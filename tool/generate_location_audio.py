#!/usr/bin/env python3
"""Generate narration audio for PENDING master locations and promote them to
READY.

For each active, visible, geocoded location in public.locations that has no
audio_files: write a short narration (OpenAI), synthesize it (ElevenLabs / DJ
Brittney), upload the MP3 to the voiceovers bucket, and set audio_files.

Resumable: re-running only processes locations still missing audio.

Usage:
  python3 tool/generate_location_audio.py            # dry run (counts only)
  python3 tool/generate_location_audio.py --limit 2  # first 2 (real)
  python3 tool/generate_location_audio.py --apply     # all pending
"""
import json
import os
import sys
import time
import urllib.request

BASE = os.environ["SUPABASE_URL"].rstrip("/")
SVC = os.environ["SUPABASE_SERVICE_KEY"]
OPENAI = os.environ["OPENAI_API_KEY"]
ELEVEN = os.environ["ELEVENLABS_API_KEY"]
VOICE = "kPzsL2i3teMYv0FxEYQ6"  # DJ Brittney
MODEL = "gpt-4o-mini"
BUCKET = "voiceovers"


def _do(req):
    with urllib.request.urlopen(req) as r:
        return r.status, r.read()


def sb(method, path, body=None, extra=None, raw=False):
    url = f"{BASE}/rest/v1/{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    for k, v in {"apikey": SVC, "Authorization": f"Bearer {SVC}",
                 "Content-Type": "application/json", **(extra or {})}.items():
        req.add_header(k, v)
    s, b = _do(req)
    return s, (b if raw else (json.loads(b) if b else None))


def pending_locations(county=None):
    out, step, off = [], 1000, 0
    cf = f"&county=eq.{county}" if county else ""
    while True:
        _, rows = sb("GET",
            "locations?select=id,name,category,county,city,description,"
            "audio_files,active,hidden,latitude,longitude"
            f"&active=eq.true&hidden=eq.false{cf}&limit={step}&offset={off}")
        rows = rows or []
        out.extend(rows)
        if len(rows) < step:
            break
        off += step
    def missing(l):
        af = l.get("audio_files") or []
        has = any((u or "").strip() for u in af)
        lat, lng = l.get("latitude"), l.get("longitude")
        return (not has) and lat is not None and lng is not None \
            and not (lat == 0 and lng == 0)
    return [l for l in out if missing(l)]


def narrate(loc):
    typ = (loc.get("category") or "point of interest").replace("_", " ")
    where = f" in {loc['county']} County" if loc.get("county") else ""
    desc = (loc.get("description") or "").strip()
    prompt = (
        f"Write a warm, factual 45-70 word spoken radio narration introducing "
        f"{loc['name']}, a {typ}{where}, Florida. "
        f"{('Context: ' + desc) if desc else ''} "
        "Keep it evocative and accurate; do NOT invent specific numbers, dates, "
        "or claims. Output only the narration text, no title or quotes.")
    body = {"model": MODEL, "temperature": 0.8,
            "messages": [
                {"role": "system", "content": "You are a professional Florida "
                 "travel radio narrator."},
                {"role": "user", "content": prompt}]}
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(body).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {OPENAI}")
    req.add_header("Content-Type", "application/json")
    _, b = _do(req)
    return json.loads(b)["choices"][0]["message"]["content"].strip()


def tts(text):
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE}"
        "?output_format=mp3_44100_128",
        data=json.dumps({"text": text,
                         "model_id": "eleven_multilingual_v2"}).encode(),
        method="POST")
    req.add_header("xi-api-key", ELEVEN)
    req.add_header("Content-Type", "application/json")
    _, b = _do(req)
    return b


def upload(loc_id, mp3):
    path = f"locations/{loc_id}.mp3"
    req = urllib.request.Request(
        f"{BASE}/storage/v1/object/{BUCKET}/{path}", data=mp3, method="POST")
    for k, v in {"apikey": SVC, "Authorization": f"Bearer {SVC}",
                 "x-upsert": "true",
                 "Content-Type": "audio/mpeg"}.items():
        req.add_header(k, v)
    _do(req)
    return f"{BASE}/storage/v1/object/public/{BUCKET}/{path}"


def main():
    apply = "--apply" in sys.argv or "--limit" in sys.argv
    limit = None
    if "--limit" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--limit") + 1])
    county = None
    if "--county" in sys.argv:
        county = sys.argv[sys.argv.index("--county") + 1]
    pend = pending_locations(county=county)
    print(f"{len(pend)} pending locations need audio"
          f"{f' in {county} County' if county else ''}")
    if not apply:
        for l in pend[:8]:
            print(f"  - {l['name']} ({l.get('category')})")
        print("DRY RUN — pass --apply (or --limit N) to generate.")
        return
    todo = pend[: (limit or len(pend))]
    print(f"generating for {len(todo)} …")
    ok = fail = 0
    for i, loc in enumerate(todo, 1):
        try:
            text = narrate(loc)
            mp3 = tts(text)
            url = upload(loc["id"], mp3)
            sb("PATCH", f"locations?id=eq.{loc['id']}",
               {"audio_files": [url]}, extra={"Prefer": "return=minimal"})
            ok += 1
            print(f"  [{i}/{len(todo)}] OK  {loc['name']}  ({len(mp3)//1024} KB)")
        except Exception as e:  # noqa: BLE001
            fail += 1
            print(f"  [{i}/{len(todo)}] FAIL {loc['name']}: {e}")
        time.sleep(0.3)
    print(f"=== done: {ok} generated, {fail} failed ===")


if __name__ == "__main__":
    main()
