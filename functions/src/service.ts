import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { actionFor, applyAction, digest } from "./actions";
import { buildTurn } from "./dialogue";
import { evaluate, hasSearchMinimum, recommend } from "./engine";
import { mergeInterpretation, validateInterpretation, type Interpretation, type LanguageModel } from "./openai";
import type { AssistantCache } from "./storage";
import { ALGORITHM_VERSION, type AssistantInput, type AssistantTurn, type Brief, type Catalog, type Result } from "./types";
import { AssistantError, legacyBrief, requestSource, validateBrief, validateInput } from "./validation";

export interface EmbeddingIndex {
  schemaVersion: number; datasetVersion: string; featureVersion: string;
  model: string; dimensions: number; inputVersion: string;
  profiles: { id: string; embedding: number[] }[];
}
export function validVector(vector: unknown, dimensions: number): vector is number[] {
  return Array.isArray(vector) && vector.length === dimensions && vector.every((value) => typeof value === "number" && Number.isFinite(value)) && vector.some((value) => value !== 0);
}
export function validateEmbeddingIndex(value: unknown, catalog: Catalog): EmbeddingIndex {
  const artifact = value as EmbeddingIndex | null;
  const fail = (): never => { throw new AssistantError("failed-precondition", "Смысловой индекс не соответствует каталогу. Нужно обновить серверные данные."); };
  if (!artifact || artifact.schemaVersion !== 1 || artifact.datasetVersion !== catalog.datasetVersion || artifact.featureVersion !== catalog.featureVersion ||
      artifact.model !== "text-embedding-3-small" || artifact.dimensions !== 1536 || !Array.isArray(artifact.profiles)) return fail();
  const labels = new Map(catalog.featureDefinitions.map((definition) => [definition.key, definition.label]));
  const inputs = catalog.contractors.map((contractor) => [
    `Категории: ${contractor.categories.join(", ")}`, contractor.description,
    ...(catalog.features.get(contractor.id) ?? []).map((feature) =>
      `${feature.polarity === "supports" ? "Указано в профиле" : "Профиль противоречит пожеланию"} «${labels.get(feature.key)}»: ${feature.quote}`),
  ].join("\n"));
  const expectedInput = `sha256:${createHash("sha256").update(JSON.stringify(inputs)).digest("hex")}`;
  if (artifact.inputVersion !== expectedInput || artifact.profiles.length !== catalog.contractors.length) return fail();
  const vectors = new Map(artifact.profiles.map((profile) => [profile.id, profile.embedding]));
  if (vectors.size !== catalog.contractors.length || catalog.contractors.some((item) => !validVector(vectors.get(item.id), artifact.dimensions))) return fail();
  return artifact;
}
function loadEmbeddings(catalog: Catalog): EmbeddingIndex | null {
  const file = resolve(__dirname, "../data/embeddings.json");
  if (!existsSync(file)) return null;
  let value: unknown;
  try { value = JSON.parse(readFileSync(file, "utf8")); } catch { throw new AssistantError("failed-precondition", "Не удалось прочитать смысловой индекс на сервере."); }
  return validateEmbeddingIndex(value, catalog);
}
export function cosine(a: number[], b: number[]): number {
  let dot = 0; let normA = 0; let normB = 0;
  for (let index = 0; index < a.length; index++) { dot += a[index] * b[index]; normA += a[index] ** 2; normB += b[index] ** 2; }
  return Math.max(-1, Math.min(1, dot / Math.sqrt(normA * normB)));
}

export interface AssistantContext { uid?: string; source?: "live" | "demo" }
const liveEmbeddingModel = "text-embedding-3-small";
const liveEmbeddingDimensions = 1536;
// UTF-8 bytes provide a conservative bound below the provider's per-input
// token ceiling. Full original constraints still participate in filtering and
// evidence; only this auxiliary similarity input is bounded.
function embeddingInput(text: string): string {
  let bytes = 0;
  let result = "";
  for (const character of text) {
    const length = Buffer.byteLength(character, "utf8");
    if (bytes + length > 8_000) break;
    bytes += length;
    result += character;
  }
  return result;
}

