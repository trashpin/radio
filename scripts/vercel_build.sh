#!/usr/bin/env bash
# Vercel build for the ExplorerOS Flutter web app.
#
# Vercel has no native Flutter runtime, so we fetch the Flutter SDK, build the
# web bundle, and emit it to build/web (set as the Output Directory).
#
# Required Vercel env vars (Project Settings -> Environment Variables):
#   SUPABASE_URL              e.g. https://qqeyvhcgirmfokoftiuz.supabase.co
#   SUPABASE_PUBLISHABLE_KEY  the sb_publishable_ (anon) key — safe for browsers
#   GOOGLE_MAPS_API_KEY       Maps JavaScript API key (restrict by referrer to
#                             your *.vercel.app domain)
# Optional:
#   FLUTTER_TARGET            entrypoint to build (default lib/main.dart).
#                             Use lib/main_admin.dart for the Admin app.
#   FLUTTER_VERSION           Flutter channel/tag (default: stable)
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"
FLUTTER_TARGET="${FLUTTER_TARGET:-lib/main.dart}"

# Client-side defaults so the deploy works even if Vercel env vars are unset,
# empty, or mistyped. These are public by design (the anon/publishable key is
# RLS-protected; the Maps JS key is a client key — restrict it by HTTP
# referrer). A valid-looking Vercel env var still overrides these.
if [[ "${SUPABASE_URL:-}" != https://* ]]; then
  SUPABASE_URL="https://qqeyvhcgirmfokoftiuz.supabase.co"
fi
if [[ "${SUPABASE_PUBLISHABLE_KEY:-}" != sb_publishable_* ]]; then
  SUPABASE_PUBLISHABLE_KEY="sb_publishable_Wy5BuUdp4uQBFKPgy2ksBA_-dPjdJ-o"
fi
: "${GOOGLE_MAPS_API_KEY:=AIzaSyA_cvKWWUAcZ-g_G1_B4CaMHzy3BUiI0tg}"

# 1. Fetch Flutter (cached between builds when Vercel preserves the workdir).
if [ ! -x "flutter/bin/flutter" ]; then
  git clone --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git
fi
export PATH="$PWD/flutter/bin:$PATH"
flutter --version
flutter config --enable-web

# 2. Recreate the bundled .env asset from Vercel env vars (real .env is gitignored).
printf 'SUPABASE_URL=%s\nSUPABASE_PUBLISHABLE_KEY=%s\n' \
  "${SUPABASE_URL:-}" "${SUPABASE_PUBLISHABLE_KEY:-}" > .env

# 3. Build BOTH apps into one output: traveler app at /, Admin at /admin/.
flutter pub get

SITE="$(mktemp -d)"

# Traveler app (root).
flutter build web --release --target "$FLUTTER_TARGET" --base-href /
cp -r build/web/. "$SITE/"

# Admin app (served under /admin/).
flutter build web --release --target lib/main_admin.dart --base-href /admin/
mkdir -p "$SITE/admin"
cp -r build/web/. "$SITE/admin/"

# Reassemble the combined site into build/web (the Output Directory).
rm -rf build/web
mkdir -p build/web
cp -r "$SITE/." build/web/

# 4. Inject the Google Maps JS key into both index.html files.
if [ -n "${GOOGLE_MAPS_API_KEY:-}" ]; then
  for f in build/web/index.html build/web/admin/index.html; do
    [ -f "$f" ] && sed -i "s/__GOOGLE_MAPS_API_KEY__/${GOOGLE_MAPS_API_KEY}/" "$f"
  done
fi

# 5. Service-worker KILL SWITCH. Flutter's service worker aggressively caches the
# app shell, so returning users kept seeing stale builds (e.g. an admin page
# missing newly-shipped buttons). Replace it with a self-unregistering worker:
# when a browser (even one with a stuck old SW) fetches the new
# flutter_service_worker.js — which is served no-cache — it installs this,
# clears ALL caches, and unregisters itself. No fetch handler = nothing is ever
# served stale; every load comes from the network (hashed assets stay cacheable
# via HTTP). It does NOT force-navigate, so there is no reload loop.
KILL_SW='self.addEventListener("install",function(){self.skipWaiting();});self.addEventListener("activate",function(e){e.waitUntil((async function(){try{var k=await caches.keys();await Promise.all(k.map(function(c){return caches.delete(c);}));}catch(_){}try{await self.registration.unregister();}catch(_){}})());});'
for f in build/web/flutter_service_worker.js build/web/admin/flutter_service_worker.js; do
  [ -f "$f" ] && printf '%s' "$KILL_SW" > "$f"
done

echo "Build complete -> build/web (app at /, admin at /admin/)"
