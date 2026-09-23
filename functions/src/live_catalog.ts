import type { DocumentSnapshot, Firestore } from "firebase-admin/firestore";
import { digest } from "./actions";
import { loadCatalog } from "./catalog";
import type { Availability, Catalog, Contractor, LiveDatePolicy } from "./types";

const dayMs = 86_400_000;
type Row = Record<string, unknown>;
const row = (value: unknown): Row | null => value !== null && typeof value === "object" && !Array.isArray(value)
  ? value as Row : null;
const text = (value: unknown, max: number): value is string => typeof value === "string" && value.trim().length > 0 && value.length <= max;
const strings = (value: unknown, max: number): value is string[] => Array.isArray(value) && value.length > 0 && value.length <= max &&
  value.every((entry) => text(entry, 200));

/** Almaty uses UTC+5; boundaries are calendar dates, independent of the server timezone. */
export function liveDatePolicy(now: Date): LiveDatePolicy {
  if (!Number.isFinite(now.getTime())) throw new Error("Invalid live catalog clock");
  const almaty = new Date(now.getTime() + 5 * 3_600_000);
  const firstDate = almaty.toISOString().slice(0, 10);
  const lastDate = new Date(Date.parse(`${firstDate}T00:00:00Z`) + 365 * dayMs).toISOString().slice(0, 10);
  return { firstDate, lastDate };
}

function validDate(date: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return false;
  const value = new Date(`${date}T00:00:00Z`);
  return Number.isFinite(value.getTime()) && value.toISOString().slice(0, 10) === date;
}

function timestampMillis(value: unknown): number | null {
  if (value instanceof Date) return Number.isFinite(value.getTime()) ? value.getTime() : null;
  const timestamp = row(value);
  if (!timestamp || typeof timestamp.toMillis !== "function") return null;
  const result: unknown = timestamp.toMillis();
  return typeof result === "number" && Number.isFinite(result) ? result : null;
}

/** A missing, malformed, future-dated or 30-day-old calendar never means available. */
export function calendarAvailability(raw: unknown, ownerId: string, date: string, now: Date): Availability {
  if (!validDate(date)) return "unconfirmed";
  const data = row(raw);
  const year = Number(date.slice(0, 4));
  const month = Number(date.slice(5, 7));
  if (!data || data.ownerId !== ownerId || data.year !== year || data.month !== month) return "unconfirmed";
  const confirmed = timestampMillis(data.confirmedAt);
  const nowMs = now.getTime();
  if (confirmed === null || !Number.isFinite(nowMs) || confirmed > nowMs || nowMs - confirmed >= 30 * dayMs) return "unconfirmed";
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const busyDays = data.busyDays;
  if (!Array.isArray(busyDays) || busyDays.length > daysInMonth || new Set(busyDays).size !== busyDays.length ||
    !busyDays.every((day) => Number.isInteger(day) && day >= 1 && day <= daysInMonth)) return "unconfirmed";
  return busyDays.includes(Number(date.slice(8, 10))) ? "busy" : "available";
}

function publicContractor(id: string, data: Row): Contractor | null {
  const content = row(data.content);
  if (!content || data.ownerId !== id || data.published !== true ||
    !Number.isSafeInteger(data.revision) || Number(data.revision) < 1 ||
    !Number.isSafeInteger(data.profileRevision) || Number(data.profileRevision) < 1 ||
    !text(content.name, 200) || !text(content.city, 200) || !text(content.description, 5000) ||
    !text(content.contact, 500) || !strings(content.categories, 20) || !strings(content.formats, 20) ||
    !strings(content.languages, 20) || !Number.isSafeInteger(content.price) || Number(content.price) < 1 || Number(content.price) > 1_000_000_000) return null;
  if (content.maxHours !== null && (typeof content.maxHours !== "number" || !Number.isFinite(content.maxHours) || content.maxHours <= 0 || content.maxHours > 48)) return null;
  const urls = content.portfolioUrls;
  if (!Array.isArray(urls) || urls.length > 5 || !urls.every((url) => {
    if (typeof url !== "string") return false;
    try { const parsed = new URL(url); return parsed.protocol === "https:" && parsed.hostname.length > 0; }
    catch { return false; }
  })) return null;
  return {
    id, anon_name: content.name, city: content.city, description: content.description,
    categories: [...content.categories], event_formats: [...content.formats], languages: [...content.languages],
    busy_dates: [], price_from_kzt: Number(content.price), max_hours: content.maxHours,
    synthetic: false, city_imputed: false, price_imputed: false,
    is_live: true, contact: content.contact, portfolio_urls: [...urls],
  };
}

async function readDocuments(db: Firestore, paths: string[]): Promise<DocumentSnapshot[]> {
  const results: DocumentSnapshot[] = [];
  for (let index = 0; index < paths.length; index += 200) {
    results.push(...await db.getAll(...paths.slice(index, index + 200).map((path) => db.doc(path))));
  }
  return results;
}

/** Fresh server reads expose only the approved public snapshot of an active, undeleted account. */
export async function loadLiveCatalog(db: Firestore, now: Date = new Date()): Promise<Catalog> {
  const snapshotNow = new Date(now.getTime());
  const policy = liveDatePolicy(snapshotNow);
  const publications = await db.collection("publishedProfiles").where("published", "==", true).get();
  const candidates = publications.docs.flatMap((document) => {
    const data = row(document.data());
    const contractor = data && publicContractor(document.id, data);
    return contractor ? [{ contractor, revision: data!.revision, profileRevision: data!.profileRevision }] : [];
  }).sort((a, b) => a.contractor.id.localeCompare(b.contractor.id, "en"));
  const checks = await readDocuments(db, candidates.flatMap(({ contractor }) => [
    `accounts/${contractor.id}`, `deletedAccounts/${contractor.id}`,
  ]));
  const visible = candidates.filter((_, index) => checks[index * 2]?.data()?.status === "active" && !checks[index * 2 + 1]?.exists);
  const contractors = visible.map(({ contractor }) => contractor);
  const profileVersions = new Map(visible.map((entry) => [entry.contractor.id, `sha256:${digest(entry)}`]));
  const ontology = loadCatalog();
  return {
    source: "live", contractors, datasetVersion: `live:sha256:${digest({ publications: visible, datePolicy: policy })}`,
    featureVersion: `live-unknown-v1:${ontology.featureVersion}`, featureDefinitions: ontology.featureDefinitions,
    features: new Map(contractors.map((contractor) => [contractor.id, []])), profileVersions, liveDatePolicy: policy,
    resolveAvailability: async (date) => {
      const result = new Map<string, Availability>(contractors.map((contractor) => [contractor.id, "unconfirmed"]));
      if (!validDate(date) || date < policy.firstDate || date > policy.lastDate) return result;
      const calendars = await readDocuments(db, contractors.map((contractor) => `calendars/${contractor.id}/months/${date.slice(0, 7)}`));
      contractors.forEach((contractor, index) => result.set(contractor.id,
        calendarAvailability(calendars[index]?.data(), contractor.id, date, snapshotNow)));
      return result;
    },
  };
}
