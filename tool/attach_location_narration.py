#!/usr/bin/env python3
"""Backfill public.locations.narration_ids + audio_files from location_content.

Mirrors lib/.../location_narration.dart resolveNarrationLinks: for each master
location, attach every location_content narration within 1 mile that matches by
name / category / proximity, best-first. Idempotent (overwrites the two fields).
"""
import json
import math
import os
import sys
import urllib.request

BASE = os.environ["SUPABASE_URL"].rstrip("/")
KEY = os.environ["SUPABASE_SERVICE_KEY"]
HEADERS = {"apikey": KEY, "Authorization": f"Bearer {KEY}",
           "Content-Type": "application/json"}
RADIUS_M = 1609.344


def _req(method, path, body=None, extra=None):
    url = f"{BASE}/rest/v1/{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    for k, v in {**HEADERS, **(extra or {})}.items():
        req.add_header(k, v)
    with urllib.request.urlopen(req) as r:
        raw = r.read().decode()
        return r.status, (json.loads(raw) if raw else None)


def get_all(table, select="*"):
    out, step, off = [], 1000, 0
    while True:
        _, rows = _req("GET", f"{table}?select={select}&limit={step}&offset={off}")
        rows = rows or []
        out.extend(rows)
        if len(rows) < step:
            return out
        off += step


def haversine(a_lat, a_lng, b_lat, b_lng):
    r = 6371000.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp = math.radians(b_lat - a_lat)
    dl = math.radians(b_lng - a_lng)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


RELEVANT = {
    "county": {"county_welcome", "county_history", "county_fun_facts",
               "county_nature", "county_agriculture", "county_economy",
               "county_hidden_gems"},
    "city": {"city_welcome", "city_history", "city_fun_facts", "city_intro"},
    "community": {"community_story"},
    "spring": {"water"},
    "river": {"river_story", "water"},
    "lake": {"lake_story", "water"},
    "forest": {"forest_story", "park"},
    "state_park": {"park", "park_story", "arrival", "wildlife", "plants"},
    "national_park": {"park", "park_story", "arrival", "wildlife", "plants"},
    "county_park": {"park", "park_story", "arrival", "wildlife", "plants"},
    "historic_site": {"history", "historic_landmark"},
    "historic_district": {"history", "historic_landmark"},
    "scenic_road": {"scenic_drive", "scenic_road", "historic_highway"},
    "trail": {"trails"},
    "trailhead": {"trails"},
    "scenic_overlook": {"scenic_overlook"},
    "museum": {"museum"},
    "restaurant": {"restaurant"},
    "hidden_gem": {"hidden_gem"},
    "wildlife_viewing": {"wildlife", "birds"},
}


def name_overlap(a, b):
    a, b = (a or "").lower().strip(), (b or "").lower().strip()
    return bool(a) and bool(b) and (a in b or b in a)


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def main():
    dry = "--apply" not in sys.argv
    locations = get_all("locations", "id,name,category,latitude,longitude")
    content = get_all("location_content",
                      "id,title,category,latitude,longitude,audio_url,text,priority")
    content = [c for c in content
               if num(c.get("latitude")) is not None
               and num(c.get("longitude")) is not None
               and ((c.get("audio_url") or "") or (c.get("text") or ""))]
    print(f"{len(locations)} locations, {len(content)} usable content rows")

    updates = []
    for loc in locations:
        lat, lng = num(loc.get("latitude")), num(loc.get("longitude"))
        if lat is None or lng is None or (lat == 0 and lng == 0):
            continue
        relevant = RELEVANT.get(loc.get("category"), {"attraction", "history"})
        scored = []
        for c in content:
            m = haversine(lat, lng, float(c["latitude"]), float(c["longitude"]))
            if m > RADIUS_M:
                continue
            score = -(int(m) // 50)
            if name_overlap(loc.get("name"), c.get("title")):
                score += 500
            if c.get("category") in relevant:
                score += 200
            if c.get("audio_url"):
                score += 120
            score += int(c.get("priority") or 0)
            scored.append((score, c))
        if not scored:
            continue
        scored.sort(key=lambda t: t[0], reverse=True)
        ids = [c["id"] for _, c in scored]
        audio = [c["audio_url"] for _, c in scored if c.get("audio_url")]
        updates.append((loc, ids, audio))

    print(f"{len(updates)} locations would get narration links")
    for loc, ids, audio in updates[:5]:
        print(f"  {loc['name']}: {len(ids)} narration, {len(audio)} audio")
    if dry:
        print("DRY RUN — pass --apply to persist.")
        return
    done = 0
    for loc, ids, audio in updates:
        _req("PATCH", f"locations?id=eq.{loc['id']}",
             {"narration_ids": ids, "audio_files": audio},
             extra={"Prefer": "return=minimal"})
        done += 1
    print(f"done: persisted links to {done} locations")


if __name__ == "__main__":
    main()
