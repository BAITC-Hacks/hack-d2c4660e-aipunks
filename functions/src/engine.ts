import { CALENDAR_END, CALENDAR_START, type Brief, type Catalog, type Contractor, type Evidence, type Preference, type Result } from "./types";
import { AssistantError, validateBrief } from "./validation";

export const dateIsCovered = (date: string | null, catalog?: Catalog): boolean => {
  if (date === null) return false;
  if (catalog?.source === "live") return Boolean(catalog.liveDatePolicy &&
    date >= catalog.liveDatePolicy.firstDate && date <= catalog.liveDatePolicy.lastDate);
  return date >= CALENDAR_START && date <= CALENDAR_END;
};
export const hasSearchMinimum = (brief: Brief): boolean => Boolean(brief.city && brief.category && brief.event_format);

export function preferenceEvidence(catalog: Catalog, contractor: Contractor, preference: Preference): Evidence {
  const features = catalog.features.get(contractor.id) ?? [];
  const matches = preference.feature_id ? features.filter((item) => item.key === preference.feature_id) : [];
  // Opposing evidence is treated conservatively; a flattering quotation must not hide a contradiction.
  const isContradiction = (polarity: "supports" | "contradicts") =>
    preference.polarity === "positive" ? polarity === "contradicts" : polarity === "supports";
  const feature = matches.find((item) => isContradiction(item.polarity)) ?? matches[0];
  return {
    feature_id: preference.feature_id ?? `unmapped:${preference.text}`,
    quote: feature?.quote ?? "",
    status: !feature ? "unknown" : isContradiction(feature.polarity) ? "contradicted" : "supported",
  };
}

export function uncheckedFields(brief: Brief, catalog?: Catalog): string[] {
  const result: string[] = [];
  if (!brief.city) result.push("Город не задан");
  if (!brief.category) result.push("Категория не задана");
  if (!brief.event_format) result.push("Формат мероприятия не задан");
  if (!brief.date) result.push("Дата не проверена");
  else if (!dateIsCovered(brief.date, catalog)) result.push(catalog?.source === "live"
    ? catalog.liveDatePolicy
      ? `Дата за пределами доступного календаря ${catalog.liveDatePolicy.firstDate}–${catalog.liveDatePolicy.lastDate}; доступность не проверена`
      : "Доступность на дату не проверена: календарь недоступен"
    : "Дата за пределами календаря 23.09–31.12.2026");
  if (brief.budget_kzt === null) result.push("Бюджет подрядчика не задан");
  else if (brief.budget_scope === "event") result.push("Указан общий бюджет; бюджет подрядчика не задан");
  return result;
}

const rejectionLabels: Record<string, string> = {
  busy: "заняты на дату", budget: "выше бюджета", format: "не берут этот формат",
  unconfirmed: "доступность на дату не подтверждена",
  language: "не работают на выбранном языке", hours: "не подходят по длительности",
  preference: "противоречат обязательному пожеланию", excluded: "уже отклонены вами",
};

export interface EvaluatedProfile {
  contractor: Contractor; evidence: Evidence[]; score: number; unchecked: string[];
  contradictionCount: number; supportedCount: number; semanticScore: number;
}
export interface Evaluation { pool: Contractor[]; eligible: EvaluatedProfile[]; rejected: Record<string, number>; unchecked: string[] }

/** No model, network, clock, implicit default date or random ordering in this engine. */
export function evaluate(catalog: Catalog, rawBrief: Brief, semanticScores?: ReadonlyMap<string, number>): Evaluation {
  const brief = validateBrief(rawBrief);
  const unchecked = uncheckedFields(brief, catalog);
  const pool = catalog.contractors.filter((item) => (!brief.city || item.city === brief.city) &&
    (!brief.category || item.categories.includes(brief.category)));
  const eligible: EvaluatedProfile[] = [];
  const rejected: Record<string, number> = {};
  for (const contractor of pool) {
    const evidence = brief.preferences.map((preference) => preferenceEvidence(catalog, contractor, preference));
    const availability = catalog.availabilityDate === brief.date ? catalog.availability?.get(contractor.id) : undefined;
    const calendarRejection = !dateIsCovered(brief.date, catalog) ? null
      : catalog.source === "live" ? availability === "available" ? null : availability === "busy" ? "busy" : "unconfirmed"
      : contractor.busy_dates.includes(brief.date!) ? "busy" : null;
    const reason = brief.excluded_ids.includes(contractor.id) ? "excluded"
      : calendarRejection ? calendarRejection
      : brief.budget_scope === "contractor" && brief.budget_kzt !== null && contractor.price_from_kzt > brief.budget_kzt ? "budget"
      : brief.event_format && !contractor.event_formats.includes(brief.event_format) ? "format"
      : brief.language && !contractor.languages.includes(brief.language) ? "language"
      : brief.hours !== null && contractor.max_hours !== null && contractor.max_hours < brief.hours ? "hours"
      : evidence.some((item, index) => item.status === "contradicted" && brief.preferences[index].importance === "required") ? "preference"
      : null;
    if (reason) { rejected[reason] = (rejected[reason] ?? 0) + 1; continue; }
    const profileUnchecked = [...unchecked];
    if (brief.hours !== null && contractor.max_hours === null) profileUnchecked.push("Длительность не подтверждена");
    brief.preferences.forEach((preference, index) => {
      if (evidence[index].status === "unknown") profileUnchecked.push(`Не подтверждено: ${preference.text}`);
    });
    let score = 0;
    evidence.forEach((item, index) => {
      const weight = brief.preferences[index].importance === "required" ? 100 : 20;
      score += item.status === "supported" ? weight : item.status === "contradicted" ? -weight : 0;
    });
    const similarity = semanticScores?.get(contractor.id) ?? 0;
    if (!Number.isFinite(similarity) || similarity < -1 || similarity > 1) {
      throw new AssistantError("unavailable", "Не удалось проверить смысловой рейтинг. Повторите запрос.", { code: "invalid-semantic-score" });
    }
    eligible.push({ contractor, evidence, score, unchecked: profileUnchecked,
      contradictionCount: evidence.filter((item) => item.status === "contradicted").length,
      supportedCount: evidence.filter((item) => item.status === "supported").length,
      semanticScore: Math.round(similarity * 1_000_000) / 1_000_000,
    });
  }
  eligible.sort((a, b) => a.contradictionCount - b.contradictionCount || b.supportedCount - a.supportedCount ||
    b.semanticScore - a.semanticScore || a.contractor.price_from_kzt - b.contractor.price_from_kzt ||
    a.contractor.id.localeCompare(b.contractor.id, "en"));
  return { pool, eligible, rejected, unchecked };
}

