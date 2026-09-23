export interface Contractor {
  id: string;
  anon_name: string;
  city: string;
  description: string;
  categories: string[];
  event_formats: string[];
  languages: string[];
  busy_dates: string[];
  price_from_kzt: number;
  max_hours: number | null;
  synthetic: boolean;
  city_imputed: boolean;
  price_imputed: boolean;
}

export interface Preference {
  text: string;
  feature_id: string | null;
  importance: "required" | "preferred";
  polarity: "positive" | "negative";
}

export interface Brief {
  city: string | null;
  category: string | null;
  event_format: string | null;
  date: string | null;
  budget_kzt: number | null;
  hours: number | null;
  language: string | null;
  preferences: Preference[];
  skipped_fields: string[];
  excluded_ids: string[];
  budget_scope: "contractor" | "event";
}

export type Field = "city" | "category" | "event_format" | "date" | "budget_kzt" | "hours" | "language";
export interface Action {
  id: string;
  label: string;
  type: string;
  field?: string;
  value?: unknown;
}
export interface HistoryEntry { role: "user" | "assistant"; text: string }
export interface AssistantInput { brief: Brief; message?: string; action?: Action; history?: HistoryEntry[] }
export interface Evidence {
  feature_id: string;
  quote: string;
  status: "supported" | "contradicted" | "unknown";
}
export interface Recommendation {
  contractor: Contractor;
  explanation: string;
  unchecked: string[];
  evidence: Evidence[];
}
export interface Result {
  outcome: "matched" | "category_absent" | "no_eligible";
  recommendations: Recommendation[];
  summary: string;
  preliminary: boolean;
  unchecked: string[];
}
export interface AssistantTurn {
  brief: Brief;
  message: string;
  actions: Action[];
  question_field: string | null;
  result: Result | null;
  mode: "ai" | "basic";
  warnings: string[];
  dataset_version: string;
  algorithm_version: string;
}
export interface FeatureDefinition { key: string; label: string; description: string }
export interface ProfileFeature { key: string; polarity: "supports" | "contradicts"; quote: string }
export interface Catalog {
  contractors: Contractor[];
  datasetVersion: string;
  featureVersion: string;
  featureDefinitions: FeatureDefinition[];
  features: ReadonlyMap<string, ProfileFeature[]>;
}
export const ALGORITHM_VERSION = "assistant-v1.0.0";
export const CALENDAR_START = "2026-09-23";
export const CALENDAR_END = "2026-12-31";
export const emptyBrief = (): Brief => ({
  city: null, category: null, event_format: null, date: null, budget_kzt: null,
  hours: null, language: null, preferences: [], skipped_fields: [], excluded_ids: [],
  budget_scope: "contractor",
});
