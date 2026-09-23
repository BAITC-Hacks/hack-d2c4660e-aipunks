import { createHash } from "node:crypto";
import { type Action, type Brief, type Field, emptyBrief } from "./types";
import { AssistantError, parsePreference, validateBrief } from "./validation";

const fields: Field[] = ["city", "category", "event_format", "date", "budget_kzt", "hours", "language"];
export function stableJson(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  return `{${Object.entries(value as Record<string, unknown>).filter(([, value]) => value !== undefined)
    .sort(([a], [b]) => a.localeCompare(b, "en")).map(([key, value]) => `${JSON.stringify(key)}:${stableJson(value)}`).join(",")}}`;
}
export const digest = (value: unknown): string => createHash("sha256").update(stableJson(value)).digest("hex");
export function actionFor(brief: Brief, label: string, type: string, field?: string, value?: unknown): Action {
  const payload = { label, type, ...(field === undefined ? {} : { field }), ...(value === undefined ? {} : { value }) };
  return { id: `a:${digest(brief).slice(0, 16)}:${digest(payload).slice(0, 16)}`, ...payload };
}

export function applyAction(current: Brief, action: Action): Brief {
  if (action.id.startsWith("a:") && action.id.split(":")[1] !== digest(current).slice(0, 16)) {
    throw new AssistantError("failed-precondition", "Условия уже изменились. Используйте кнопки последнего ответа.", { code: "stale-action" });
  }
  const brief: Brief = structuredClone(current);
  const invalid = () => { throw new AssistantError("invalid-argument", "Некорректное действие помощника."); };
  switch (action.type) {
    case "reset": return emptyBrief();
    case "show_results": return brief;
    case "set_field":
    case "clear_field": {
      if (!fields.includes(action.field as Field)) return invalid();
      const key = action.field as Field;
      (brief as unknown as Record<string, unknown>)[key] = action.type === "clear_field" ? null : action.value;
      if (key === "budget_kzt" && action.type === "set_field") brief.budget_scope = "contractor";
      brief.skipped_fields = brief.skipped_fields.filter((item) => item !== key);
      // Changing the category via its field is still a correction, not a new search.
      return validateBrief(brief);
    }
    case "skip_field":
      if (action.field !== "date" && action.field !== "budget_kzt") return invalid();
      brief.skipped_fields = [...new Set([...brief.skipped_fields, action.field])];
      brief[action.field] = null;
      return brief;
    case "next_category":
      if (action.value !== null && action.value !== undefined && typeof action.value !== "string") return invalid();
      return validateBrief({ ...emptyBrief(), city: brief.city, date: brief.date, event_format: brief.event_format, category: action.value ?? null });
    case "add_preference":
      brief.preferences.push(parsePreference(action.value));
      return validateBrief(brief);
    case "remove_preference":
      if (!Number.isInteger(action.value) || Number(action.value) < 0 || Number(action.value) >= brief.preferences.length) return invalid();
      brief.preferences.splice(Number(action.value), 1);
      return brief;
    case "reject": {
      const value = action.value as { contractor_id?: unknown; reason?: unknown; detail?: unknown } | null;
      if (!value || typeof value.contractor_id !== "string" || !["price", "style", "experience", "other"].includes(String(value.reason))) return invalid();
      if (value.detail !== undefined && (typeof value.detail !== "string" || value.detail.length > 1000)) return invalid();
      brief.excluded_ids = [...new Set([...brief.excluded_ids, value.contractor_id])];
      return validateBrief(brief);
    }
    default: return invalid();
  }
}
