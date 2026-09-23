#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { annotations, featureDefinitions, featureVersion } from './assistant_catalog_annotations.mjs';

export const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const sourcePath = resolve(repositoryRoot, 'apps/event_match/assets/data/catalog.jsonl');
export const outputDirectory = resolve(repositoryRoot, 'functions/data');
export const embeddingModel = 'text-embedding-3-small';
export const embeddingDimensions = 1536;
const sha256 = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

/** Pure preparation: all domain data comes from the original JSONL unchanged. */
export function buildArtifacts(sourceBytes, reviewedAnnotations = annotations) {
  const catalog = sourceBytes.toString('utf8').split(/\r?\n/).filter(line => line.trim()).map(line => JSON.parse(line));
  if (catalog.length !== 66) throw new Error(`Expected the reviewed 66-profile dataset; got ${catalog.length}`);
  const byId = new Map(catalog.map(contractor => [contractor.id, contractor]));
  if (byId.size !== catalog.length) throw new Error('Catalog contains duplicate ids');
  const keys = new Set(featureDefinitions.map(feature => feature.key));
  if (keys.size !== featureDefinitions.length) throw new Error('Ontology contains duplicate keys');
  const seen = new Set();
  for (const annotation of reviewedAnnotations) {
    if (seen.has(annotation.id)) throw new Error(`Duplicate annotation id: ${annotation.id}`);
    seen.add(annotation.id);
    const contractor = byId.get(annotation.id);
    if (!contractor) throw new Error(`Unknown annotation id: ${annotation.id}`);
    if (annotation.reviewed !== true) throw new Error(`Unreviewed annotation: ${annotation.id}`);
    if (!annotation.features.length && !annotation.reviewNote) throw new Error(`Empty profile requires a review note: ${annotation.id}`);
    const seenFeatures = new Set();
    for (const feature of annotation.features) {
      if (!keys.has(feature.key)) throw new Error(`Unknown feature: ${annotation.id}/${feature.key}`);
      if (!['supports', 'contradicts'].includes(feature.polarity)) throw new Error(`Invalid polarity: ${annotation.id}/${feature.key}`);
      if (typeof feature.quote !== 'string' || feature.quote.trim().length < 4 || !contractor.description.includes(feature.quote)) {
        throw new Error(`Quote is not an exact source substring: ${annotation.id}/${feature.key}`);
      }
      if (seenFeatures.has(feature.key)) throw new Error(`Duplicate feature: ${annotation.id}/${feature.key}`);
      seenFeatures.add(feature.key);
    }
  }
  if (seen.size !== catalog.length) {
    throw new Error(`Missing annotations: ${catalog.filter(contractor => !seen.has(contractor.id)).map(contractor => contractor.id).join(', ')}`);
  }
  const metadata = {
    schemaVersion: 1,
    datasetVersion: sha256(sourceBytes),
    featureVersion,
  };
  return {
    catalog,
    semantic: {
      ...metadata,
      source: 'apps/event_match/assets/data/catalog.jsonl',
      evidencePolicy: 'Quotes are exact source substrings. Profile statements are not independently verified. Missing features mean unknown. Semantic features never override structured city, category, date, price, format, language or hours.',
      featureDefinitions,
      featureLabels: Object.fromEntries(featureDefinitions.map(feature => [feature.key, feature.label])),
      profiles: reviewedAnnotations,
    },
  };
}

export function embeddingInput(contractor, semanticProfile, labels) {
  const evidence = semanticProfile.features.map(feature =>
    `${feature.polarity === 'supports' ? 'Указано в профиле' : 'Профиль противоречит пожеланию'} «${labels[feature.key]}»: ${feature.quote}`,
  );
  return [`Категории: ${contractor.categories.join(', ')}`, contractor.description, ...evidence].join('\n');
}

export function validateEmbeddings(artifact, catalog, semantic) {
  if (artifact.schemaVersion !== 1 || artifact.datasetVersion !== semantic.datasetVersion || artifact.featureVersion !== semantic.featureVersion) {
    throw new Error('Embeddings metadata does not match the current catalog and feature versions');
  }
  if (artifact.model !== embeddingModel || artifact.dimensions !== embeddingDimensions) throw new Error('Unexpected embedding model or dimensions');
  const semanticById = new Map(semantic.profiles.map(profile => [profile.id, profile]));
  const input = catalog.map(contractor => embeddingInput(contractor, semanticById.get(contractor.id), semantic.featureLabels));
  if (artifact.inputVersion !== sha256(JSON.stringify(input))) throw new Error('Embeddings were generated from different descriptions or evidence');
  if (!Array.isArray(artifact.profiles) || artifact.profiles.length !== catalog.length) throw new Error('Embeddings do not cover every profile');
  const byId = new Map(artifact.profiles.map(profile => [profile.id, profile.embedding]));
  if (byId.size !== catalog.length) throw new Error('Duplicate embedding ids');
  for (const contractor of catalog) {
    const vector = byId.get(contractor.id);
    if (!Array.isArray(vector) || vector.length !== embeddingDimensions || !vector.every(value => typeof value === 'number' && Number.isFinite(value))) {
      throw new Error(`Invalid embedding: ${contractor.id}`);
    }
    if (!vector.some(value => value !== 0)) throw new Error(`Zero embedding is not a real vector: ${contractor.id}`);
  }
}

