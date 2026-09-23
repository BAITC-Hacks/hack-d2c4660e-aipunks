#!/usr/bin/env node
/** Optional live evaluation. Never runs during unit tests or build.
 * From the repository root:
 *   npm --prefix functions run build
 *   OPENAI_API_KEY=<provided securely in your environment> node scripts/evaluate_assistant_ai.mjs
 * OPENAI_MODEL optionally selects the deployed model configuration.
 * Eight cases make nine real extraction calls, plus query embeddings when the
 * actual precomputed embedding artifact exists. Provider usage may incur cost.
 * Output is JSON; exit 0 means all behavior checks passed, 1 a failed case,
 * and 2 missing configuration/build. Latency is measured, never asserted in advance.
 */
import { createRequire } from 'node:module';
import { performance } from 'node:perf_hooks';
import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
const latencyTargetMs = 10_000;
const safeErrorCodes = new Set(['invalid-argument', 'failed-precondition', 'unauthenticated', 'resource-exhausted', 'unavailable']);

function configurationFailure(message) {
  console.error(message);
  process.exitCode = 2;
}

async function main() {
  // This check precedes module loading and every possible provider call.
  const key = process.env.OPENAI_API_KEY?.trim();
  if (!key) {
    configurationFailure('OPENAI_API_KEY не задан. Live-проверка не запускалась; обращений к провайдеру не было.');
    return;
  }
  if (/[^\x21-\x7e]/.test(key)) {
    configurationFailure('OPENAI_API_KEY имеет неверный формат. Live-проверка не запускалась.');
    return;
  }
  if (!existsSync(resolve(root, 'functions/lib/service.js'))) {
    configurationFailure('Сначала соберите сервер: npm --prefix functions run build. Live-проверка не запускалась.');
    return;
  }

  let catalog;
  let createLanguageModel;
  let AssistantApplication;
  let MemoryAssistantCache;
  let emptyBrief;
  let algorithmVersion;
  try {
    ({ createLanguageModel } = require('../functions/lib/openai.js'));
    ({ AssistantApplication } = require('../functions/lib/service.js'));
    ({ MemoryAssistantCache } = require('../functions/lib/storage.js'));
    ({ emptyBrief, ALGORITHM_VERSION: algorithmVersion } = require('../functions/lib/types.js'));
    catalog = require('../functions/lib/catalog.js').loadCatalog();
  } catch {
    configurationFailure('Не удалось загрузить собранный сервер или проверенный каталог. Пересоберите functions и проверьте data.');
    return;
  }
  for (const feature of ['calm_delivery', 'no_contests', 'no_generic_contests']) {
    if (!catalog.featureDefinitions.some(item => item.key === feature)) {
      configurationFailure('Онтология каталога изменилась. Обновите ожидаемые признаки live-проверки перед запуском.');
      return;
    }
  }

  const provider = createLanguageModel(key);
  const calls = { responses: 0, embeddings: 0 };
  const model = {
    available: provider.available,
    version: provider.version,
    extract(...args) { calls.responses++; return provider.extract(...args); },
    embed(...args) { calls.embeddings++; return provider.embed(...args); },
  };
  const full = (patch = {}) => ({ ...emptyBrief(), city: 'Алматы', category: 'Ведущий',
    event_format: 'корпоратив', date: '2026-10-15', budget_kzt: 1_500_000, hours: 4, language: 'русский', ...patch });
  const calm = { text: 'Спокойная подача', feature_id: 'calm_delivery', importance: 'preferred', polarity: 'positive' };
  const hasFeature = (brief, key) => brief.preferences.some(preference => preference.feature_id === key && preference.polarity === 'positive');
  const hasCards = turn => Boolean(turn.result?.recommendations.length);
  const keepsFields = (actual, expected, fields) => fields.every(field => actual[field] === expected[field]);
  const check = (name, passed) => ({ name, passed: Boolean(passed) });

  const cases = [
    {
      id: 'full_phrase', title: 'Полный запрос сразу даёт подборку',
      async run(turn) {
        const result = await turn({ brief: emptyBrief(), message: 'Нужен ведущий на корпоратив в Алматы 15 октября 2026 года. Работа на русском языке, 4 часа. Бюджет именно на ведущего — до 1 500 000 тенге.' });
        return [check('Все явно заданные параметры извлечены', keepsFields(result.brief, full(), ['city', 'category', 'event_format', 'date', 'budget_kzt', 'hours', 'language'])),
          check('Нет обязательного дополнительного вопроса', result.question_field === null), check('Есть рекомендации', hasCards(result))];
      },
    },
    {
      id: 'partial_phrase', title: 'Минимальный запрос даёт предварительные варианты и один вопрос о дате',
      async run(turn) {
        const result = await turn({ brief: emptyBrief(), message: 'Нужен ведущий на корпоратив в Алматы.' });
        return [check('Нет выдуманной даты или суммы', result.brief.date === null && result.brief.budget_kzt === null),
          check('Следующий вопрос — дата', result.question_field === 'date'),
          check('Есть предварительные карточки', hasCards(result) && result.result.preliminary)];
      },
    },
    {
      id: 'correction', title: 'Исправление суммы сохраняет остальные условия',
      async run(turn) {
        const before = full({ preferences: [calm] });
        const result = await turn({ brief: before, message: 'Нет, бюджет на ведущего теперь 500 тысяч тенге. Остальные условия оставляем.' });
        return [check('Новая сумма — 500000', result.brief.budget_kzt === 500_000 && result.brief.budget_scope === 'contractor'),
          check('Остальные поля сохранены', keepsFields(result.brief, before, ['city', 'category', 'event_format', 'date', 'hours', 'language'])),
          check('Пожелание сохранено', hasFeature(result.brief, 'calm_delivery'))];
      },
    },
    {
      id: 'negative_scope', title: 'Полный запрет конкурсов отличается от запрета банальных конкурсов',
      async run(turn) {
        const strict = await turn({ brief: full(), message: 'Обязательно совсем без каких-либо конкурсов. Не только без банальных: вообще никаких конкурсов.' });
        const generic = await turn({ brief: full(), message: 'Не хочу именно банальных конкурсов. Оригинальные конкурсы можно, полного запрета конкурсов нет.' });
        const strictPreference = strict.brief.preferences.find(item => item.feature_id === 'no_contests');
        return [check('Полный запрет распознан как обязательный no_contests', strictPreference?.importance === 'required' && strictPreference.polarity === 'positive'),
          check('Полный запрет не заменён более слабым условием', !hasFeature(strict.brief, 'no_generic_contests')),
          check('Без доказательств запрет не обещан', hasCards(strict) && strict.result.preliminary && strict.result.recommendations.every(item =>
            item.evidence.some(evidence => evidence.feature_id === 'no_contests' && evidence.status === 'unknown'))),
          check('Банальные конкурсы выделены отдельно', hasFeature(generic.brief, 'no_generic_contests') && !hasFeature(generic.brief, 'no_contests'))];
      },
    },
    {
      id: 'event_budget', title: 'Общий бюджет не становится лимитом подрядчика',
      async run(turn) {
        const result = await turn({ brief: emptyBrief(), message: 'Ищу ведущего на корпоратив в Алматы 15 октября 2026 года. 100 000 тенге — общий бюджет всего мероприятия, сумму на ведущего ещё не выделял.' });
        return [check('Общий бюджет сохранён', result.brief.budget_scope === 'event' && result.brief.budget_kzt === 100_000),
          check('Уточняется бюджет подрядчика', result.question_field === 'budget_kzt'),
          check('Общая сумма не отсекает кандидатов', hasCards(result) && result.result.recommendations.some(item => item.contractor.price_from_kzt > 100_000)),
          check('Результат предварительный', result.result?.preliminary)];
      },
    },
    {
      id: 'multiple_categories', title: 'Несколько категорий вызывают одно уточнение',
      async run(turn) {
        const result = await turn({ brief: emptyBrief(), message: 'Нужны ведущий и фотограф на корпоратив в Алматы 15 октября 2026. На каждого подрядчика бюджет до 1 500 000 тенге. Кого искать первым, ещё не решил.' });
        return [check('Уточняется категория', result.question_field === 'category'),
          check('Случайной подборки нет', result.result === null),
          check('Известные условия сохранены', keepsFields(result.brief, full(), ['city', 'event_format', 'date'])),
          check('Есть кнопки обеих категорий', ['Ведущий', 'Фотограф'].every(category => result.actions.some(action => action.type === 'set_field' && action.field === 'category' && action.value === category)))];
      },
    },
    {
      id: 'outside_calendar', title: 'Дата вне календаря сохраняется без обещания доступности',
      async run(turn) {
        const result = await turn({ brief: emptyBrief(), message: 'Нужен ведущий на корпоратив в Алматы 15 января 2027 года. Бюджет на ведущего до 1 500 000 тенге.' });
        return [check('Дата не подменена', result.brief.date === '2027-01-15'),
          check('Результат предварительный', hasCards(result) && result.result.preliminary),
          check('Доступность явно непроверена', result.result?.unchecked.some(value => value.includes('Дата за пределами календаря')))];
      },
    },
    {
      id: 'next_specialist', title: 'Следующий специалист наследует только контекст мероприятия',
      async run(turn) {
        const before = full({ preferences: [calm], excluded_ids: [catalog.contractors[0].id] });
        const result = await turn({ brief: before, message: 'С ведущим закончили. Теперь подбери следующего специалиста — фотографа для того же мероприятия. Для фотографа бюджет, длительность, язык и пожелания ещё не задавал.' });
        return [check('Выбран фотограф', result.brief.category === 'Фотограф'),
          check('Город, дата и формат сохранены', keepsFields(result.brief, before, ['city', 'date', 'event_format'])),
          check('Лимит предыдущего подрядчика сброшен', result.brief.budget_kzt === null && result.brief.hours === null && result.brief.language === null),
          check('Прежние пожелания и исключения сброшены', result.brief.preferences.length === 0 && result.brief.excluded_ids.length === 0)];
      },
    },
  ];

  const report = {
    kind: 'live-provider-evaluation', startedAt: new Date().toISOString(),
    modelVersion: model.version, datasetVersion: catalog.datasetVersion, featureVersion: catalog.featureVersion,
    algorithmVersion, embeddingsArtifactPresent: existsSync(resolve(root, 'functions/data/embeddings.json')),
    latencyTargetMs, latencyPolicy: 'Measured per assistant turn, including optional embedding request; target is not a pre-proven benchmark.',
    cachePolicy: 'Fresh in-memory application cache for each case.', cases: [], providerCalls: calls,
  };
  for (const scenario of cases) {
    const latencyMs = [];
    const entry = { id: scenario.id, title: scenario.title, passed: false, checks: [], latencyMs, latencyTargetMet: false };
    try {
      const app = new AssistantApplication(catalog, new MemoryAssistantCache(), model);
      const turn = async input => {
        const started = performance.now();
        try { return await app.turn(input); }
        finally { latencyMs.push(Math.round(performance.now() - started)); }
      };
      entry.checks = await scenario.run(turn);
      entry.passed = entry.checks.every(item => item.passed);
    } catch (error) {
      // Never print raw provider errors, response bodies, request headers or stack traces.
      entry.errorCode = safeErrorCodes.has(error?.code) ? error.code : 'evaluation-error';
    }
    entry.latencyTargetMet = latencyMs.length > 0 && latencyMs.every(value => value <= latencyTargetMs);
    report.cases.push(entry);
  }
  const timings = report.cases.flatMap(item => item.latencyMs).sort((a, b) => a - b);
  report.summary = {
    passed: report.cases.filter(item => item.passed).length, total: report.cases.length,
    latencyTargetMet: report.cases.every(item => item.latencyTargetMet),
    latencyMedianMs: timings.length ? timings[Math.floor(timings.length / 2)] : null,
    latencyMaxMs: timings.at(-1) ?? null,
  };
  console.log(JSON.stringify(report, null, 2));
  process.exitCode = report.summary.passed === report.summary.total ? 0 : 1;
}

// Unexpected failures are intentionally sanitized too; no stack can reveal a key.
main().catch(() => configurationFailure('Live-проверка завершилась внутренней ошибкой. Проверьте сборку и конфигурацию сервера.'));
