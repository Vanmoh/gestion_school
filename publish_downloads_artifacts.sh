#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/frontend/gestion_school_app"
DOWNLOADS_DIR="$ROOT_DIR/downloads_site"

APK_SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
DESKTOP_SRC="$APP_DIR/build/linux/x64/release/bundle"
DESKTOP_ARCHIVE="$DOWNLOADS_DIR/gestion_school_desktop_linux.tar.gz"

if [[ ! -f "$APK_SRC" ]]; then
  echo "APK introuvable: $APK_SRC"
  echo "Build d'abord: flutter build apk --release --dart-define=API_BASE_URL=https://<api>/api"
  exit 1
fi

if [[ ! -d "$DESKTOP_SRC" ]]; then
  echo "Bundle desktop introuvable: $DESKTOP_SRC"
  echo "Build d'abord: flutter build linux --release --dart-define=API_BASE_URL=https://<api>/api"
  exit 1
fi

mkdir -p "$DOWNLOADS_DIR"
cp "$APK_SRC" "$DOWNLOADS_DIR/app-release.apk"

tar -czf "$DESKTOP_ARCHIVE" -C "$DESKTOP_SRC" .

echo "Artifacts publiés dans: $DOWNLOADS_DIR"
ls -lh "$DOWNLOADS_DIR/app-release.apk" "$DESKTOP_ARCHIVE"
