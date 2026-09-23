import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { actionFor, applyAction, digest } from "./actions";
import { buildTurn } from "./dialogue";
import { hasSearchMinimum, recommend } from "./engine";
import { mergeInterpretation, validateInterpretation, type Interpretation, type LanguageModel } from "./openai";
import type { AssistantCache } from "./storage";
import { ALGORITHM_VERSION, type AssistantInput, type AssistantTurn, type Brief, type Catalog, type Result } from "./types";
import { AssistantError, legacyBrief, validateBrief, validateInput } from "./validation";

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

/** A single engine serves both callable endpoints. The model cannot order results. */
export class AssistantApplication {
  private readonly ttl: number;
  private readonly embeddings: EmbeddingIndex | null;
  private readonly pending = new Map<string, Promise<Interpretation>>();
  constructor(private readonly catalog: Catalog, private readonly cache: AssistantCache, private readonly model: LanguageModel,
    embeddings?: EmbeddingIndex | null) {
    const ttl = Number(process.env.ASSISTANT_CACHE_TTL_SECONDS ?? 3600);
    this.ttl = Number.isFinite(ttl) && ttl > 0 ? ttl : 3600;
    this.embeddings = embeddings === undefined ? loadEmbeddings(catalog) : embeddings === null ? null : validateEmbeddingIndex(embeddings, catalog);
  }
  private async interpret(input: AssistantInput): Promise<Interpretation> {
    if (!this.model.available) throw new AssistantError("failed-precondition", "AI пока не настроен на сервере. Условия сохранены; можно продолжить кнопками в ручном режиме.", { code: "ai-not-configured" });
    const key = `parse:${digest({ input, model: this.model.version, dataset: this.catalog.datasetVersion,
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
      return this.cache.putIfAbsent(key, result, this.ttl);
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
    if (validated.excluded_ids.some((id) => !ids.has(id))) throw new AssistantError("invalid-argument", "Неизвестный подрядчик в исключениях.");
    return validated;
  }
  private async semanticScores(brief: Brief): Promise<ReadonlyMap<string, number> | undefined> {
    // Negative requirements are decided by evidence, never rewarded through similarity.
    const positive = brief.preferences.filter((preference) => preference.polarity === "positive" &&
      !preference.feature_id?.startsWith("no_") &&
      (preference.feature_id !== null || !/(^|\s)(без|не|никаких|никакого|никакой|without|no)(\s|$)/iu.test(preference.text)));
    if (!this.embeddings || !positive.length || !hasSearchMinimum(brief)) return undefined;
    const query = `Категория: ${brief.category}\nФормат: ${brief.event_format}\n${positive.map((preference) =>
      `${preference.importance === "required" ? "Обязательно" : "Пожелание"}: ${preference.text}`).join("\n")}`;
    const key = `embedding:${digest({ query, model: this.embeddings.model, dimensions: this.embeddings.dimensions,
      input: this.embeddings.inputVersion, algorithm: ALGORITHM_VERSION })}`;
    let vector = await this.cache.get<number[]>(key);
    if (!vector) {
      if (!this.model.available) throw new AssistantError("failed-precondition", "Для смыслового подбора нужен серверный AI. Условия сохранены; доступен ручной режим.");
      const generated = await this.model.embed(query, this.embeddings.model, this.embeddings.dimensions);
      if (!validVector(generated, this.embeddings.dimensions)) throw new AssistantError("unavailable", "Не удалось проверить смысловую близость. Повторите запрос.");
      vector = await this.cache.putIfAbsent(key, generated, this.ttl);
    }
    if (!validVector(vector, this.embeddings.dimensions)) throw new AssistantError("unavailable", "Нужно обновить смысловой кэш на сервере.");
    return new Map(this.embeddings.profiles.map((profile) => [profile.id, cosine(vector!, profile.embedding)]));
  }
  async turn(value: unknown): Promise<AssistantTurn> {
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
    const scores = await this.semanticScores(brief);
    return buildTurn(this.catalog, brief, { mode: this.model.available ? "ai" : "basic", action: input.action,
      forceResults: input.action?.type === "show_results", semanticScores: scores,
      warnings: this.model.available ? [] : ["AI не настроен на сервере. Доступен ручной подбор по кнопкам."],
    });
  }
  async recommend(value: unknown): Promise<Result & { dataset_version: string; algorithm_version: string; mode: "ai" | "basic" }> {
    let brief = legacyBrief(value);
    if (brief.preferences.length && this.model.available) {
      const interpretation = await this.interpret({ brief, message: `Разбери только эти пожелания к одному подрядчику: ${brief.preferences[0].text}`, history: [] });
      // Legacy form already supplies explicit filters. AI may only enrich preferences.
      brief = { ...brief, preferences: interpretation.brief.preferences };
    }
    brief = this.validateCatalogBrief(brief);
    const result = recommend(this.catalog, brief, await this.semanticScores(brief));
    return { ...result, dataset_version: this.catalog.datasetVersion, algorithm_version: ALGORITHM_VERSION, mode: this.model.available ? "ai" : "basic" };
  }
}
