import { CALENDAR_END, CALENDAR_START } from "./types.mjs";
import { AssistantError, validateBrief } from "./validation.mjs";
export const dateIsCovered = (date)=>date !== null && date >= CALENDAR_START && date <= CALENDAR_END;
export const hasSearchMinimum = (brief)=>Boolean(brief.city && brief.category && brief.event_format);
export function preferenceEvidence(catalog, contractor, preference) {
    const features = catalog.features.get(contractor.id) ?? [];
    const matches = preference.feature_id ? features.filter((item)=>item.key === preference.feature_id) : [];
    const isContradiction = (polarity)=>preference.polarity === "positive" ? polarity === "contradicts" : polarity === "supports";
    const feature = matches.find((item)=>isContradiction(item.polarity)) ?? matches[0];
    return {
        feature_id: preference.feature_id ?? `unmapped:${preference.text}`,
        quote: feature?.quote ?? "",
        status: !feature ? "unknown" : isContradiction(feature.polarity) ? "contradicted" : "supported"
    };
}
export function uncheckedFields(brief) {
    const result = [];
    if (!brief.city) result.push("Город не задан");
    if (!brief.category) result.push("Категория не задана");
    if (!brief.event_format) result.push("Формат мероприятия не задан");
    if (!brief.date) result.push("Дата не проверена");
    else if (!dateIsCovered(brief.date)) result.push("Дата за пределами календаря 23.09–31.12.2026");
    if (brief.budget_kzt === null) result.push("Бюджет подрядчика не задан");
    else if (brief.budget_scope === "event") result.push("Указан общий бюджет; бюджет подрядчика не задан");
    return result;
}
const rejectionLabels = {
    busy: "заняты на дату",
    budget: "выше бюджета",
    format: "не берут этот формат",
    language: "не работают на выбранном языке",
    hours: "не подходят по длительности",
    preference: "противоречат обязательному пожеланию",
    excluded: "уже отклонены вами"
};
export function evaluate(catalog, rawBrief, semanticScores) {
    const brief = validateBrief(rawBrief);
    const unchecked = uncheckedFields(brief);
    const pool = catalog.contractors.filter((item)=>(!brief.city || item.city === brief.city) && (!brief.category || item.categories.includes(brief.category)));
    const eligible = [];
    const rejected = {};
    for (const contractor of pool){
        const evidence = brief.preferences.map((preference)=>preferenceEvidence(catalog, contractor, preference));
        const reason = brief.excluded_ids.includes(contractor.id) ? "excluded" : dateIsCovered(brief.date) && contractor.busy_dates.includes(brief.date) ? "busy" : brief.budget_scope === "contractor" && brief.budget_kzt !== null && contractor.price_from_kzt > brief.budget_kzt ? "budget" : brief.event_format && !contractor.event_formats.includes(brief.event_format) ? "format" : brief.language && !contractor.languages.includes(brief.language) ? "language" : brief.hours !== null && contractor.max_hours !== null && contractor.max_hours < brief.hours ? "hours" : evidence.some((item, index)=>item.status === "contradicted" && brief.preferences[index].importance === "required") ? "preference" : null;
        if (reason) {
            rejected[reason] = (rejected[reason] ?? 0) + 1;
            continue;
        }
        const profileUnchecked = [
            ...unchecked
        ];
        if (brief.hours !== null && contractor.max_hours === null) profileUnchecked.push("Длительность не подтверждена");
        brief.preferences.forEach((preference, index)=>{
            if (evidence[index].status === "unknown") profileUnchecked.push(`Не подтверждено: ${preference.text}`);
        });
        let score = 0;
        evidence.forEach((item, index)=>{
            const weight = brief.preferences[index].importance === "required" ? 100 : 20;
            score += item.status === "supported" ? weight : item.status === "contradicted" ? -weight : 0;
        });
        const similarity = semanticScores?.get(contractor.id) ?? 0;
        if (!Number.isFinite(similarity) || similarity < -1 || similarity > 1) {
            throw new AssistantError("unavailable", "Не удалось проверить смысловой рейтинг. Повторите запрос.", {
                code: "invalid-semantic-score"
            });
        }
        eligible.push({
            contractor,
            evidence,
            score,
            unchecked: profileUnchecked,
            contradictionCount: evidence.filter((item)=>item.status === "contradicted").length,
            supportedCount: evidence.filter((item)=>item.status === "supported").length,
            semanticScore: Math.round(similarity * 1_000_000) / 1_000_000
        });
    }
    eligible.sort((a, b)=>a.contradictionCount - b.contradictionCount || b.supportedCount - a.supportedCount || b.semanticScore - a.semanticScore || a.contractor.price_from_kzt - b.contractor.price_from_kzt || a.contractor.id.localeCompare(b.contractor.id, "en"));
    return {
        pool,
        eligible,
        rejected,
        unchecked
    };
}
function excerpt(text) {
    const trimmed = text.trim();
    if (trimmed.length <= 200) return trimmed;
    const boundary = trimmed.lastIndexOf(" ", 200);
    return trimmed.slice(0, boundary > 80 ? boundary : 200);
}
function explain(catalog, item, brief) {
    const { contractor, evidence } = item;
    const relevantIndex = evidence.findIndex((entry)=>entry.status === "contradicted");
    const supportedIndex = evidence.findIndex((entry)=>entry.status === "supported");
    const chosenIndex = relevantIndex >= 0 ? relevantIndex : supportedIndex;
    const sourceFeature = (catalog.features.get(contractor.id) ?? []).find((entry)=>entry.polarity === "supports");
    let explanation = chosenIndex >= 0 ? `${evidence[chosenIndex].status === "supported" ? "Есть подтверждение пожелания" : "Есть противоречие пожеланию"} «${brief.preferences[chosenIndex].text}»: «${excerpt(evidence[chosenIndex].quote)}».` : `Из профиля: «${excerpt(sourceFeature?.quote ?? contractor.description)}».`;
    const unknownRequired = brief.preferences.filter((preference, i)=>preference.importance === "required" && evidence[i].status === "unknown");
    if (unknownRequired.length) explanation += ` Обязательное условие нужно подтвердить: ${unknownRequired.map((item)=>item.text).join(", ")}.`;
    return explanation;
}
export function recommend(catalog, rawBrief, semanticScores) {
    const brief = validateBrief(rawBrief);
    if (!hasSearchMinimum(brief)) {
        throw new AssistantError("invalid-argument", "Для подбора нужны город, категория и формат мероприятия.", {
            code: "missing-search-minimum"
        });
    }
    const { pool, eligible, rejected, unchecked } = evaluate(catalog, brief, semanticScores);
    const recommendations = eligible.slice(0, 3).map((item)=>({
            contractor: item.contractor,
            explanation: explain(catalog, item, brief),
            unchecked: item.unchecked,
            evidence: item.evidence
        }));
    const preliminary = unchecked.length > 0 || recommendations.some((item)=>item.unchecked.length > 0);
    const rejectedText = Object.entries(rejected).map(([reason, count])=>`${count} — ${rejectionLabels[reason]}`).join("; ");
    let summary = pool.length === 0 ? "В этом городе такой категории пока нет в каталоге." : eligible.length === 0 ? `Никто не проходит по заданным условиям. ${rejectedText}.` : `${preliminary ? "Предварительно подходят" : "Проходят по указанным условиям"} ${eligible.length} из ${pool.length}; показано ${recommendations.length}.`;
    if (eligible.length && rejectedText) summary += ` Исключены: ${rejectedText}.`;
    if (!dateIsCovered(brief.date)) summary += " Доступность на дату не проверена.";
    if (brief.budget_kzt === null || brief.budget_scope === "event") summary += " Бюджет на одного подрядчика не проверен.";
    return {
        outcome: pool.length === 0 ? "category_absent" : eligible.length === 0 ? "no_eligible" : "matched",
        recommendations,
        summary,
        preliminary,
        unchecked
    };
}
