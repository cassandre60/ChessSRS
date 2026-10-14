#!/usr/bin/env bash
set -euo pipefail

BUNDLE_DIR="${1:-build/linux/x64/release/bundle}"
VERSION="${2:-1.0.0}"
OUTPUT_DIR="${3:-dist}"

CLEAN_VERSION="${VERSION#v}"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "Error: bundle directory $BUNDLE_DIR does not exist" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

PKG_DIR=$(mktemp -d /tmp/chesssrs_deb_XXXXXX)
trap 'rm -rf "$PKG_DIR"' EXIT

mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/opt/chesssrs"
mkdir -p "$PKG_DIR/usr/bin"
mkdir -p "$PKG_DIR/usr/share/applications"
mkdir -p "$PKG_DIR/usr/share/icons/hicolor/512x512/apps"
mkdir -p "$PKG_DIR/usr/share/icons/hicolor/scalable/apps"

cp -r "$BUNDLE_DIR"/* "$PKG_DIR/opt/chesssrs/"

cat > "$PKG_DIR/usr/bin/chess_srs" << 'EOF'
#!/bin/sh
exec /opt/chesssrs/chess_srs "$@"
EOF
chmod +x "$PKG_DIR/usr/bin/chess_srs"

cp packaging/linux/org.chesssrs.ChessSRS.desktop "$PKG_DIR/usr/share/applications/chess_srs.desktop"
cp assets/brand/icon-1024.png "$PKG_DIR/usr/share/icons/hicolor/512x512/apps/chess_srs.png"
cp assets/brand/icon.svg "$PKG_DIR/usr/share/icons/hicolor/scalable/apps/chess_srs.svg"

cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: chesssrs
Version: ${CLEAN_VERSION}
Section: games
Priority: optional
Architecture: amd64
Depends: libc6, libgtk-3-0, libglib2.0-0, libsecret-1-0
Maintainer: ChessSRS Contributors <https://github.com/cassandre60/ChessSRS>
Description: Local-first chess repertoire and spaced-repetition trainer
 ChessSRS is a local-first chess opening repertoire manager and spaced-repetition
 review trainer. Offline-first, fast, and private.
EOF

dpkg-deb --build --root-owner-group "$PKG_DIR" "$OUTPUT_DIR/chesssrs_${CLEAN_VERSION}_amd64.deb"
echo "Debian package created: $OUTPUT_DIR/chesssrs_${CLEAN_VERSION}_amd64.deb"
