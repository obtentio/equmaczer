#!/usr/bin/env bash
# equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
EXECUTABLE_NAME="equmaczer"
APP_NAME="equmaczer"
RELEASE_DIR="$ROOT_DIR/release"
APP_BUNDLE="$RELEASE_DIR/${APP_NAME}.app"
INFO_PLIST_SRC="$ROOT_DIR/src/app/Info.plist"
ENTITLEMENTS="$ROOT_DIR/resources/equmaczer.entitlements"
ICON_SVG="$ROOT_DIR/resources/AppIcon.svg"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
ICON_ICNS="$ROOT_DIR/.build/AppIcon.icns"
DRIVER_BUNDLE="$ROOT_DIR/driver/.build/equmaczer.driver"

if [[ ! -f "$ROOT_DIR/Package.swift" ]]; then
  echo "Error: bundle.sh must run from repo root containing Package.swift" >&2
  exit 1
fi

generate_icon() {
  if [[ ! -f "$ICON_SVG" ]]; then
    echo "Error: Icon SVG not found at $ICON_SVG" >&2
    exit 1
  fi

  if ! command -v rsvg-convert &>/dev/null; then
    echo "Error: rsvg-convert not found. Install with: brew install librsvg" >&2
    exit 1
  fi

  echo "Generating app icon..."
  mkdir -p "$(dirname "$ICONSET_DIR")"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  for size in 16 32 128 256 512; do
    rsvg-convert -w $size -h $size "$ICON_SVG" -o "$ICONSET_DIR/icon_${size}x${size}.png"
    rsvg-convert -w $((size * 2)) -h $((size * 2)) "$ICON_SVG" -o "$ICONSET_DIR/icon_${size}x${size}@2x.png"
  done

  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
  rm -rf "$ICONSET_DIR"

  echo "Icon generated: $ICON_ICNS"
}

build_driver() {
  if [[ ! -f "$ICON_ICNS" ]]; then
    echo "Error: Icon not found. Run: ./bundle.sh icon" >&2
    exit 1
  fi

  echo "Building virtual audio driver..."
  "$ROOT_DIR/driver/driver.sh" bundle --quiet
}

build_app() {
  if [[ ! -d "$DRIVER_BUNDLE" ]]; then
    echo "Error: Driver not found. Run: ./bundle.sh driver" >&2
    exit 1
  fi

  echo "Building Swift app..."
  if [[ "${EQ_SKIP_BUILD:-0}" != "1" ]]; then
    swift build -c release
  fi
  if [[ ! -x "$BUILD_DIR/$EXECUTABLE_NAME" ]]; then
    echo "Error: build the release executable before packaging" >&2
    exit 1
  fi

  echo "Creating app bundle at $APP_BUNDLE"
  rm -rf "$RELEASE_DIR"
  mkdir -p "$APP_BUNDLE/Contents/MacOS"
  mkdir -p "$APP_BUNDLE/Contents/Resources"

  cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
  cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"

  # Copy driver to app bundle
  cp -R "$DRIVER_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
  echo "Driver bundled with app"

  # Copy icon to app bundle
  if [[ -f "$ICON_ICNS" ]]; then
    cp "$ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "Icon copied to app bundle"
  fi

  # Copy the menu bar mark (template PNGs) to app bundle
  cp "$ROOT_DIR/resources/MenuBarIcon.png" "$APP_BUNDLE/Contents/Resources/"
  cp "$ROOT_DIR/resources/MenuBarIcon@2x.png" "$APP_BUNDLE/Contents/Resources/"
  echo "Menu bar icon copied to app bundle"

  # Copy the licence into the bundle: every conveyed copy carries it
  # (GPL-3.0 section 4) and the About pane's legal view reads it.
  cp "$ROOT_DIR/LICENSE" "$APP_BUNDLE/Contents/Resources/LICENSE.txt"
  echo "Licence copied to app bundle"

  # Ad-hoc signatures change every build, so macOS forgets the audio-capture permission
  # (the tap then records silence). A stable local identity keeps it; SIGN_ID overrides.
  local sign_id="${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
  codesign --force --sign "${sign_id:--}" --options runtime \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"

  echo "Bundle created: $APP_BUNDLE"
  echo "You can now copy it to /Applications to run equmaczer normally."
}

show_usage() {
  echo "Usage: $0 [command]"
  echo ""
  echo "Commands:"
  echo "  (none)  - Full build: generate icon, build driver, build app"
  echo "  icon    - Generate icon only"
  echo "  driver  - Build driver only (requires icon)"
  echo "  app     - Build app only (requires driver)"
}

case "${1:-}" in
  icon)
    generate_icon
    ;;
  driver)
    build_driver
    ;;
  app)
    build_app
    ;;
  "")
    generate_icon
    build_driver
    build_app
    ;;
  *)
    show_usage
    exit 1
    ;;
esac

