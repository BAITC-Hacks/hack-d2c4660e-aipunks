"""Convert the organizer CSV to validated UTF-8 JSONL (stdlib only)."""
import argparse
import csv
import json
from datetime import date
from pathlib import Path


def convert(source: Path, destination: Path):
    profiles = []
    seen = set()
    with source.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            profile = {key: row[key].strip() for key in ("id", "anon_name", "city", "description")}
            if not all(profile.values()) or profile["id"] in seen:
                raise ValueError(f"Missing fields or duplicate id: {profile['id']}")
            seen.add(profile["id"])
            for key in ("categories", "event_formats", "languages", "busy_dates"):
                profile[key] = [part.strip() for part in row[key].split("|") if part.strip()]
            for key in ("synthetic", "city_imputed", "price_imputed"):
                value = row[key].strip().lower()
                if value not in ("true", "false"):
                    raise ValueError(f"Invalid boolean: {key}")
                profile[key] = value == "true"
            profile["price_from_kzt"] = int(row["price_from_kzt"])
            profile["max_hours"] = float(row["max_hours"]) if row["max_hours"].strip() else None
            if profile["price_from_kzt"] < 0:
                raise ValueError("Negative price")
            if profile["max_hours"] is not None and not 0 < profile["max_hours"] <= 1000:
                raise ValueError("Invalid hours")
            for busy in profile["busy_dates"]:
                if not date(2026, 9, 23) <= date.fromisoformat(busy) <= date(2026, 12, 31):
                    raise ValueError(f"Date outside calendar: {busy}")
            profiles.append(profile)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(json.dumps(p, ensure_ascii=False) for p in profiles) + "\n", encoding="utf-8")
    print(f"Imported {len(profiles)} profiles; synthetic={sum(p['synthetic'] for p in profiles)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    convert(args.source, args.destination)
