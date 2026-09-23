import { createHash } from "node:crypto";
import { Timestamp, type Firestore } from "firebase-admin/firestore";

export interface AssistantCache {
  get<T>(key: string): Promise<T | null>;
  /** Concurrent writers receive the same first committed value until expiry. */
  putIfAbsent<T>(key: string, value: T, ttlSeconds: number): Promise<T>;
  /** A shared per-UID fixed one-minute window; true consumes one request. */
  rateLimit(uid: string, limit: number): Promise<boolean>;
}

const minute = 60_000;
const documentId = (value: string): string => createHash("sha256").update(value).digest("hex");
const clone = <T>(value: T): T => structuredClone(value);
function validTtl(ttlSeconds: number): void {
  if (!Number.isFinite(ttlSeconds) || ttlSeconds <= 0) throw new Error("Cache TTL must be positive");
}
function validLimit(limit: number): void {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new Error("Request limit must be a positive integer");
}

interface MemoryEntry { value: unknown; expiresAtMs: number }
interface RateEntry { window: number; count: number }

/** Emulator/test cache; never used as the distributed production rate limit. */
export class MemoryAssistantCache implements AssistantCache {
  private readonly entries = new Map<string, MemoryEntry>();
  private readonly requests = new Map<string, RateEntry>();
  constructor(private readonly clock: () => number = Date.now) {}

  async get<T>(key: string): Promise<T | null> {
    const entry = this.entries.get(key);
    if (!entry) return null;
    if (entry.expiresAtMs <= this.clock()) {
      this.entries.delete(key);
      return null;
    }
    return clone(entry.value as T);
  }

  async putIfAbsent<T>(key: string, value: T, ttlSeconds: number): Promise<T> {
    validTtl(ttlSeconds);
    const now = this.clock();
    // No await between checking and writing: a single emulator process has one
    // winner even when many requests resolve their model calls simultaneously.
    const existing = this.entries.get(key);
    if (existing && existing.expiresAtMs > now) return clone(existing.value as T);
    for (const [entryKey, entry] of this.entries) if (entry.expiresAtMs <= now) this.entries.delete(entryKey);
    this.entries.set(key, { value: clone(value), expiresAtMs: now + ttlSeconds * 1000 });
    return clone(value);
  }

  async rateLimit(uid: string, limit: number): Promise<boolean> {
    validLimit(limit);
    const window = Math.floor(this.clock() / minute);
    const existing = this.requests.get(uid);
    const entry = existing?.window === window ? existing : { window, count: 0 };
    if (entry.count >= limit) return false;
    entry.count++;
    this.requests.set(uid, entry);
    // Expired user buckets are not retained throughout an emulator session.
    for (const [key, item] of this.requests) if (item.window !== window) this.requests.delete(key);
    return true;
  }
}

/** These collections are server-only in Firestore rules. TTL deletion is an
 * operational cleanup; correctness never depends on Firestore deleting on time. */
export class FirestoreAssistantCache implements AssistantCache {
  constructor(private readonly db: Firestore, private readonly clock: () => number = Date.now) {}

  async get<T>(key: string): Promise<T | null> {
    const snapshot = await this.db.collection("assistant_cache").doc(documentId(key)).get();
    const entry = snapshot.data();
    if (!entry || typeof entry.expiresAtMs !== "number" || entry.expiresAtMs <= this.clock()) return null;
    return entry.value as T;
  }

  async putIfAbsent<T>(key: string, value: T, ttlSeconds: number): Promise<T> {
    validTtl(ttlSeconds);
    const reference = this.db.collection("assistant_cache").doc(documentId(key));
    const now = this.clock();
    return this.db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const existing = snapshot.data();
      if (existing && typeof existing.expiresAtMs === "number" && existing.expiresAtMs > now) return existing.value as T;
      const expiresAtMs = now + ttlSeconds * 1000;
      transaction.set(reference, { value, expiresAtMs, expiresAt: Timestamp.fromMillis(expiresAtMs) });
      return value;
    });
  }

  async rateLimit(uid: string, limit: number): Promise<boolean> {
    validLimit(limit);
    const window = Math.floor(this.clock() / minute);
    const reference = this.db.collection("assistant_rate_limits").doc(documentId(uid));
    return this.db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const existing = snapshot.data();
      const count = existing?.window === window && Number.isSafeInteger(existing.count) ? Number(existing.count) : 0;
      if (count >= limit) return false;
      transaction.set(reference, { window, count: count + 1, expiresAt: Timestamp.fromMillis((window + 1) * minute) });
      return true;
    });
  }
}
