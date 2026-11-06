#!/bin/bash
# Builds Glimpse.app and a drag-to-Applications DMG installer.
#
#   ./build.sh            universal build (Apple Silicon + Intel)
#   ./build.sh --native   build only for this Mac's CPU (faster)
#   ./build.sh --run      build, then launch the app
#
# Needs the Xcode Command Line Tools (xcode-select --install) or Xcode.

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Glimpse"
EXECUTABLE="Glimpse"
VERSION="$(cat VERSION 2>/dev/null || echo 1.0.0)"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

NATIVE=0
RUN=0
for arg in "$@"; do
  case "$arg" in
    --native) NATIVE=1 ;;
    --run) RUN=1 ;;
  esac
done

if ! command -v swift >/dev/null 2>&1; then
  echo "✗ Swift toolchain not found."
  echo "  Install the Xcode Command Line Tools:  xcode-select --install"
  exit 1
fi
if ! xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
  echo "✗ macOS SDK not found. Run:  xcode-select --install"
  exit 1
fi
echo "▶ Swift: $(swift --version 2>&1 | head -n 1)"

# ---------------------------------------------------------------- compile
# Each architecture is built separately with --triple (works with the Command
# Line Tools alone; "--arch a --arch b" needs full Xcode) and merged with lipo.
mkdir -p .build
BINARY=".build/$EXECUTABLE-universal"
rm -f "$BINARY"

build_arch() {
  local triple="$1" dir scratch
  scratch=".build/$triple"
  echo "▶ Compiling release for $triple …" >&2
  if ! swift build -c release --triple "$triple" --scratch-path "$scratch" 1>&2; then
    return 1
  fi
  dir="$(swift build -c release --triple "$triple" --scratch-path "$scratch" --show-bin-path)"
  [[ -x "$dir/$EXECUTABLE" ]] || return 1
  echo "$dir/$EXECUTABLE"
}

if [[ $NATIVE -eq 1 ]]; then
  echo "▶ Compiling release (this Mac only) …"
  swift build -c release
  cp "$(swift build -c release --show-bin-path)/$EXECUTABLE" "$BINARY"
else
  NATIVE_TRIPLE="$(uname -m)-apple-macosx14.0"
  OTHER_TRIPLE="x86_64-apple-macosx14.0"
  [[ "$(uname -m)" == "x86_64" ]] && OTHER_TRIPLE="arm64-apple-macosx14.0"

  if ! MAIN_BIN="$(build_arch "$NATIVE_TRIPLE")"; then
    echo
    echo "✗ Compile failed for $NATIVE_TRIPLE – see the errors above."
    exit 1
  fi
  if OTHER_BIN="$(build_arch "$OTHER_TRIPLE")"; then
    lipo -create "$MAIN_BIN" "$OTHER_BIN" -output "$BINARY"
  else
    echo "⚠ $OTHER_TRIPLE slice failed – shipping $(uname -m) only."
    cp "$MAIN_BIN" "$BINARY"
  fi
fi
[[ -x "$BINARY" ]] || { echo "✗ Binary not found at $BINARY"; exit 1; }

# ---------------------------------------------------------------- bundle
echo "▶ Assembling $APP …"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD_NUMBER/g" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Icon: square artwork → masked to the macOS icon shape → .iconset → .icns
echo "▶ Building icon …"
MASKED=".build/AppIcon-1024.png"
swift Scripts/MakeIcon.swift Resources/AppIcon-source.png "$MASKED" >/dev/null
ICONSET="$DIST/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$size" "$size" "$MASKED" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$double" "$double" "$MASKED" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Ad-hoc signature (required on Apple Silicon; no developer account needed).
codesign --force --deep --options runtime --sign - "$APP"
echo "▶ Architectures: $(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE")"

# ---------------------------------------------------------------- dmg
echo "▶ Creating DMG …"
STAGING="$DIST/dmg-staging"
RW_DMG="$DIST/$APP_NAME-rw.dmg"
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
# Retina-aware background: 1x + 2x combined into one TIFF.
tiffutil -cathidpicheck Resources/dmg-background.png Resources/dmg-background@2x.png \
  -out "$STAGING/.background/background.tiff" 2>/dev/null \
  || cp Resources/dmg-background.png "$STAGING/.background/background.tiff"
cp "$MASKED" "$STAGING/.VolumeIcon.png" 2>/dev/null || true

# A previously opened Glimpse DMG would make the new one mount as "Glimpse 1".
if [[ -d "/Volumes/$APP_NAME" ]]; then
  hdiutil detach "/Volumes/$APP_NAME" -quiet || hdiutil detach "/Volumes/$APP_NAME" -force -quiet || true
fi
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDRW -fs HFS+ "$RW_DMG" >/dev/null
MOUNT_DIR="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | grep -E '/Volumes/' | sed 's/.*\(\/Volumes\/.*\)/\1/')"

# Volume icon
if [[ -f "$STAGING/.VolumeIcon.png" ]]; then
  sips -s format icns "$MOUNT_DIR/.VolumeIcon.png" --out "$MOUNT_DIR/.VolumeIcon.icns" >/dev/null 2>&1 \
    && SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null \
    && SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
  rm -f "$MOUNT_DIR/.VolumeIcon.png"
fi

# Finder layout: icon view, fixed window, background, icon positions.
# (Needs a logged-in Finder; on a headless machine the DMG still works, just unstyled.)
if ! osascript <<EOF >/dev/null
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 860, 540}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {160, 185}
    set position of item "Applications" of container window to {500, 185}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
then
  echo "⚠ Finder layout could not be applied (no GUI session?) – DMG will use the default view."
fi
sync
hdiutil detach "$MOUNT_DIR" -quiet || { sleep 2; hdiutil detach "$MOUNT_DIR" -force -quiet; }
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW_DMG"
rm -rf "$STAGING"

echo
echo "✅ App:  $APP"
echo "✅ DMG:  $DMG"
echo "   Open the DMG and drag ${APP_NAME} into Applications."

if [[ $RUN -eq 1 ]]; then
  open "$APP"
else
  open "$DIST"
fi
