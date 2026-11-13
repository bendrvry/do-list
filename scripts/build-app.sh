#!/bin/zsh
# Builds "Do List.app" (release) into build/, signs it ad hoc and zips it.
#
#   ./scripts/build-app.sh            # build/Do List.app + build/Do List.zip
#   ./scripts/build-app.sh --install  # also copy to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Do List"      # display name; also change AppInfo.name in Menus.swift
PRODUCT="Still"          # SwiftPM executable product
BUNDLE_ID="app.dolist.mac"
VERSION="1.0"
BUILD_NUMBER="1"
MIN_MACOS="14.0"

ROOT=$(pwd)
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"

# The Command Line Tools' newest SDK expects SwiftUI macro plugins that ship only
# with Xcode. Fall back to the newest SDK that builds without them.
if [[ -z "${SDKROOT:-}" ]] && [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
  for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk; do
    if [[ -d "$sdk" ]]; then export SDKROOT="$sdk"; break; fi
  done
fi

echo "→ Compiling (release)"
ARCHS=(--arch arm64)
if swift build -c release --arch arm64 --arch x86_64 --product "$PRODUCT" >/dev/null 2>&1; then
  ARCHS=(--arch arm64 --arch x86_64)
fi
swift build -c release "${ARCHS[@]}" --product "$PRODUCT"
BIN_DIR=$(swift build -c release "${ARCHS[@]}" --show-bin-path)

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$PRODUCT" "$APP/Contents/MacOS/$APP_NAME"
# Drop debug symbols: they embed absolute build paths from this machine.
strip -S -x "$APP/Contents/MacOS/$APP_NAME"

ICONSET="$BUILD/AppIcon.iconset"
if [[ ! -f "$BUILD/AppIcon.icns" || scripts/make-icon.swift -nt "$BUILD/AppIcon.icns" ]]; then
  echo "→ Rendering icon"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  SDKROOT= swift scripts/make-icon.swift "$BUILD/AppIcon-1024.png"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$BUILD/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"
fi
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>A quiet place for the things you need to do.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

echo "→ Signing (ad hoc)"
codesign --force --options runtime --timestamp=none --sign - "$APP"
codesign --verify --strict "$APP"

echo "→ Zipping"
rm -f "$BUILD/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$BUILD/$APP_NAME.zip"

if [[ "${1:-}" == "--install" ]]; then
  echo "→ Installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  ditto "$APP" "/Applications/$APP_NAME.app"
fi

echo "✓ $APP"
