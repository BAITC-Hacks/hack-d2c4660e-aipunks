import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { annotations, featureDefinitions } from './assistant_catalog_annotations.mjs';
import {
  buildArtifacts, sourcePath, outputDirectory, precomputeEmbeddings,
  validateEmbeddings, embeddingDimensions, embeddingModel,
} from './prepare_assistant_catalog.mjs';

const sourceBytes = await readFile(sourcePath);
const { catalog, semantic } = buildArtifacts(sourceBytes);
const profile = id => semantic.profiles.find(entry => entry.id === id);
const feature = (id, key) => profile(id).features.find(entry => entry.key === key);

test('all 66 source profiles are reviewed, including profiles with insufficient detail', () => {
  assert.equal(catalog.length, 66);
  assert.equal(new Set(semantic.profiles.map(entry => entry.id)).size, 66);
  assert.deepEqual(new Set(semantic.profiles.map(entry => entry.id)), new Set(catalog.map(entry => entry.id)));
  for (const annotation of semantic.profiles) {
    assert.equal(annotation.reviewed, true);
    if (!annotation.features.length) assert.ok(annotation.reviewNote.length > 20);
  }
  // Sparse descriptions are retained with unknown features, never padded by AI.
  assert.deepEqual(profile('HK-77793').features, []);
  assert.deepEqual(profile('HK-39301').features, []);
});

test('every evidence quote is an exact source substring and has an ontology label', () => {
  const byId = new Map(catalog.map(entry => [entry.id, entry]));
  for (const annotation of semantic.profiles) {
    for (const evidence of annotation.features) {
      assert.ok(byId.get(annotation.id).description.includes(evidence.quote), `${annotation.id}/${evidence.key}`);
      assert.ok(semantic.featureLabels[evidence.key]);
      assert.ok(['supports', 'contradicts'].includes(evidence.polarity));
    }
  }
  assert.equal(Object.keys(semantic.featureLabels).length, featureDefinitions.length);
});

test('committed server artifacts reproduce the source and curated annotations without changing flags', async () => {
  const preparedCatalog = JSON.parse(await readFile(resolve(outputDirectory, 'catalog.json'), 'utf8'));
  const preparedSemantic = JSON.parse(await readFile(resolve(outputDirectory, 'assistant_catalog.json'), 'utf8'));
  assert.deepEqual(preparedCatalog, catalog);
  assert.deepEqual(preparedSemantic, semantic);
  assert.equal(preparedCatalog.filter(entry => entry.synthetic).length, 13);
  assert.equal(preparedCatalog.find(entry => entry.id === 'HK-64395').city_imputed, true);
  assert.equal(preparedCatalog.find(entry => entry.id === 'HK-61323').price_imputed, true);
});

test('critical negation: no banal contests is narrower than no contests', () => {
  assert.equal(feature('HK-58385', 'no_generic_contests').polarity, 'supports');
  assert.equal(feature('HK-58385', 'no_generic_contests').quote, 'Без шаблонов и банальных конкурсов');
  assert.equal(feature('HK-58385', 'calm_delivery').polarity, 'contradicts');
  assert.match(feature('HK-58385', 'calm_delivery').quote, /не подойдём/);
  assert.ok(semantic.featureLabels.no_contests);
  assert.equal(semantic.profiles.some(entry => entry.features.some(evidence => evidence.key === 'no_contests')), false);
  // Offering games does not prove refusing to adapt a program without games.
  assert.equal(feature('HK-72938', 'interactive_program').polarity, 'supports');
  assert.equal(feature('HK-72938', 'no_contests'), undefined);
  assert.equal(feature('HK-77838', 'no_contests'), undefined);
});

test('poetic wording, prizes, and unverified promises do not become stronger claims', () => {
  assert.equal(feature('HK-53108', 'unobtrusive_work'), undefined); // "тишина внутри кадра"
  assert.equal(feature('HK-26808', 'intelligent_humor'), undefined); // comedy is not a type of humor
  assert.equal(feature('HK-26808', 'comedy_experience').polarity, 'supports');
  assert.equal(feature('HK-90010', 'photo_print').polarity, 'supports'); // printing, not a speed guarantee
  assert.equal(feature('HK-90012', 'capacity_200'), undefined);
  assert.equal(feature('HK-90011', 'capacity_200').quote, 'вместимость зала до 200 гостей');
  assert.match(feature('HK-68220', 'documentary_photo').quote, /постановочных кадров/);
});

test('four real demo candidates have grounded evidence and pass their structured constraints', () => {
  const demos = [
    { id: 'HK-44733', city: 'Алматы', format: 'корпоратив', budget: 1_000_000, keys: ['calm_delivery', 'intimate_event_experience'] },
    { id: 'HK-61323', city: 'Астана', format: 'свадьба', budget: 300_000, keys: ['documentary_photo', 'posing_help'] },
    { id: 'HK-46450', city: 'Алматы', format: 'корпоратив', budget: 400_000, keys: ['jazz', 'welcome_music', 'kazakh_repertoire'] },
    { id: 'HK-64395', city: 'Алматы', format: 'свадьба', budget: 3_000_000, keys: ['terrace', 'mountain_view'] },
  ];
  for (const demo of demos) {
    const contractor = catalog.find(entry => entry.id === demo.id);
    assert.equal(contractor.city, demo.city);
    assert.ok(contractor.event_formats.includes(demo.format));
    assert.ok(contractor.price_from_kzt <= demo.budget);
    assert.equal(contractor.busy_dates.includes('2026-11-14'), false);
    for (const key of demo.keys) assert.equal(feature(demo.id, key).polarity, 'supports');
  }
  // Semantic similarity must never make an unavailable photographer available.
  assert.ok(catalog.find(entry => entry.id === 'HK-98562').busy_dates.includes('2026-11-14'));
});

