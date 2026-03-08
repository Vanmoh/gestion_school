#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/frontend/gestion_school_app"
DOWNLOADS_DIR="$ROOT_DIR/downloads_site"
APK_PUBLISHED_NAME="Gestion School.apk"

APK_SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
LINUX_SRC="$APP_DIR/build/linux/x64/release/bundle"
LINUX_ARCHIVE="$DOWNLOADS_DIR/gestion_school_desktop_linux.tar.gz"
WINDOWS_SRC="$APP_DIR/build/windows/x64/runner/Release"
WINDOWS_ARCHIVE="$DOWNLOADS_DIR/gestion_school_desktop_windows.zip"
APK_DST="$DOWNLOADS_DIR/$APK_PUBLISHED_NAME"

if [[ ! -f "$APK_SRC" ]]; then
  echo "APK introuvable: $APK_SRC"
  echo "Build d'abord: flutter build apk --release --dart-define=API_BASE_URL=https://<api>/api"
  exit 1
fi

mkdir -p "$DOWNLOADS_DIR"
cp "$APK_SRC" "$APK_DST"

if [[ -d "$LINUX_SRC" ]]; then
  tar -czf "$LINUX_ARCHIVE" -C "$LINUX_SRC" .
  echo "Linux desktop archive générée: $LINUX_ARCHIVE"
else
  echo "Linux desktop non trouvé (ignoré): $LINUX_SRC"
fi

if [[ -d "$WINDOWS_SRC" ]]; then
  if command -v zip >/dev/null 2>&1; then
    (
      cd "$WINDOWS_SRC"
      rm -f "$WINDOWS_ARCHIVE"
      zip -r "$WINDOWS_ARCHIVE" . >/dev/null
    )
    echo "Windows desktop archive générée: $WINDOWS_ARCHIVE"
  else
    echo "Commande 'zip' introuvable, impossible de générer $WINDOWS_ARCHIVE"
  fi
else
  echo "Windows desktop non trouvé (ignoré): $WINDOWS_SRC"
fi

echo "Artifacts publiés dans: $DOWNLOADS_DIR"
ls -lh "$APK_DST" "$DOWNLOADS_DIR"/gestion_school_desktop_*.{tar.gz,zip} 2>/dev/null || ls -lh "$APK_DST"
