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

# 3. Build.
flutter pub get
flutter build web --release --target "$FLUTTER_TARGET"

# 4. Inject the Google Maps JS key into the built index.html.
if [ -n "${GOOGLE_MAPS_API_KEY:-}" ]; then
  sed -i "s/__GOOGLE_MAPS_API_KEY__/${GOOGLE_MAPS_API_KEY}/" build/web/index.html
fi

echo "Flutter web build complete -> build/web"