test('preparation rejects missing ids, duplicate ids, invented quotes, and unknown ontology keys', () => {
  assert.throws(() => buildArtifacts(sourceBytes, annotations.slice(1)), /Missing annotations/);
  assert.throws(() => buildArtifacts(sourceBytes, [...annotations, annotations[0]]), /Duplicate annotation id/);
  const invented = structuredClone(annotations);
  invented[1].features[0].quote = 'This evidence was invented and is not in the source.';
  assert.throws(() => buildArtifacts(sourceBytes, invented), /exact source substring/);
  const wrongKey = structuredClone(annotations);
  wrongKey[1].features[0].key = 'not_in_the_ontology';
  assert.throws(() => buildArtifacts(sourceBytes, wrongKey), /Unknown feature/);
});

test('missing API key fails before any request and does not fabricate vectors', async () => {
  let called = false;
  await assert.rejects(precomputeEmbeddings(catalog, semantic, { fetchImpl: () => { called = true; } }), /OPENAI_API_KEY is required/);
  assert.equal(called, false);
});

test('malformed multiline keys are rejected before headers can leak them', async () => {
  const fakeSecret = 'unit-test-secret\nsecond-secret-line';
  let called = false;
  await assert.rejects(precomputeEmbeddings(catalog, semantic, {
    apiKey: fakeSecret, fetchImpl: () => { called = true; },
  }), error => {
    assert.match(error.message, /invalid format/);
    assert.equal(error.message.includes('unit-test-secret'), false);
    assert.equal(error.message.includes('second-secret-line'), false);
    assert.equal(error.cause, undefined);
    return true;
  });
  assert.equal(called, false);
});

test('transport and JSON errors cannot echo the Authorization secret', async () => {
  const fakeSecret = 'unit-test-sensitive-credential';
  for (const fetchImpl of [
    async () => { throw new Error(`Proxy failure for Authorization: Bearer ${fakeSecret}`); },
    async () => ({ ok: true, json: async () => { throw new Error(`Unexpected JSON: ${fakeSecret}`); } }),
  ]) {
    await assert.rejects(precomputeEmbeddings(catalog, semantic, { apiKey: fakeSecret, fetchImpl }), error => {
      assert.equal(error.message.includes(fakeSecret), false);
      assert.equal(error.cause, undefined);
      assert.match(error.message, /no embedding artifact was written/);
      return true;
    });
  }
});

test('real-API adapter validates the batch and restores source ordering by response index', async () => {
  // Synthetic transport fixtures exist only in this test, are never written to
  // an artifact, and cannot be selected by the production preparation script.
  const artifact = await precomputeEmbeddings(catalog, semantic, {
    apiKey: 'unit-test-key',
    fetchImpl: async (url, options) => {
      assert.equal(url, 'https://api.openai.com/v1/embeddings');
      assert.equal(options.headers.Authorization, 'Bearer unit-test-key');
      const body = JSON.parse(options.body);
      assert.equal(body.model, embeddingModel);
      assert.equal(body.dimensions, embeddingDimensions);
      assert.equal(body.input.length, 66);
      assert.ok(body.input.some(input => input.includes('Если вам нужен тихий, формальный вечер')));
      return { ok: true, json: async () => ({
        model: embeddingModel,
        data: catalog.map((_, index) => ({ index, embedding: Array(embeddingDimensions).fill((index + 1) / 1000) })).reverse(),
      }) };
    },
  });
  assert.deepEqual(artifact.profiles.map(entry => entry.id), catalog.map(entry => entry.id));
  assert.equal(artifact.profiles[0].embedding[0], 0.001);
  validateEmbeddings(artifact, catalog, semantic);
  assert.equal(JSON.stringify(artifact).includes('unit-test-key'), false);
  assert.throws(() => validateEmbeddings({ ...artifact, datasetVersion: 'wrong' }, catalog, semantic), /metadata/);
  assert.throws(() => validateEmbeddings({ ...artifact, inputVersion: 'wrong' }, catalog, semantic), /different descriptions/);
  const bad = structuredClone(artifact);
  bad.profiles[0].embedding.fill(0);
  assert.throws(() => validateEmbeddings(bad, catalog, semantic), /Zero embedding/);
});

test('embedding adapter rejects API failure and incomplete response batches', async () => {
  await assert.rejects(precomputeEmbeddings(catalog, semantic, {
    apiKey: 'unit-test-key', fetchImpl: async () => ({ ok: false, status: 429 }),
  }), /HTTP 429/);
  await assert.rejects(precomputeEmbeddings(catalog, semantic, {
    apiKey: 'unit-test-key', fetchImpl: async () => ({ ok: true, json: async () => ({ model: embeddingModel, data: [] }) }),
  }), /incomplete embedding batch/);
});
