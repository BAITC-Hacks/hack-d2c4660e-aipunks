import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { loadCatalog } from "./catalog";
import { loadLiveCatalog } from "./live_catalog";
import { createLanguageModel } from "./openai";
import { AssistantApplication } from "./service";
import { FirestoreAssistantCache, MemoryAssistantCache, type AssistantCache } from "./storage";
import { AssistantError, requestSource } from "./validation";

export interface RuntimeAuth {
  uid: string;
  token: { firebase?: { sign_in_provider?: string } };
}
export interface RuntimeRequest { auth?: RuntimeAuth; data: unknown }
export interface AccountState { exists: boolean; status: string | null; deleted: boolean }
export interface RuntimeApplication {
  turn(input: unknown): Promise<unknown>;
  recommend(input: unknown): Promise<unknown>;
}
export interface RuntimeDependencies {
  cache: AssistantCache;
  readAccount: (uid: string) => Promise<AccountState>;
  application: (context: { uid: string; source: "live" | "demo" }) => RuntimeApplication | Promise<RuntimeApplication>;
  requestsPerMinute?: number;
}

/** Configuration mistakes never silently disable the request budget. */
export function configuredRateLimit(value: string | undefined): number {
  if (value === undefined || value.trim() === "") return 20;
  const limit = Number(value);
  return Number.isSafeInteger(limit) && limit > 0 && limit <= 1000 ? limit : 20;
}

export function runtimeConfiguration(environment: NodeJS.ProcessEnv = process.env) {
  const emulator = environment.FUNCTIONS_EMULATOR === "true";
  return {
    emulator,
    region: environment.ASSISTANT_REGION?.trim() || "us-central1",
    enforceAppCheck: environment.ASSISTANT_ENFORCE_APP_CHECK?.trim().toLowerCase() === "true",
    requestsPerMinute: configuredRateLimit(environment.ASSISTANT_RATE_LIMIT_PER_MINUTE),
    storage: emulator && environment.ASSISTANT_STORAGE?.trim().toLowerCase() !== "firestore" ? "memory" as const : "firestore" as const,
  };
}

export function assertEmulatorConfiguration(emulator: boolean, firestoreHost: string | undefined): void {
  if (emulator && !firestoreHost?.trim()) {
    throw new HttpsError("failed-precondition", "Запустите эмуляторы Auth, Firestore и Functions вместе.");
  }
}

export async function assertAssistantAccess(
  auth: RuntimeAuth | undefined,
  readAccount: RuntimeDependencies["readAccount"],
): Promise<string> {
  if (!auth?.uid) throw new HttpsError("unauthenticated", "Для подбора нужен действующий сеанс.");
  const state = await readAccount(auth.uid);
  if (state.deleted || (state.exists && ["suspended", "deactivated"].includes(state.status ?? ""))) {
    throw new HttpsError("permission-denied", "Доступ к помощнику для этого аккаунта ограничен.");
  }
  return auth.uid;
}

/** Never echo SDK/model/network messages, input payloads, or credentials. */
export function safeCallableError(error: unknown): HttpsError {
  const code = error instanceof AssistantError || error instanceof HttpsError ? error.code : "unavailable";
  switch (code) {
    case "unauthenticated": return new HttpsError(code, "Не удалось подтвердить сеанс. Повторите вход.");
    case "permission-denied": return new HttpsError(code, "Доступ к помощнику для этого аккаунта ограничен.");
    case "invalid-argument": return new HttpsError(code, "Не удалось применить запрос. Проверьте условия и выбранные варианты.");
    case "failed-precondition": return new HttpsError(code, "Помощник пока не готов к этому запросу. Повторите позже или продолжите кнопками.");
    case "resource-exhausted": return new HttpsError(code, "Достигнут лимит запросов. Повторите через минуту.");
    default: return new HttpsError("unavailable", "Помощник временно недоступен. Условия сохранены — повторите или продолжите кнопками.");
  }
}

/** Injectable wrapper keeps access/rate checks ahead of every cache/model call. */
export function createCallableHandler(method: "turn" | "recommend", dependencies: RuntimeDependencies) {
  return async (request: RuntimeRequest): Promise<unknown> => {
    try {
      const uid = await assertAssistantAccess(request.auth, dependencies.readAccount);
      if (!await dependencies.cache.rateLimit(uid, dependencies.requestsPerMinute ?? 20)) {
        throw new HttpsError("resource-exhausted", "Request limit reached");
      }
      const source = requestSource(request.data);
      const application = await dependencies.application({ uid, source });
      return await application[method](request.data);
    } catch (error) {
      throw safeCallableError(error);
    }
  };
}

const configuration = runtimeConfiguration();
const isEmulator = configuration.emulator;
const openaiApiKey = defineSecret("OPENAI_API_KEY");
let dependencies: RuntimeDependencies | undefined;

function runtimeDependencies(): RuntimeDependencies {
  if (dependencies) return dependencies;
  // Starting only the Functions emulator must not silently send account-state
  // reads to production Firestore through Application Default Credentials.
  assertEmulatorConfiguration(isEmulator, process.env.FIRESTORE_EMULATOR_HOST);
  if (!getApps().length) initializeApp();
  const db = getFirestore();
  const cache: AssistantCache = configuration.storage === "memory" ? new MemoryAssistantCache() : new FirestoreAssistantCache(db);
  dependencies = {
    cache,
    requestsPerMinute: configuration.requestsPerMinute,
    readAccount: async (uid) => {
      // Tombstones also protect anonymous identities: absence of accounts is
      // expected for guests and must never bypass a deletion restriction.
      const [account, deleted] = await Promise.all([
        db.collection("accounts").doc(uid).get(),
        db.collection("deletedAccounts").doc(uid).get(),
      ]);
      const status = account.data()?.status;
      return { exists: account.exists, status: typeof status === "string" ? status : null, deleted: deleted.exists };
    },
    application: async (context) => {
      // The live snapshot and calendar resolver are recreated on every turn:
      // publication changes and withdrawals cannot survive in an app singleton.
      const catalog = context.source === "live" ? await loadLiveCatalog(db) : loadCatalog();
      // In the emulator .secret.local is loaded into env by Firebase. Do not
      // declare a bound cloud secret there, which would trigger cloud lookups.
      const key = process.env.OPENAI_API_KEY || (isEmulator ? undefined : openaiApiKey.value());
      return new AssistantApplication(catalog, cache, createLanguageModel(key), undefined, context);
    },
  };
  return dependencies;
}

const options = {
  region: configuration.region,
  timeoutSeconds: 30,
  memory: "256MiB" as const,
  maxInstances: 3,
  enforceAppCheck: configuration.enforceAppCheck,
  secrets: isEmulator ? [] : [openaiApiKey],
};

async function dispatch(method: "turn" | "recommend", request: RuntimeRequest): Promise<unknown> {
  try {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required");
    return await createCallableHandler(method, runtimeDependencies())(request);
  } catch (error) {
    throw safeCallableError(error);
  }
}

export const assistantTurn = onCall(options, (request) => dispatch("turn", request));
export const recommendContractors = onCall(options, (request) => dispatch("recommend", request));