function excerpt(text: string): string {
  const trimmed = text.trim();
  if (trimmed.length <= 200) return trimmed;
  const boundary = trimmed.lastIndexOf(" ", 200);
  return trimmed.slice(0, boundary > 80 ? boundary : 200);
}

function explain(catalog: Catalog, item: EvaluatedProfile, brief: Brief): string {
  const { contractor, evidence } = item;
  const relevantIndex = evidence.findIndex((entry) => entry.status === "contradicted");
  const supportedIndex = evidence.findIndex((entry) => entry.status === "supported");
  const chosenIndex = relevantIndex >= 0 ? relevantIndex : supportedIndex;
  const sourceFeature = (catalog.features.get(contractor.id) ?? []).find((entry) => entry.polarity === "supports");
  let explanation = chosenIndex >= 0
    ? `${evidence[chosenIndex].status === "supported" ? "Есть подтверждение пожелания" : "Есть противоречие пожеланию"} «${brief.preferences[chosenIndex].text}»: «${excerpt(evidence[chosenIndex].quote)}».`
    : `Из профиля: «${excerpt(sourceFeature?.quote ?? contractor.description)}».`;
  const unknownRequired = brief.preferences.filter((preference, i) => preference.importance === "required" && evidence[i].status === "unknown");
  if (unknownRequired.length) explanation += ` Обязательное условие нужно подтвердить: ${unknownRequired.map((item) => item.text).join(", ")}.`;
  return explanation;
}

export function recommend(catalog: Catalog, rawBrief: Brief, semanticScores?: ReadonlyMap<string, number>): Result {
  const brief = validateBrief(rawBrief);
  if (!hasSearchMinimum(brief)) {
    throw new AssistantError("invalid-argument", "Для подбора нужны город, категория и формат мероприятия.", { code: "missing-search-minimum" });
  }
  const { pool, eligible, rejected, unchecked } = evaluate(catalog, brief, semanticScores);
  const recommendations = eligible.slice(0, 3).map((item) => ({
    contractor: item.contractor, explanation: explain(catalog, item, brief), unchecked: item.unchecked, evidence: item.evidence,
  }));
  const preliminary = unchecked.length > 0 || recommendations.some((item) => item.unchecked.length > 0);
  const rejectedText = Object.entries(rejected).map(([reason, count]) => `${count} — ${rejectionLabels[reason]}`).join("; ");
  let summary = catalog.source === "live" && catalog.contractors.length === 0 ? "В живом каталоге пока нет опубликованных подрядчиков."
    : pool.length === 0 ? "В этом городе такой категории пока нет в каталоге."
    : eligible.length === 0 ? `Никто не проходит по заданным условиям. ${rejectedText}.`
    : `${preliminary ? "Предварительно подходят" : "Проходят по указанным условиям"} ${eligible.length} из ${pool.length}; показано ${recommendations.length}.`;
  if (eligible.length && rejectedText) summary += ` Исключены: ${rejectedText}.`;
  if (!dateIsCovered(brief.date, catalog)) summary += " Доступность на дату не проверена.";
  else if (catalog.source === "live" && eligible.length) summary += " Доступность на дату подтверждена актуальным календарём.";
  if (brief.budget_kzt === null || brief.budget_scope === "event") summary += " Бюджет на одного подрядчика не проверен.";
  return { outcome: pool.length === 0 ? "category_absent" : eligible.length === 0 ? "no_eligible" : "matched",
    recommendations, summary, preliminary, unchecked };
}
