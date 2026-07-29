#!/usr/bin/env python3
"""One-off REST backfill of public.locations from map_locations + destinations.

Matched to the LIVE table schemas (introspected). Idempotent-ish: run against an
empty locations table. Category mapping mirrors public.map_location_type().
"""
import json
import os
import re
import sys
import urllib.request

BASE = os.environ["SUPABASE_URL"].rstrip("/")
KEY = os.environ["SUPABASE_SERVICE_KEY"]
HEADERS = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Content-Type": "application/json",
}


def _req(method, path, body=None, extra=None):
    url = f"{BASE}/rest/v1/{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    for k, v in HEADERS.items():
        req.add_header(k, v)
    for k, v in (extra or {}).items():
        req.add_header(k, v)
    with urllib.request.urlopen(req) as r:
        raw = r.read().decode()
        return r.status, (json.loads(raw) if raw else None)


def get_all(table, select="*"):
    out, step = [], 1000
    off = 0
    while True:
        _, rows = _req(
            "GET",
            f"{table}?select={select}&limit={step}&offset={off}",
        )
        rows = rows or []
        out.extend(rows)
        if len(rows) < step:
            break
        off += step
    return out


def map_type(raw, nm):
    t = f"{(raw or '')} {(nm or '')}".lower()

    def has(p):
        return re.search(p, t) is not None

    rules = [
        # Administrative + park designations win over embedded water words
        # (e.g. "Alafia River State Park" is a state park, not a river).
        (r"community|unincorporated", "community"),
        (r"national park", "national_park"),
        (r"state park", "state_park"),
        (r"county park", "county_park"),
        (r"county", "county"),
        (r"national forest|state forest|forest", "forest"),
        (r"city|town", "city"),
        (r"spring", "spring"),
        (r"river|creek", "river"),
        (r"lake|pond|reservoir", "lake"),
        (r"historic district", "historic_district"),
        (r"histor|fort|heritage|monument", "historic_site"),
        (r"scenic road|byway|scenic drive|highway", "scenic_road"),
        (r"trailhead", "trailhead"),
        (r"trail", "trail"),
        (r"camp", "campground"),
        (r"boat ramp|boat|ramp", "boat_ramp"),
        (r"visitor", "visitor_center"),
        (r"wildlife", "wildlife_viewing"),
        (r"overlook|scenic|vista", "scenic_overlook"),
        (r"museum", "museum"),
        (r"restaurant|food|dining", "restaurant"),
        (r"gas|fuel", "gas_station"),
        (r"parking", "parking"),
        (r"safety|alert|warning", "safety_alert"),
        (r"hidden|gem", "hidden_gem"),
        (r"attraction", "attraction"),
    ]
    for pat, val in rules:
        if has(pat):
            return val
    return "point_of_interest"


def valid_coords(lat, lng):
    if lat is None or lng is None:
        return False
    try:
        lat, lng = float(lat), float(lng)
    except (TypeError, ValueError):
        return False
    if lat == 0 and lng == 0:
        return False
    return abs(lat) <= 90 and abs(lng) <= 180


def name_of(v, fallback="Unnamed"):
    v = (v or "").strip()
    return v if v else fallback


def build_rows():
    rows = []

    for m in get_all("map_locations"):
        if not valid_coords(m.get("latitude"), m.get("longitude")):
            continue
        images = []
        if m.get("image_url"):
            images.append(m["image_url"])
        gal = m.get("gallery_urls")
        if isinstance(gal, list):
            images.extend([g for g in gal if g])
        rows.append({
            "name": name_of(m.get("name")),
            "category": map_type(m.get("category"), m.get("name")),
            "latitude": m.get("latitude"),
            "longitude": m.get("longitude"),
            "description": m.get("description"),
            "trigger_radius": m.get("trigger_radius_m"),
            "images": images,
            "audio_files": [m["audio_url"]] if m.get("audio_url") else [],
            "destination_code": m.get("park_code"),
            "featured": bool(m.get("featured")),
            "source": "map_locations",
            "source_id": str(m.get("id")),
            "active": True,
        })

    for d in get_all("destinations"):
        if not valid_coords(d.get("latitude"), d.get("longitude")):
            continue
        rows.append({
            "name": name_of(d.get("name")),
            "category": map_type(d.get("destination_type"), d.get("name")),
            "latitude": d.get("latitude"),
            "longitude": d.get("longitude"),
            "address": d.get("address"),
            "description": d.get("description"),
            "images": [d["hero_image"]] if d.get("hero_image") else [],
            "destination_code": d.get("destination_code") or str(d.get("destination_id")),
            "featured": bool(d.get("featured")),
            "source": "destinations",
            "source_id": str(d.get("destination_id")),
            "active": True,
        })
    return rows


_ARRAY_KEYS = {"images", "audio_files", "videos", "related_locations", "narration_ids"}
_ALL_KEYS = [
    "name", "category", "latitude", "longitude", "county", "city", "community",
    "address", "description", "trigger_radius", "map_visibility_radius",
    "priority", "narration_ids", "images", "audio_files", "videos",
    "related_locations", "active", "featured", "hidden", "source", "source_id",
    "destination_code",
]


def normalize(row):
    """PostgREST bulk insert requires identical keys across all objects."""
    out = {}
    for k in _ALL_KEYS:
        if k in row:
            out[k] = row[k]
        elif k in _ARRAY_KEYS:
            out[k] = []
        elif k == "priority":
            out[k] = 0
        elif k in ("active",):
            out[k] = True
        elif k in ("featured", "hidden"):
            out[k] = False
        else:
            out[k] = None
    return out


def main():
    dry = "--apply" not in sys.argv
    rows = [normalize(r) for r in build_rows()]
    by_src = {}
    for r in rows:
        by_src[r["source"]] = by_src.get(r["source"], 0) + 1
    print(f"prepared {len(rows)} rows: {by_src}")
    if dry:
        print("DRY RUN (pass --apply to insert). Sample:")
        print(json.dumps(rows[:3], indent=2))
        return
    inserted = 0
    for i in range(0, len(rows), 200):
        chunk = rows[i:i + 200]
        status, _ = _req(
            "POST", "locations", chunk,
            extra={"Prefer": "return=minimal"},
        )
        inserted += len(chunk)
        print(f"  inserted batch {i}-{i + len(chunk)} (http {status})")
    print(f"done: {inserted} rows posted")


if __name__ == "__main__":
    main()
