#!/usr/bin/env bash
set -euo pipefail

BUNDLE_DIR="${1:-build/linux/x64/release/bundle}"
VERSION="${2:-1.0.0}"
OUTPUT_DIR="${3:-dist}"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "Error: bundle directory $BUNDLE_DIR does not exist" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

APPDIR=$(mktemp -d /tmp/chesssrs_appdir_XXXXXX)
trap 'rm -rf "$APPDIR"' EXIT

mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/512x512/apps"
mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"

cp -r "$BUNDLE_DIR"/* "$APPDIR/usr/bin/"
if [ -d "$BUNDLE_DIR/lib" ]; then
  cp -r "$BUNDLE_DIR/lib"/* "$APPDIR/usr/lib/" 2>/dev/null || true
fi

cp packaging/linux/AppRun "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"

cp packaging/linux/org.chesssrs.ChessSRS.desktop "$APPDIR/chess_srs.desktop"
cp packaging/linux/org.chesssrs.ChessSRS.desktop "$APPDIR/usr/share/applications/chess_srs.desktop"
cp assets/brand/icon-1024.png "$APPDIR/chess_srs.png"
cp assets/brand/icon-1024.png "$APPDIR/usr/share/icons/hicolor/512x512/apps/chess_srs.png"
cp assets/brand/icon.svg "$APPDIR/usr/share/icons/hicolor/scalable/apps/chess_srs.svg"

# Fetch appimagetool if not available in PATH
if ! command -v appimagetool >/dev/null 2>&1; then
  if [ ! -f /tmp/appimagetool ]; then
    echo "Downloading appimagetool..."
    curl -fsSL https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage -o /tmp/appimagetool
    chmod +x /tmp/appimagetool
  fi
  APPIMAGETOOL="/tmp/appimagetool"
else
  APPIMAGETOOL="appimagetool"
fi

# In container or CI environments, extract appimagetool if FUSE is not available
if ! "$APPIMAGETOOL" --version >/dev/null 2>&1; then
  echo "FUSE not available, extracting appimagetool..."
  cd /tmp
  "$APPIMAGETOOL" --appimage-extract >/dev/null 2>&1
  APPIMAGETOOL="/tmp/squashfs-root/AppRun"
  cd - >/dev/null
fi

ARCH=x86_64 "$APPIMAGETOOL" --no-appstream "$APPDIR" "$OUTPUT_DIR/chesssrs-${VERSION}-x86_64.AppImage"
echo "AppImage created: $OUTPUT_DIR/chesssrs-${VERSION}-x86_64.AppImage"