/** Calls the real API only on explicit --embeddings; never fabricates a fallback. */
export async function precomputeEmbeddings(catalog, semantic, { apiKey, fetchImpl = globalThis.fetch } = {}) {
  if (typeof apiKey !== 'string' || !apiKey.trim()) throw new Error('OPENAI_API_KEY is required for --embeddings. No embeddings artifact was created.');
  const secret = apiKey.trim();
  // Undici includes an invalid header's entire value in its exception. Validate
  // before constructing Authorization so a malformed local key cannot be logged.
  if (/[^\x21-\x7e]/.test(secret)) throw new Error('OPENAI_API_KEY has an invalid format. Use a single key without internal whitespace.');
  const byId = new Map(semantic.profiles.map(profile => [profile.id, profile]));
  const input = catalog.map(contractor => embeddingInput(contractor, byId.get(contractor.id), semantic.featureLabels));
  let response;
  try {
    response = await fetchImpl('https://api.openai.com/v1/embeddings', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${secret}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: embeddingModel, dimensions: embeddingDimensions, input, encoding_format: 'float' }),
      signal: AbortSignal.timeout(60_000),
    });
  } catch {
    // Transport and proxy errors may include request headers. Never preserve
    // their message/cause in the exception shown by the CLI.
    throw new Error('OpenAI embedding connection failed or timed out; no embedding artifact was written.');
  }
  if (!response.ok) throw new Error(`OpenAI embedding request failed (HTTP ${response.status}); no embedding artifact was written.`);
  let payload;
  try { payload = await response.json(); }
  catch { throw new Error('OpenAI embedding response was not valid JSON; no embedding artifact was written.'); }
  if (payload.model !== embeddingModel || !Array.isArray(payload.data) || payload.data.length !== catalog.length) {
    throw new Error('OpenAI returned an unexpected model or incomplete embedding batch');
  }
  const byIndex = new Map();
  for (const item of payload.data) {
    if (!Number.isInteger(item.index) || item.index < 0 || item.index >= catalog.length || byIndex.has(item.index)) {
      throw new Error('OpenAI returned invalid or duplicate embedding indices');
    }
    byIndex.set(item.index, item.embedding);
  }
  const artifact = {
    schemaVersion: 1,
    datasetVersion: semantic.datasetVersion,
    featureVersion: semantic.featureVersion,
    model: embeddingModel,
    dimensions: embeddingDimensions,
    inputVersion: sha256(JSON.stringify(input)),
    profiles: catalog.map((contractor, index) => ({ id: contractor.id, embedding: byIndex.get(index) })),
  };
  validateEmbeddings(artifact, catalog, semantic);
  return artifact;
}

const json = value => `${JSON.stringify(value, null, 2)}\n`;

async function main() {
  const flags = new Set(process.argv.slice(2));
  for (const flag of flags) {
    if (!['--check', '--embeddings'].includes(flag)) throw new Error(`Unknown argument: ${flag}. Use --check or --embeddings.`);
  }
  if (flags.has('--check') && flags.has('--embeddings')) throw new Error('--check cannot call the embedding API or write files');
  const { catalog, semantic } = buildArtifacts(await readFile(sourcePath));
  const outputs = [['catalog.json', catalog], ['assistant_catalog.json', semantic]];
  if (flags.has('--check')) {
    for (const [filename, value] of outputs) {
      if (await readFile(resolve(outputDirectory, filename), 'utf8') !== json(value)) throw new Error(`${filename} is stale; rerun the preparation script`);
    }
    let embeddings;
    try { embeddings = JSON.parse(await readFile(resolve(outputDirectory, 'embeddings.json'), 'utf8')); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (embeddings) validateEmbeddings(embeddings, catalog, semantic);
    console.log(`Verified ${catalog.length} profiles, all exact evidence quotes, ${semantic.featureDefinitions.length} feature definitions. Embeddings: ${embeddings ? 'present and validated' : 'absent (evidence ranking remains available)'}.`);
    return;
  }
  let embeddings;
  if (flags.has('--embeddings')) {
    // Read secrets only from the executing process; never copy them into artifacts.
    embeddings = await precomputeEmbeddings(catalog, semantic, { apiKey: process.env.OPENAI_API_KEY });
  }
  await mkdir(outputDirectory, { recursive: true });
  for (const [filename, value] of outputs) await writeFile(resolve(outputDirectory, filename), json(value));
  if (embeddings) await writeFile(resolve(outputDirectory, 'embeddings.json'), json(embeddings));
  console.log(`Prepared ${catalog.length} profiles with reviewed evidence (${semantic.datasetVersion}). ${embeddings ? 'Real OpenAI embeddings written.' : 'Embeddings not generated; use --embeddings with OPENAI_API_KEY.'}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
