import { z } from "zod";
export class AssistantError extends Error {
    code;
    details;
    constructor(code, message, details = {}){
        super(message), this.code = code, this.details = details;
        this.name = "AssistantError";
    }
}
const nullableText = z.string().trim().min(1).max(120).nullable();
const calendarDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine((value)=>{
    const parsed = new Date(`${value}T00:00:00.000Z`);
    return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}, "Некорректная календарная дата");
export const preferenceSchema = z.object({
    text: z.string().trim().min(1).max(1000),
    feature_id: z.string().min(1).max(80).nullable(),
    importance: z.enum([
        "required",
        "preferred"
    ]),
    polarity: z.enum([
        "positive",
        "negative"
    ])
}).strict();
export const briefSchema = z.object({
    city: nullableText,
    category: nullableText,
    event_format: nullableText,
    date: calendarDate.nullable(),
    budget_kzt: z.number().int().positive().max(1_000_000_000_000).nullable(),
    hours: z.number().positive().max(168).nullable(),
    language: nullableText,
    preferences: z.array(preferenceSchema).max(12).default([]),
    skipped_fields: z.array(z.enum([
        "date",
        "budget_kzt"
    ])).max(2).default([]),
    excluded_ids: z.array(z.string().min(1).max(100)).max(100).default([]),
    budget_scope: z.enum([
        "contractor",
        "event"
    ]).default("contractor")
}).strict();
const actionSchema = z.object({
    id: z.string().min(1).max(240),
    label: z.string().min(1).max(180),
    type: z.enum([
        "set_field",
        "clear_field",
        "skip_field",
        "show_results",
        "next_category",
        "reject",
        "add_preference",
        "remove_preference",
        "reset"
    ]),
    field: z.string().max(80).optional(),
    value: z.unknown().optional()
}).strict();
const inputSchema = z.object({
    brief: briefSchema,
    message: z.string().trim().min(1).max(2000).optional(),
    action: actionSchema.optional(),
    history: z.array(z.object({
        role: z.enum([
            "user",
            "assistant"
        ]),
        text: z.string().max(2000)
    }).strict()).max(12).optional()
}).strict().refine((input)=>Boolean(input.message) !== Boolean(input.action), "Передайте только сообщение или действие");
function parse(schema, value) {
    const result = schema.safeParse(value);
    if (!result.success) {
        throw new AssistantError("invalid-argument", "Проверьте заполненные условия.", {
            issues: result.error.issues.map((item)=>({
                    field: item.path.join("."),
                    message: item.message
                }))
        });
    }
    return result.data;
}
export function validateBrief(value) {
    return parse(briefSchema, value);
}
export function validateInput(value) {
    if (Buffer.byteLength(JSON.stringify(value ?? null), "utf8") > 64_000) {
        throw new AssistantError("invalid-argument", "Запрос слишком большой.");
    }
    return parse(inputSchema, value);
}
export function validateAction(value) {
    return parse(actionSchema, value);
}
export const parsePreference = (value)=>parse(preferenceSchema, value);
export function legacyBrief(value) {
    const legacy = parse(z.object({
        city: z.string(),
        category: z.string(),
        event_format: z.string(),
        date: calendarDate,
        budget_kzt: z.number(),
        hours: z.number().nullable().optional(),
        language: z.string().nullable().optional(),
        preferences: z.string().max(1000).optional()
    }).strict(), value);
    return validateBrief({
        ...legacy,
        hours: legacy.hours ?? null,
        language: legacy.language ?? null,
        preferences: legacy.preferences?.trim() ? [
            {
                text: legacy.preferences.trim(),
                feature_id: null,
                importance: "preferred",
                polarity: "positive"
            }
        ] : [],
        skipped_fields: [],
        excluded_ids: [],
        budget_scope: "contractor"
    });
}
