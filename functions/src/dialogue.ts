import { actionFor } from "./actions";
import { evaluate, hasSearchMinimum, recommend } from "./engine";
import { ALGORITHM_VERSION, type Action, type AssistantTurn, type Brief, type Catalog, type Field, type Result } from "./types";

export interface DialogueOptions { mode: "ai" | "basic"; forceResults?: boolean; action?: Action; warnings?: string[]; semanticScores?: ReadonlyMap<string, number> }

function choices(catalog: Catalog, brief: Brief, field: Field): string[] {
  const pool = catalog.contractors.filter((item) => (!brief.city || item.city === brief.city) &&
    (!brief.category || item.categories.includes(brief.category)));
  const source = field === "category" ? (pool.length ? pool : catalog.contractors).flatMap((item) => item.categories)
    : field === "city" ? (pool.length ? pool : catalog.contractors).map((item) => item.city)
    : field === "event_format" ? pool.flatMap((item) => item.event_formats)
    : field === "language" ? pool.flatMap((item) => item.languages) : [];
  return [...new Set(source)].sort((a, b) => a.localeCompare(b, "ru"));
}

function fieldQuestion(catalog: Catalog, brief: Brief, field: Field): { message: string; actions: Action[] } {
  const prompts: Record<Field, string> = {
    category: "Какого подрядчика ищете?", city: "В каком городе пройдёт мероприятие?",
    event_format: "Для какого мероприятия подбираем подрядчика?", date: "На какую дату проверить занятость?",
    budget_kzt: brief.budget_scope === "event" ? "Какую часть общего бюджета выделим на одного подрядчика?" : "Какой бюджет на одного подрядчика?",
    hours: "На сколько часов нужен подрядчик?", language: "На каком языке должно пройти мероприятие?",
  };
  const actions = choices(catalog, brief, field).slice(0, 4).map((value) => actionFor(brief, value, "set_field", field, value));
  if (field === "date") actions.push(actionFor(brief, "Выбрать дату", "pick_date", "date"));
  if (field === "budget_kzt") {
    const prices = [...new Set(evaluate(catalog, { ...brief, budget_kzt: null, budget_scope: "contractor" }).eligible
      .map((item) => item.contractor.price_from_kzt))].sort((a, b) => a - b);
    const thresholds = prices.length ? [...new Set([prices[0], prices[Math.floor(prices.length / 2)]])] : [];
    actions.push(...thresholds.map((value) => actionFor(brief, `До ${new Intl.NumberFormat("ru-RU").format(value)} ₸`, "set_field", "budget_kzt", value)));
    actions.push(actionFor(brief, "Своя сумма", "pick_budget", "budget_kzt"));
  }
  if (field !== "date" && field !== "budget_kzt") actions.push(actionFor(brief, "Другой вариант", "pick_field", field));
  if (field === "date" || field === "budget_kzt") actions.push(actionFor(brief, "Пока не знаю", "skip_field", field));
  if (hasSearchMinimum(brief)) actions.push(actionFor(brief, "Показать варианты", "show_results"));
  return { message: prompts[field], actions };
}

/** Optional refinement uses actual variation, but never blocks a complete brief with another question. */
function informativeFeature(catalog: Catalog, brief: Brief): string | undefined {
  const pool = evaluate(catalog, brief).eligible;
  if (pool.length < 2 || brief.preferences.length > 0) return undefined;
  return catalog.featureDefinitions.map((definition) => {
    const support = pool.filter((item) => (catalog.features.get(item.contractor.id) ?? [])
      .some((feature) => feature.key === definition.key && feature.polarity === "supports")).length;
    return { key: definition.key, split: support && support < pool.length ? Math.min(support, pool.length - support) : 0 };
  }).sort((a, b) => b.split - a.split || a.key.localeCompare(b.key, "en")).find((item) => item.split > 0)?.key;
}

function refinementActions(brief: Brief): Action[] {
  return [actionFor(brief, "Изменить бюджет", "pick_budget", "budget_kzt"), actionFor(brief, "Изменить дату", "pick_date", "date"),
    actionFor(brief, "Найти другого специалиста", "next_category", undefined, null)];
}

export function buildTurn(catalog: Catalog, brief: Brief, options: DialogueOptions): AssistantTurn {
  let result: Result | null = hasSearchMinimum(brief)
    ? recommend(catalog, brief, options.semanticScores) : null;
  let questionField: string | null = null;
  let actions: Action[] = [];
  let message: string;
  const missingCore = (["category", "city", "event_format"] as Field[]).find((field) => brief[field] === null);
  const missing = (["date", "budget_kzt"] as Field[]).find((field) =>
    (brief[field] === null || (field === "budget_kzt" && brief.budget_scope === "event")) && !brief.skipped_fields.includes(field));
  if (missingCore) {
    questionField = missingCore;
    ({ message, actions } = fieldQuestion(catalog, brief, missingCore));
  } else if (!options.forceResults && missing && result?.outcome !== "no_eligible" && result?.outcome !== "category_absent") {
    questionField = missing;
    ({ message, actions } = fieldQuestion(catalog, brief, missing));
    if (result) message = `${result.summary}\n\n${message}`;
  } else {
    result ??= recommend(catalog, brief, options.semanticScores);
    message = result.summary;
    actions = refinementActions(brief);
    if (result.outcome === "category_absent") {
      actions = [actionFor(brief, "Изменить город", "pick_field", "city"), actionFor(brief, "Изменить категорию", "pick_field", "category")];
    } else if (result.outcome === "no_eligible") {
      if (brief.language) actions.push(actionFor(brief, "Изменить язык", "pick_field", "language"));
      if (brief.hours !== null) actions.push(actionFor(brief, "Изменить длительность", "pick_field", "hours"));
      if (brief.preferences.length) actions.push(actionFor(brief, "Изменить пожелания", "pick_field", "preferences"));
      if (!brief.language && brief.hours === null && !brief.preferences.length) {
        actions.push(actionFor(brief, "Изменить формат", "pick_field", "event_format"));
      }
    } else if (!options.forceResults) {
      const featureId = informativeFeature(catalog, brief);
      const definition = catalog.featureDefinitions.find((item) => item.key === featureId);
      if (definition) {
        actions.push(actionFor(brief, `Предпочитаю: ${definition.label}`, "add_preference", undefined, {
          text: definition.label, feature_id: definition.key, importance: "preferred", polarity: "positive",
        }));
      }
    }
  }
  if (options.action?.type === "reject" && result) {
    const value = options.action.value as { reason: string };
    const followup = value.reason === "price" ? "Оставил прежний бюджет. Можно указать новую сумму кнопкой ниже."
      : value.reason === "style" ? "Какой стиль вам ближе? Можно описать пожелание или выбрать условие вручную."
      : value.reason === "experience" ? "Какой опыт для вас важен? Можно описать пожелание или выбрать условие вручную."
      : "Исключил этот вариант. Уточните условия, если хотите изменить следующую подборку.";
    message = `${followup}\n\n${result?.summary ?? message}`;
    actions = [...refinementActions(brief), actionFor(brief, "Уточнить пожелания", "pick_field", "preferences")];
    questionField = value.reason === "price" ? "budget_kzt" : value.reason === "style" || value.reason === "experience" ? "preferences" : null;
  }
  return { brief, message, actions, question_field: questionField, result, mode: options.mode,
    warnings: options.warnings ?? [], dataset_version: catalog.datasetVersion, algorithm_version: ALGORITHM_VERSION };
}
