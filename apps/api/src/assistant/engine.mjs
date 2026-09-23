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
        // In the supplied dataset null means a service without a required
        // on-site duration (for example gifts/decor), not missing evidence.
        // A live profile has no such dataset guarantee.
        if (brief.hours !== null && contractor.max_hours === null && (contractor.is_live === true || catalog.source === "live")) profileUnchecked.push("Длительность не подтверждена");
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
const money = (value)=>new Intl.NumberFormat("ru-RU").format(value);
const displayDate = (date)=>date.split("-").reverse().join(".");
const sentenceSegments = new Intl.Segmenter("ru", { granularity: "sentence" });

/** Expand an exact evidence substring to its complete source sentence(s).
 * Never crop by character count: a trailing negation or condition matters. */
function fullEvidenceQuote(description, quote) {
    const start = description.indexOf(quote);
    if (start < 0 || !quote) return null;
    const end = start + quote.length;
    return [...sentenceSegments.segment(description)]
        .filter((part)=>part.index < end && part.index + part.segment.length > start)
        .map((part)=>part.segment).join("").trim();
}
function compactQuote(quote) {
    return quote.length <= 180 && [...sentenceSegments.segment(quote)].length === 1;
}
function shortLabel(text) {
    // Keep user wording intact when it fits; never cut away a qualification or
    // negation merely to fit the card. The full wish remains in the brief.
    return text.length <= 100 && !/[.!?…\r\n]/u.test(text);
}
function quotedSentence(prefix, quote) {
    // The original punctuation stays inside the quote. A sentence without a
    // terminal mark receives it outside; no source words are removed.
    return `${prefix}: «${quote}»${/[.!?…][»”"')\]]?$/u.test(quote) ? "" : "."}`;
}
function explain(catalog, item, brief) {
    const { contractor, evidence } = item;
    const startingPrice = `${contractor.price_imputed ? "Оценочная начальная цена" : "Начальная цена"} — от ${money(contractor.price_from_kzt)} ₸ за мероприятие`;
    const limit = brief.budget_scope === "contractor" && brief.budget_kzt !== null
        ? ` при вашем лимите ${money(brief.budget_kzt)} ₸` : "";
    const priceSentence = `${startingPrice}${limit}; итоговую стоимость нужно согласовать.`;
    // A preferred contradiction must remain visible even when another wish is
    // supported. Unknown wishes are reported separately in unchecked.
    const chosenIndex = evidence.findIndex((entry)=>entry.status === "contradicted");
    const requiredSupport = evidence.findIndex((entry, index)=>entry.status === "supported" && brief.preferences[index].importance === "required");
    const supportedIndex = requiredSupport >= 0 ? requiredSupport : evidence.findIndex((entry)=>entry.status === "supported");
    const semanticIndex = chosenIndex >= 0 ? chosenIndex : supportedIndex;
    if (semanticIndex >= 0) {
        const quote = fullEvidenceQuote(contractor.description, evidence[semanticIndex].quote);
        if (quote) {
            const text = brief.preferences[semanticIndex].text;
            const wish = shortLabel(text) ? `пожеланию «${text}»` : `пожеланию №${semanticIndex + 1}`;
            const confirmedWish = shortLabel(text) ? `Пожелание «${text}»` : `Пожелание №${semanticIndex + 1}`;
            const prefix = evidence[semanticIndex].status === "contradicted"
                ? `Описание противоречит ${wish}`
                : `${confirmedWish} подтверждено описанием`;
            // Full source context stays in evidence, including long sentences
            // and evidence spanning several sentences. Only a complete short
            // sentence belongs in the two-sentence card explanation.
            return `${priceSentence} ${compactQuote(quote) ? quotedSentence(prefix, quote) : `${prefix}.`}`;
        }
    }
    const facts = [shortLabel(brief.event_format) ? `формат «${brief.event_format}»` : "запрошенный формат"];
    if (brief.language !== null) facts.push(shortLabel(brief.language) ? `запрошенный язык «${brief.language}»` : "запрошенный язык");
    if (brief.hours !== null && contractor.max_hours !== null) facts.push(`предел ${contractor.max_hours} ч при запросе на ${brief.hours} ч`);
    let fitSentence = `В анкете ${facts.length > 1 ? "указаны" : "указан"} ${facts.join(", ")}`;
    if (brief.hours !== null && contractor.max_hours === null && contractor.is_live !== true && catalog.source !== "live") {
        fitSentence += `; услуга не привязана к длительности присутствия (запрошено ${brief.hours} ч)`;
    }
    return `${priceSentence} ${fitSentence}.`;
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
            evidence: item.evidence.map((entry)=>({
                ...entry,
                quote: fullEvidenceQuote(item.contractor.description, entry.quote) ?? entry.quote
            }))
        }));
    const preliminary = unchecked.length > 0 || recommendations.some((item)=>item.unchecked.length > 0);
    const rejectedText = Object.entries(rejected).map(([reason, count])=>`${count} — ${rejectionLabels[reason]}`).join("; ");
    let summary = pool.length === 0 ? "В этом городе такой категории пока нет в каталоге." : eligible.length === 0 ? `Никто не проходит по заданным условиям. ${rejectedText}.` : `Найдено ${eligible.length} из ${pool.length}; показано ${recommendations.length}${preliminary ? " — предварительно" : ""}.`;
    if (eligible.length > 0 && eligible.length < 3) {
        summary += rejectedText ? ` Меньше трёх вариантов: остальные исключены (${rejectedText}).`
            : " Меньше трёх вариантов: других анкет этой категории в городе нет.";
    } else if (eligible.length && rejectedText) summary += ` Исключены: ${rejectedText}.`;
    if (brief.date === null) summary += " Дата не задана; занятость не проверена.";
    else if (!dateIsCovered(brief.date)) summary += ` Занятость на ${displayDate(brief.date)} не проверена: дата вне календаря 23.09–31.12.2026.`;
    else if (pool.length === 0) summary += ` Дата запроса — ${displayDate(brief.date)}.`;
    else summary += ` Проверена занятость на ${displayDate(brief.date)}${recommendations.length ? "; у показанных вариантов дата не отмечена занятой" : ""}.`;
    if (brief.budget_kzt === null || brief.budget_scope === "event") summary += " Бюджет на одного подрядчика не проверен.";
    return {
        outcome: pool.length === 0 ? "category_absent" : eligible.length === 0 ? "no_eligible" : "matched",
        recommendations,
        summary,
        preliminary,
        unchecked
    };
}
