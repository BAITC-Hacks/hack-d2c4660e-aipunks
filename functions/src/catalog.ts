import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type { Catalog, Contractor, FeatureDefinition, ProfileFeature } from "./types";

interface FeatureArtifact {
  schemaVersion: number; datasetVersion: string; featureVersion: string;
  featureDefinitions: FeatureDefinition[];
  profiles: { id: string; features: ProfileFeature[] }[];
}

/** Feature evidence is accepted only if its exact quotation exists in the source profile. */
export function makeCatalog(contractors: Contractor[], artifact: FeatureArtifact): Catalog {
  if (artifact.schemaVersion !== 1 || !artifact.datasetVersion || !artifact.featureVersion) {
    throw new Error("Unsupported contractor evidence artifact");
  }
  const ids = new Set(contractors.map((item) => item.id));
  if (ids.size !== contractors.length) throw new Error("Duplicate contractor ids");
  const keys = new Set(artifact.featureDefinitions.map((item) => item.key));
  const features = new Map<string, ProfileFeature[]>();
  for (const profile of artifact.profiles) {
    const contractor = contractors.find((item) => item.id === profile.id);
    if (!contractor) throw new Error("Evidence refers to an unknown contractor");
    const supported = profile.features.filter((feature) =>
      keys.has(feature.key) && feature.quote.length > 0 && contractor.description.includes(feature.quote) &&
      (feature.polarity === "supports" || feature.polarity === "contradicts"));
    if (supported.length !== profile.features.length) throw new Error("Unverifiable contractor evidence");
    features.set(profile.id, supported);
  }
  return { contractors, datasetVersion: artifact.datasetVersion, featureVersion: artifact.featureVersion,
    featureDefinitions: artifact.featureDefinitions, features };
}

let loaded: Catalog | undefined;
export function loadCatalog(): Catalog {
  if (!loaded) {
    const directory = resolve(__dirname, "../data");
    loaded = makeCatalog(
      JSON.parse(readFileSync(resolve(directory, "catalog.json"), "utf8")) as Contractor[],
      JSON.parse(readFileSync(resolve(directory, "assistant_catalog.json"), "utf8")) as FeatureArtifact,
    );
  }
  return loaded;
}