/** A single engine serves both callable endpoints. The model cannot order results. */
export class AssistantApplication {
  private readonly ttl: number;
  private readonly embeddings: EmbeddingIndex | null;
  private readonly pending = new Map<string, Promise<Interpretation>>();
  constructor(private readonly catalog: Catalog, private readonly cache: AssistantCache, private readonly model: LanguageModel,
    embeddings?: EmbeddingIndex | null, private readonly context: AssistantContext = {}) {
    const ttl = Number(process.env.ASSISTANT_CACHE_TTL_SECONDS ?? 3600);
    this.ttl = Number.isFinite(ttl) && ttl > 0 ? ttl : 3600;
    if (context.source && context.source !== (catalog.source ?? "demo")) throw new AssistantError("failed-precondition", "Источник каталога не совпадает с запросом.");
    this.embeddings = catalog.source === "live" ? null
      : embeddings === undefined ? loadEmbeddings(catalog) : embeddings === null ? null : validateEmbeddingIndex(embeddings, catalog);
  }
  private get privateMetadata(): { ownerUid?: string } { return this.context.uid ? { ownerUid: this.context.uid } : {}; }
  private checkSource(value: unknown): void {
    if (requestSource(value) !== (this.catalog.source ?? "demo")) throw new AssistantError("invalid-argument", "Источник запроса не совпадает с каталогом.");
  }
  private async interpret(input: AssistantInput): Promise<Interpretation> {
    if (!this.model.available) throw new AssistantError("failed-precondition", "AI пока не настроен на сервере. Условия сохранены; можно продолжить кнопками в ручном режиме.", { code: "ai-not-configured" });
    const key = `parse:${digest({ input, uid: this.context.uid ?? null, source: this.catalog.source ?? "demo", model: this.model.version, dataset: this.catalog.datasetVersion,
      features: this.catalog.featureVersion, algorithm: ALGORITHM_VERSION,
      // Relative dates must not reuse yesterday's interpretation.
      day: new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Almaty" }).format(new Date()),
    })}`;
    const cached = await this.cache.get<Interpretation>(key);
    if (cached) return validateInterpretation(cached, this.catalog);
    const pending = this.pending.get(key);
    if (pending) return pending;
    const work = (async () => {
      const result = validateInterpretation(await this.model.extract(input, this.catalog), this.catalog);
      return this.cache.putIfAbsent(key, result, this.ttl, this.privateMetadata);
    })();
    this.pending.set(key, work);
    try { return await work; } finally { this.pending.delete(key); }
  }
  private validateCatalogBrief(brief: Brief): Brief {
    const validated = validateBrief(brief);
    const keys = new Set(this.catalog.featureDefinitions.map((feature) => feature.key));
    if (validated.preferences.some((preference) => preference.feature_id && !keys.has(preference.feature_id))) {
      throw new AssistantError("invalid-argument", "Неизвестный признак пожелания. Опишите его текстом.");
    }
    const ids = new Set(this.catalog.contractors.map((item) => item.id));
    // A live publication may be withdrawn between turns; retaining its exclusion
    // is harmless and must not make the user's next request invalid forever.
    if (this.catalog.source !== "live" && validated.excluded_ids.some((id) => !ids.has(id))) throw new AssistantError("invalid-argument", "Неизвестный подрядчик в исключениях.");
    return validated;
  }
  private async catalogForBrief(brief: Brief): Promise<Catalog> {
    const policy = this.catalog.liveDatePolicy;
    if (this.catalog.source !== "live" || !brief.date || !policy || brief.date < policy.firstDate || brief.date > policy.lastDate || !this.catalog.resolveAvailability) return this.catalog;
    return { ...this.catalog, availabilityDate: brief.date, availability: await this.catalog.resolveAvailability(brief.date) };
  }
  private async semanticScores(brief: Brief, catalog: Catalog = this.catalog): Promise<ReadonlyMap<string, number> | undefined> {
    // Negative requirements are decided by evidence, never rewarded through similarity.
    const positive = brief.preferences.filter((preference) => preference.polarity === "positive" &&
      !preference.feature_id?.startsWith("no_") &&
      (preference.feature_id !== null || !/(^|\s)(без|не|никаких|никакого|никакой|without|no)(\s|$)/iu.test(preference.text)));
    if (!positive.length || !hasSearchMinimum(brief)) return undefined;
    const query = embeddingInput(`Категория: ${brief.category}\nФормат: ${brief.event_format}\n${positive.map((preference) =>
      `${preference.importance === "required" ? "Обязательно" : "Пожелание"}: ${preference.text}`).join("\n")}`);
    if (catalog.source === "live") return this.liveSemanticScores(brief, catalog, query);
    if (!this.embeddings) return undefined;
    const key = `embedding:${digest({ query, model: this.embeddings.model, dimensions: this.embeddings.dimensions,
      uid: this.context.uid ?? null, source: "demo", input: this.embeddings.inputVersion, algorithm: ALGORITHM_VERSION })}`;
    let vector = await this.cache.get<number[]>(key);
    if (!vector) {
      if (!this.model.available) throw new AssistantError("failed-precondition", "Для смыслового подбора нужен серверный AI. Условия сохранены; доступен ручной режим.");
      const generated = await this.model.embed(query, this.embeddings.model, this.embeddings.dimensions);
      if (!validVector(generated, this.embeddings.dimensions)) throw new AssistantError("unavailable", "Не удалось проверить смысловую близость. Повторите запрос.");
      vector = await this.cache.putIfAbsent(key, generated, this.ttl, this.privateMetadata);
    }
    if (!validVector(vector, this.embeddings.dimensions)) throw new AssistantError("unavailable", "Нужно обновить смысловой кэш на сервере.");
    return new Map(this.embeddings.profiles.map((profile) => [profile.id, cosine(vector!, profile.embedding)]));
  }
  private async liveSemanticScores(brief: Brief, catalog: Catalog, query: string): Promise<ReadonlyMap<string, number> | undefined> {
    // Missing credentials deliberately retain the explicit basic typed workflow.
    // Public descriptions never become reviewed factual preference evidence.
    if (!this.model.available) return undefined;
    const candidates = evaluate(catalog, brief).eligible.map((item) => item.contractor);
    if (!candidates.length) return undefined;
    const queryKey = `live-query:${digest({ uid: this.context.uid ?? null, query, model: liveEmbeddingModel,
      dimensions: liveEmbeddingDimensions, algorithm: ALGORITHM_VERSION })}`;
    const entries = [{ key: queryKey, text: query, id: null as string | null }, ...candidates.map((contractor) => {
      const text = embeddingInput(`Категории: ${contractor.categories.join(", ")}\n${contractor.description}`);
      return { id: contractor.id, text, key: `live-profile:${digest({ text, revision: catalog.profileVersions?.get(contractor.id) ?? null,
        model: liveEmbeddingModel, dimensions: liveEmbeddingDimensions })}` };
    })];
    const vectors = new Map<string, number[]>();
    const missing: typeof entries = [];
    const cached = await Promise.all(entries.map((entry) => this.cache.get<number[]>(entry.key)));
    entries.forEach((entry, index) => {
      const vector = cached[index];
      if (vector === null) { if (!missing.some((item) => item.key === entry.key)) missing.push(entry); }
      else if (!validVector(vector, liveEmbeddingDimensions)) throw new AssistantError("unavailable", "Нужно обновить смысловой кэш на сервере.");
      else vectors.set(entry.key, vector);
    });
    // Embeddings accepts batched inputs and returns indices, not an implicit
    // guarantee of response ordering. The adapter validates all indices.
    const batches: (typeof entries)[] = [];
    for (let index = 0; index < missing.length; index += 32) batches.push(missing.slice(index, index + 32));
    await Promise.all(batches.map(async (batch) => {
      const texts = batch.map((entry) => entry.text);
      const generated = this.model.embedMany ? await this.model.embedMany(texts, liveEmbeddingModel, liveEmbeddingDimensions)
        : await Promise.all(texts.map((text) => this.model.embed(text, liveEmbeddingModel, liveEmbeddingDimensions)));
      if (generated.length !== batch.length || generated.some((vector) => !validVector(vector, liveEmbeddingDimensions))) {
        throw new AssistantError("unavailable", "Не удалось проверить смысловую близость. Повторите запрос.");
      }
      await Promise.all(batch.map(async (entry, index) => {
        const vector = await this.cache.putIfAbsent(entry.key, generated[index], this.ttl, entry.id === null ? this.privateMetadata : undefined);
        if (!validVector(vector, liveEmbeddingDimensions)) throw new AssistantError("unavailable", "Нужно обновить смысловой кэш на сервере.");
        vectors.set(entry.key, vector);
      }));
    }));
    const queryVector = vectors.get(queryKey)!;
    return new Map(entries.filter((entry) => entry.id !== null).map((entry) => [entry.id!, cosine(queryVector, vectors.get(entry.key)!)]));
  }
  async turn(value: unknown): Promise<AssistantTurn> {
    this.checkSource(value);
    const input = validateInput(value);
    this.validateCatalogBrief(input.brief);
    let brief: Brief;
    let interpretation: Interpretation | undefined;
    if (input.action) brief = applyAction(input.brief, input.action);
    else {
      interpretation = await this.interpret(input);
      brief = mergeInterpretation(input.brief, interpretation);
    }
    brief = this.validateCatalogBrief(brief);
    if (interpretation?.operation === "clarify") {
      // Conflicting values are never silently treated as a completed request.
      const field = interpretation.question_field!;
      const choices = ["city", "category", "event_format", "language", "date"].includes(field) ? interpretation.choices : [];
      return {
        brief, message: interpretation.question!, question_field: field, result: null, mode: "ai", warnings: [],
        actions: [...choices.map((choice) => actionFor(brief, choice, "set_field", field, choice)),
          actionFor(brief, "Уточнить условие", field === "budget_kzt" ? "pick_budget" : field === "date" ? "pick_date" : "pick_field", field)],
        dataset_version: this.catalog.datasetVersion, algorithm_version: ALGORITHM_VERSION,
      };
    }
    const catalog = await this.catalogForBrief(brief);
    const scores = await this.semanticScores(brief, catalog);
    return buildTurn(catalog, brief, { mode: this.model.available ? "ai" : "basic", action: input.action,
      forceResults: input.action?.type === "show_results", semanticScores: scores,
      warnings: this.model.available ? [] : ["AI не настроен на сервере. Доступен ручной подбор по кнопкам."],
    });
  }
  async recommend(value: unknown): Promise<Result & { dataset_version: string; algorithm_version: string; mode: "ai" | "basic" }> {
    this.checkSource(value);
    let brief = legacyBrief(value);
    if (brief.preferences.length) {
      const interpretation = await this.interpret({ source: this.catalog.source ?? "demo", brief, message: `Разбери только эти пожелания к одному подрядчику: ${brief.preferences[0].text}`, history: [] });
      // Legacy form already supplies explicit filters. AI may only enrich preferences.
      brief = { ...brief, preferences: interpretation.brief.preferences };
    }
    brief = this.validateCatalogBrief(brief);
    const catalog = await this.catalogForBrief(brief);
    const result = recommend(catalog, brief, await this.semanticScores(brief, catalog));
    return { ...result, dataset_version: this.catalog.datasetVersion, algorithm_version: ALGORITHM_VERSION, mode: this.model.available ? "ai" : "basic" };
  }
}
