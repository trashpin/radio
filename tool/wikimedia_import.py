#!/usr/bin/env python3
"""Wikimedia Commons hero-image importer for ExplorerOS destinations.

For each location (public.locations) missing a hero image, searches Wikimedia
Commons, filters (name match, >=1200px, real photos only — no logos/maps/icons/
flags/drawings/PDF/SVG), downloads the best image (<=10MB, jpg/png/webp),
uploads it to the `media` bucket under destination-images/, links it as the
location's hero, and records full attribution (author/license/source) in
media_assets. Retries downloads up to 3x. Never overwrites an existing hero
unless --replace is passed.

Usage:
  python3 tool/wikimedia_import.py                 # dry run (search only)
  python3 tool/wikimedia_import.py --limit 5 --apply
  python3 tool/wikimedia_import.py --county Marion --apply
  python3 tool/wikimedia_import.py --apply --replace
"""
import io
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
FOLDER = "destination-images"
COMMONS = "https://commons.wikimedia.org/w/api.php"
UA = "ExplorerOS-ImageImporter/1.0 (https://exploreros.app; admin@exploreros.app)"
MAX_BYTES = 10 * 1024 * 1024
MIN_WIDTH = 1200
ACCEPT_MIME = {"image/jpeg", "image/png", "image/webp"}
# Titles containing these are not real destination photos.
BAD_WORDS = re.compile(
    r"logo|icon|\bmap\b|flag|coat of arms|\bseal\b|drawing|diagram|chart|"
    r"\bplan\b|locator|\.svg|\.pdf|signature|blazon|emblem|schematic",
    re.I,
)
GENERIC = {
    "state", "park", "county", "florida", "fl", "recreation", "area",
    "national", "forest", "lake", "river", "spring", "springs", "historic",
    "historical", "landmark", "site", "the", "of", "and", "trail", "trailhead",
    "museum", "city", "town", "community", "boat", "ramp", "scenic", "road",
    "campground", "attraction", "center", "point", "interest",
}


def _get(url, headers=None, timeout=45):
    req = urllib.request.Request(url, headers=headers or {})
    req.add_header("User-Agent", UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read()


def sb(method, path, body=None, extra=None, raw=False):
    url = f"{BASE}/rest/v1/{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    for k, v in {"apikey": SVC, "Authorization": f"Bearer {SVC}",
                 "Content-Type": "application/json", **(extra or {})}.items():
        req.add_header(k, v)
    with urllib.request.urlopen(req) as r:
        b = r.read()
        return r.status, (b if raw else (json.loads(b) if b else None))


def get_locations(county=None):
    out, step, off = [], 1000, 0
    cf = f"&county=eq.{urllib.parse.quote(county)}" if county else ""
    while True:
        _, rows = sb("GET",
            f"locations?select=id,name,category,city,county,images,active"
            f"{cf}&limit={step}&offset={off}")
        rows = rows or []
        out.extend(rows)
        if len(rows) < step:
            return out
        off += step


def strip_html(s):
    return re.sub(r"<[^>]+>", "", s or "").strip()


def distinctive_tokens(name):
    toks = re.findall(r"[a-z0-9]+", name.lower())
    return [t for t in toks if t not in GENERIC and len(t) > 2]


def search_commons(query):
    params = {
        "action": "query", "format": "json", "generator": "search",
        "gsrsearch": f"{query} filetype:bitmap", "gsrnamespace": "6",
        "gsrlimit": "20", "prop": "imageinfo",
        "iiprop": "url|size|mime|extmetadata|dimensions", "iiurlwidth": "1600",
        "iiextmetadatafilter": "Artist|LicenseShortName|LicenseUrl|Credit|Attribution",
    }
    url = COMMONS + "?" + urllib.parse.urlencode(params)
    _, body = _get(url)
    data = json.loads(body)
    pages = (data.get("query") or {}).get("pages") or {}
    return list(pages.values())


def pick_image(pages, name, county=None):
    # All name words (>2 chars), keeping "springs"/"park" etc. so multi-word
    # park names still match strongly.
    tokens = [t for t in re.findall(r"[a-z0-9]+", name.lower()) if len(t) > 2]
    ntokens = len(tokens)
    best = None
    best_score = -1
    for p in pages:
        title = p.get("title", "")
        info = (p.get("imageinfo") or [None])[0]
        if not info:
            continue
        if BAD_WORDS.search(title):
            continue
        mime = info.get("mime", "")
        if mime not in ACCEPT_MIME:
            continue
        w, h = info.get("width", 0), info.get("height", 0)
        if w < MIN_WIDTH:
            continue
        lt = title.lower()
        matches = sum(1 for t in tokens if t in lt)
        geo_ok = "florida" in lt or (county and county.lower() in lt)
        # Accept only confident matches: a strong name overlap, or a decent
        # overlap backed by a Florida/county hint (rejects same-named people
        # and out-of-state places like Fort McCoy, WI).
        strong = matches >= 3 or matches >= max(2, ntokens)
        accept = strong or (geo_ok and matches >= min(2, ntokens))
        if not accept:
            continue
        score = matches * 100 + (300 if geo_ok else 0)
        if w >= h:
            score += 500  # landscape preferred
        score += min(w, 6000) // 100  # higher resolution better (capped)
        if score > best_score:
            best_score = score
            best = (p, info)
    return best


