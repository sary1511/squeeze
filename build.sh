#!/usr/bin/env bash
# Builds Squeeze.app and Squeeze.dmg into ./dist
# Needs: macOS 26 (Tahoe) + Xcode 26 (or its Command Line Tools).
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
APP_NAME="Squeeze"
BUNDLE_ID="com.vyeola.squeeze"
VERSION="1.0.0"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
VENDOR="$ROOT/vendor"

say() { printf "\n\033[1;34m▸ %s\033[0m\n" "$1"; }
warn() { printf "\033[1;33m! %s\033[0m\n" "$1"; }

# ---------------------------------------------------------------- checks
# Prefer full Xcode over the Command Line Tools when it's installed.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  for x in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    if [[ -d "$x/Contents/Developer" ]]; then export DEVELOPER_DIR="$x/Contents/Developer"; break; fi
  done
fi
echo "Toolchain: ${DEVELOPER_DIR:-$(xcode-select -p)}"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo 0)"
if [[ "${SDK_VERSION%%.*}" -lt 26 ]]; then
  echo "Squeeze uses Liquid Glass, which needs the macOS 26 SDK (Xcode 26). Found SDK: $SDK_VERSION"
  echo "Install Xcode 26 from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi

# ---------------------------------------------------------------- HandBrakeCLI
fetch_handbrake() {
  mkdir -p "$VENDOR"
  if [[ -x "$VENDOR/HandBrakeCLI" ]]; then
    echo "Using vendor/HandBrakeCLI"
    return 0
  fi

  say "Downloading the official HandBrakeCLI"
  local api url tmp mnt
  api="$(curl -fsSL https://api.github.com/repos/HandBrake/HandBrake/releases/latest || true)"
  url="$(printf '%s' "$api" | grep -Eo '"browser_download_url": *"[^"]*HandBrakeCLI-[^"]*\.dmg"' | head -1 | sed -E 's/.*"(https[^"]+)"/\1/')"
  if [[ -n "$url" ]]; then
    tmp="$(mktemp -d)"
    echo "$url"
    if curl -fL --progress-bar -o "$tmp/hb.dmg" "$url"; then
      mnt="$(hdiutil attach -nobrowse -readonly "$tmp/hb.dmg" | grep -Eo '/Volumes/.*$' | head -1)"
      if [[ -n "$mnt" && -f "$mnt/HandBrakeCLI" ]]; then
        cp "$mnt/HandBrakeCLI" "$VENDOR/HandBrakeCLI"
        chmod +x "$VENDOR/HandBrakeCLI"
      fi
      [[ -n "$mnt" ]] && hdiutil detach -quiet "$mnt" || true
    fi
    rm -rf "$tmp"
  fi
  [[ -x "$VENDOR/HandBrakeCLI" ]] && return 0

  if command -v HandBrakeCLI >/dev/null 2>&1; then
    warn "Download failed — using the Homebrew HandBrakeCLI at $(command -v HandBrakeCLI)"
    cp "$(command -v HandBrakeCLI)" "$VENDOR/HandBrakeCLI"
    return 0
  fi

  warn "Couldn't get HandBrakeCLI. The HandBrake engine will work only if you run: brew install handbrake"
  warn "(Or download HandBrakeCLI from https://handbrake.fr/downloads2.php and put it in ./vendor)"
  return 1
}
HAVE_HB=1
fetch_handbrake || HAVE_HB=0

# ---------------------------------------------------------------- FFmpeg
# Static macOS builds from https://ffmpeg.martin-riedl.de (signed, no Homebrew dylibs).
fetch_ffmpeg() {
  mkdir -p "$VENDOR"
  if [[ -x "$VENDOR/ffmpeg" ]]; then
    echo "Using vendor/ffmpeg"
    return 0
  fi

  local arch tmp url
  arch="$(uname -m)"; [[ "$arch" == "x86_64" ]] && arch="amd64"
  url="https://ffmpeg.martin-riedl.de/redirect/latest/macos/$arch/release/ffmpeg.zip"
  say "Downloading a static FFmpeg ($arch)"
  echo "$url"
  tmp="$(mktemp -d)"
  if curl -fL --progress-bar -o "$tmp/ffmpeg.zip" "$url" && unzip -q -o "$tmp/ffmpeg.zip" -d "$tmp/x"; then
    local bin
    bin="$(find "$tmp/x" -type f -name ffmpeg | head -1)"
    if [[ -n "$bin" ]]; then
      cp "$bin" "$VENDOR/ffmpeg"
      chmod +x "$VENDOR/ffmpeg"
    fi
  fi
  rm -rf "$tmp"

  if [[ -x "$VENDOR/ffmpeg" ]] && "$VENDOR/ffmpeg" -hide_banner -version >/dev/null 2>&1; then
    "$VENDOR/ffmpeg" -hide_banner -version | head -1
    if otool -L "$VENDOR/ffmpeg" | grep -q -e /opt/homebrew -e /usr/local/; then
      warn "This ffmpeg links to Homebrew libraries, so it will only run on Macs with those installed."
    fi
    return 0
  fi
  rm -f "$VENDOR/ffmpeg"

  warn "Couldn't download FFmpeg. If Homebrew's ffmpeg is installed (brew install ffmpeg) Squeeze will use it;"
  warn "otherwise download a static build from https://ffmpeg.martin-riedl.de and put 'ffmpeg' in ./vendor"
  return 1
}
HAVE_FF=1
fetch_ffmpeg || HAVE_FF=0

# ---------------------------------------------------------------- compile
say "Compiling Squeeze (release)"
swift build -c release --product "$APP_NAME"
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

say "Compiling the Finder extension"
EXT_NAME="SqueezeFinder"
EXT_BUILD="$ROOT/.build/finder-extension"
mkdir -p "$EXT_BUILD"
xcrun swiftc -O -parse-as-library \
  -module-name "$EXT_NAME" \
  -target "$(uname -m)-apple-macos26.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  Extension/FinderSync.swift Sources/Squeeze/SqueezeLink.swift \
  -framework Cocoa -framework FinderSync \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$EXT_BUILD/$EXT_NAME"

# ---------------------------------------------------------------- bundle
say "Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
[[ $HAVE_HB -eq 1 ]] && cp "$VENDOR/HandBrakeCLI" "$APP/Contents/Resources/HandBrakeCLI"
[[ $HAVE_FF -eq 1 ]] && cp "$VENDOR/ffmpeg" "$APP/Contents/Resources/ffmpeg"

# Finder extension bundle
APPEX="$APP/Contents/PlugIns/$EXT_NAME.appex"
mkdir -p "$APPEX/Contents/MacOS"
cp "$EXT_BUILD/$EXT_NAME" "$APPEX/Contents/MacOS/$EXT_NAME"
cat > "$APPEX/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$EXT_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID.finder</string>
  <key>CFBundleName</key><string>$EXT_NAME</string>
  <key>CFBundleDisplayName</key><string>Squeeze</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHumanReadableDescription</key><string>Compress and convert videos from Finder's right-click menu.</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionAttributes</key><dict/>
    <key>NSExtensionPointIdentifier</key><string>com.apple.FinderSync</string>
    <key>NSExtensionPrincipalClass</key><string>SqueezeFinderSync</string>
  </dict>
</dict>
</plist>
PLIST

# App icon from Resources/AppIcon.png (1024×1024)
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "Resources/AppIcon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "Resources/AppIcon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <!-- Starts without a Dock icon; Squeeze adds it when the window opens, so
       Finder actions can run silently in the background. -->
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
      <key>CFBundleURLSchemes</key><array><string>squeeze</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Ad-hoc signature (runs on this Mac; no Apple Developer account needed)
say "Signing (ad-hoc)"
for tool in HandBrakeCLI ffmpeg; do
  if [[ -f "$APP/Contents/Resources/$tool" ]]; then
    codesign --force --sign - "$APP/Contents/Resources/$tool"
  fi
done
# Finder extensions must be sandboxed (the app itself isn't).
EXT_ENTITLEMENTS="$EXT_BUILD/extension.entitlements"
cat > "$EXT_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - --entitlements "$EXT_ENTITLEMENTS" "$APPEX"
codesign --force --sign - "$APP"

# ---------------------------------------------------------------- dmg
say "Creating $APP_NAME.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DIST/$APP_NAME.dmg"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$APP_NAME.dmg"
rm -rf "$STAGE"

say "Done"
echo "App: $APP"
echo "DMG: $DIST/$APP_NAME.dmg"
echo "Finder extension: drag Squeeze to Applications and open it once. Then right-click any video → Squeeze."
[[ $HAVE_HB -eq 1 ]] || warn "Built without HandBrakeCLI — only the Apple engine will work until you install it."
[[ $HAVE_FF -eq 1 ]] || warn "Built without FFmpeg — AVI, WMV, FLV, TS, 3GP, OGV, WebP, MP3, WAV, FLAC and 'Keep original codecs' need it."
