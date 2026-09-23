import { readFileSync } from "node:fs";
import { resolve } from "node:path";
export function makeCatalog(contractors, artifact) {
    if (artifact.schemaVersion !== 1 || !artifact.datasetVersion || !artifact.featureVersion) {
        throw new Error("Unsupported contractor evidence artifact");
    }
    const ids = new Set(contractors.map((item)=>item.id));
    if (ids.size !== contractors.length) throw new Error("Duplicate contractor ids");
    const keys = new Set(artifact.featureDefinitions.map((item)=>item.key));
    const features = new Map();
    for (const profile of artifact.profiles){
        const contractor = contractors.find((item)=>item.id === profile.id);
        if (!contractor) throw new Error("Evidence refers to an unknown contractor");
        const supported = profile.features.filter((feature)=>keys.has(feature.key) && feature.quote.length > 0 && contractor.description.includes(feature.quote) && (feature.polarity === "supports" || feature.polarity === "contradicts"));
        if (supported.length !== profile.features.length) throw new Error("Unverifiable contractor evidence");
        features.set(profile.id, supported);
    }
    return {
        contractors,
        datasetVersion: artifact.datasetVersion,
        featureVersion: artifact.featureVersion,
        featureDefinitions: artifact.featureDefinitions,
        features
    };
}
let loaded;
export function loadCatalog() {
    if (!loaded) {
        const directory = resolve(import.meta.dirname, "../../data");
        loaded = makeCatalog(JSON.parse(readFileSync(resolve(directory, "catalog.json"), "utf8")), JSON.parse(readFileSync(resolve(directory, "assistant_catalog.json"), "utf8")));
    }
    return loaded;
}