def download(url, tries=3):
    for i in range(tries):
        try:
            _, b = _get(url)
            return b
        except Exception:  # noqa: BLE001
            time.sleep(1.0 * (i + 1))
    return None


def slugify(name):
    s = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return s or "destination"


def thumb_at(thumburl, width):
    # Commons thumb URLs look like .../thumb/a/ab/File.jpg/1600px-File.jpg
    return re.sub(r"/\d+px-", f"/{width}px-", thumburl or "")


def upload(path, data, content_type):
    req = urllib.request.Request(
        f"{BASE}/storage/v1/object/{BUCKET}/{path}", data=data, method="POST")
    for k, v in {"apikey": SVC, "Authorization": f"Bearer {SVC}",
                 "x-upsert": "true", "Content-Type": content_type}.items():
        req.add_header(k, v)
    with urllib.request.urlopen(req) as r:
        r.read()
    return f"{BASE}/storage/v1/object/public/{BUCKET}/{path}"


def has_hero(loc):
    return any((u or "").strip() for u in (loc.get("images") or []))


def main():
    apply = "--apply" in sys.argv
    replace = "--replace" in sys.argv
    county = None
    limit = None
    if "--county" in sys.argv:
        county = sys.argv[sys.argv.index("--county") + 1]
    if "--limit" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--limit") + 1])

    locs = get_locations(county=county)
    todo = [l for l in locs if replace or not has_hero(l)]
    if limit:
        todo = todo[:limit]
    print(f"{len(locs)} locations, {len(todo)} need a hero image"
          f"{f' in {county} County' if county else ''}"
          f"{' (dry run)' if not apply else ''}")

    imported = exists = notfound = failed = 0
    missing = []
    for i, loc in enumerate(todo, 1):
        name = (loc.get("name") or "").strip()
        parts = [name, loc.get("county") and f"{loc['county']} County",
                 loc.get("city"), "Florida"]
        query = " ".join(p for p in parts if p)
        try:
            pages = search_commons(query)
            picked = pick_image(pages, name, county=loc.get("county"))
        except Exception as e:  # noqa: BLE001
            print(f"  [{i}/{len(todo)}] ERR   {name}: search failed: {e}")
            failed += 1
            continue
        if not picked:
            print(f"  [{i}/{len(todo)}] MISS  {name}")
            notfound += 1
            missing.append(name)
            continue

        page, info = picked
        author = strip_html((info.get("extmetadata", {})
                             .get("Artist", {}) or {}).get("value")) or "Unknown"
        lic = strip_html((info.get("extmetadata", {})
                          .get("LicenseShortName", {}) or {}).get("value")) \
            or "See Wikimedia Commons"
        orig_url = info.get("url")
        thumburl = info.get("thumburl") or orig_url
        size = info.get("size", 0)
        mime = info.get("mime", "image/jpeg")
        ext = {"image/jpeg": "jpg", "image/png": "png",
               "image/webp": "webp"}.get(mime, "jpg")

        if not apply:
            print(f"  [{i}/{len(todo)}] OK*   {name}  <- {page.get('title')}"
                  f"  ({info.get('width')}x{info.get('height')}, {lic})")
            imported += 1
            continue

        # Download original if reasonable, else the 1600px thumb.
        src = orig_url if (size and size <= MAX_BYTES) else thumburl
        data = download(src)
        if data is None or len(data) > MAX_BYTES:
            data = download(thumburl)
        if data is None:
            print(f"  [{i}/{len(todo)}] FAIL  {name}: download failed")
            failed += 1
            continue

        slug = slugify(name)
        try:
            hero_url = upload(f"{FOLDER}/{slug}.{ext}", data, mime)
        except Exception as e:  # noqa: BLE001
            print(f"  [{i}/{len(todo)}] FAIL  {name}: upload failed: {e}")
            failed += 1
            continue

        # Link hero on the location (hero first, keep any gallery).
        imgs = [u for u in (loc.get("images") or []) if (u or "").strip()]
        imgs = [hero_url] + [u for u in imgs if u != hero_url]
        sb("PATCH", f"locations?id=eq.{loc['id']}", {"images": imgs},
           extra={"Prefer": "return=minimal"})

        # Record attribution in media_assets.
        sb("POST", "media_assets", {
            "record_type": "location",
            "record_id": loc["id"],
            "media_type": "image",
            "is_hero": True,
            "title": name,
            "public_url": hero_url,
            "thumbnail": thumb_at(thumburl, 400),
            "photographer": author,
            "license": lic,
            "copyright": "Wikimedia Commons",
            "caption": orig_url,
            "width": info.get("width"),
            "height": info.get("height"),
            "file_size": len(data),
            "tags": ["wikimedia", "hero"],
        }, extra={"Prefer": "return=minimal"})

        print(f"  [{i}/{len(todo)}] OK    {name}  ({len(data)//1024} KB, {lic})")
        imported += 1
        time.sleep(0.3)

    print("\n=== Wikimedia import complete ===")
    print(f"Imported: {imported}   Already had hero: {exists}   "
          f"Not found: {notfound}   Failed: {failed}")
    if missing:
        print("Missing images:", ", ".join(missing[:40]))


if __name__ == "__main__":
    main()
