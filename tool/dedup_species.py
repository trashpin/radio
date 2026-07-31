#!/usr/bin/env python3
"""Clean & normalize the ExplorerOS `species` catalog — merge duplicates safely.

Duplicates are detected CONSERVATIVELY (no fuzzy spelling, so distinct species
are never merged): two species are the same when they share a normalized
common name OR a normalized scientific name (lowercased, trimmed, whitespace
collapsed, punctuation removed). Union-find clusters e.g. "Black Bear",
"black bear", "Black  Bear" (and "American Black Bear" when the scientific name
matches).

For each cluster it keeps the MOST COMPLETE record (survivor), coalesces every
missing field from the duplicates (no data lost), repoints all references
(media.species_id, audio_assets.record_id, media_assets.record_id) to the
survivor, then deletes the duplicates.

SAFETY: writes a full JSON backup (species + linked media/audio/media_assets)
to Storage before any change, prints a summary, and is reversible from the
backup. `--apply` performs writes; without it, it's a dry run.

Usage:
  python3 tool/dedup_species.py                 # dry run + report
  python3 tool/dedup_species.py --apply         # backup, merge, delete, report
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

BASE = os.environ["SUPABASE_URL"].rstrip("/")
SVC = os.environ["SUPABASE_SERVICE_KEY"]
BUCKET = "media"

# Species text fields used for completeness scoring + coalescing.
FIELDS = [
    "scientific_name", "pronunciation", "description", "size", "weight",
    "color", "shape", "special_markings", "male_vs_female", "juvenile_notes",
    "diet", "behavior", "life_span", "breeding", "conservation_status",
    "safety_info", "fun_facts", "hero_image", "hero_media_id",
]
SPECIFIC_CATS = {"plants", "birds", "reptiles", "amphibians", "fish", "trees",
                 "wildflowers"}


def sb(method, path, body=None, extra=None):
    url = f"{BASE}/rest/v1/{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    for k, v in {"apikey": SVC, "Authorization": f"Bearer {SVC}",
                 "Content-Type": "application/json", **(extra or {})}.items():
        req.add_header(k, v)
    with urllib.request.urlopen(req) as r:
        b = r.read()
        return r.status, (json.loads(b) if b else None)


def get_all(table, select="*"):
    out, step, off = [], 1000, 0
    while True:
        _, rows = sb("GET", f"{table}?select={select}&limit={step}&offset={off}")
        rows = rows or []
        out.extend(rows)
        if len(rows) < step:
            return out
        off += step


def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def score(sp):
    n = sum(1 for f in FIELDS if str(sp.get(f) or "").strip())
    if sp.get("published"):
        n += 1
    if str(sp.get("hero_image") or "").strip():
        n += 2  # a real image is valuable
    return n


def upload_backup(payload):
    path = f"backups/species_dedup_{int(time.time())}.json"
    data = json.dumps(payload, indent=2).encode()
    req = urllib.request.Request(
        f"{BASE}/storage/v1/object/{BUCKET}/{path}", data=data, method="POST")
    for k, v in {"apikey": SVC, "Authorization": f"Bearer {SVC}",
                 "x-upsert": "true", "Content-Type": "application/json"}.items():
        req.add_header(k, v)
    with urllib.request.urlopen(req) as r:
        r.read()
    return f"{BASE}/storage/v1/object/public/{BUCKET}/{path}"


class UF:
    def __init__(self):
        self.p = {}

    def find(self, x):
        self.p.setdefault(x, x)
        while self.p[x] != x:
            self.p[x] = self.p[self.p[x]]
            x = self.p[x]
        return x

    def union(self, a, b):
        self.p[self.find(a)] = self.find(b)


def main():
    apply = "--apply" in sys.argv
    species = get_all("species")
    print(f"Loaded {len(species)} species.")

    # Cluster by shared normalized common OR scientific name.
    uf = UF()
    by_common, by_sci = {}, {}
    for s in species:
        sid = s["species_id"]
        uf.find(sid)
        c = norm(s.get("common_name"))
        if c:
            if c in by_common:
                uf.union(sid, by_common[c])
            else:
                by_common[c] = sid
        sci = norm(s.get("scientific_name"))
        if sci:
            if sci in by_sci:
                uf.union(sid, by_sci[sci])
            else:
                by_sci[sci] = sid

    clusters = {}
    idx = {s["species_id"]: s for s in species}
    for s in species:
        clusters.setdefault(uf.find(s["species_id"]), []).append(s)
    dup_clusters = {k: v for k, v in clusters.items() if len(v) > 1}

    total_dups = sum(len(v) - 1 for v in dup_clusters.values())
    print(f"Duplicate clusters: {len(dup_clusters)}  "
          f"(removing {total_dups} duplicate rows; "
          f"{len(species) - total_dups} species will remain)")

    # Build the merge plan.
    plan = []  # (survivor, losers, merged_fields, merged_category)
    for members in dup_clusters.values():
        members.sort(key=lambda s: (score(s), str(s.get("created_at") or "")),
                     reverse=True)
        survivor = members[0]
        losers = members[1:]
        merged = {}
        for f in FIELDS:
            if not str(survivor.get(f) or "").strip():
                for m in members:
                    v = str(m.get(f) or "").strip()
                    if v:
                        merged[f] = m.get(f)
                        break
        # Fix mis-categorization: prefer a specific category over "animals".
        cat = survivor.get("category")
        if cat == "animals":
            for m in members:
                if m.get("category") in SPECIFIC_CATS:
                    merged["category"] = m["category"]
                    break
        plan.append((survivor, losers, merged, merged.get("category", cat)))

    for survivor, losers, merged, cat in plan[:40]:
        names = ", ".join(sorted({m["common_name"] for m in [survivor] + losers}))
        print(f"  KEEP '{survivor['common_name']}' ({cat}) "
              f"<- merge {len(losers)}  [{names}]")

    if not apply:
        print("\nDRY RUN — pass --apply to back up + merge + delete.")
        return

    # ---- Apply ----
    dup_ids = {m["species_id"] for _, losers, _, _ in plan for m in losers}
    media = [m for m in get_all("media") if m.get("species_id") in dup_ids
             or m.get("species_id") in {s["species_id"] for s, *_ in plan}]
    aa = get_all("audio_assets", "id,record_id,record_type")
    ma = get_all("media_assets", "id,record_id,record_type")
    aa_ref = [r for r in aa if r.get("record_id") in dup_ids]
    ma_ref = [r for r in ma if r.get("record_id") in dup_ids]

    backup_url = upload_backup({
        "created": int(time.time()),
        "species": species,
        "media_species_links": [m for m in media],
        "audio_assets_refs": aa_ref,
        "media_assets_refs": ma_ref,
    })
    print(f"\nBackup written: {backup_url}")

    merged_groups = deleted = repointed = 0
    for survivor, losers, merged, cat in plan:
        sid = survivor["species_id"]
        if merged:
            sb("PATCH", f"species?species_id=eq.{sid}", merged,
               extra={"Prefer": "return=minimal"})
        for m in losers:
            lid = m["species_id"]
            for tbl, col in [("media", "species_id"),
                             ("audio_assets", "record_id"),
                             ("media_assets", "record_id")]:
                _, _ = sb("PATCH",
                          f"{tbl}?{col}=eq.{urllib.parse.quote(lid)}",
                          {col: sid}, extra={"Prefer": "return=minimal"})
            sb("DELETE", f"species?species_id=eq.{urllib.parse.quote(lid)}",
               extra={"Prefer": "return=minimal"})
            deleted += 1
            repointed += 1
        merged_groups += 1

    remaining = len(species) - deleted
    print("\n=== Species dedup complete ===")
    print(f"Clusters merged:   {merged_groups}")
    print(f"Duplicates deleted:{deleted}")
    print(f"References moved:  {repointed} loser records repointed to survivors")
    print(f"Species remaining: {remaining}")
    print(f"Backup (reversible): {backup_url}")


if __name__ == "__main__":
    main()
