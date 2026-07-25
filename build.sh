#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="Toolbox.app"
BIN="Toolbox"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Toolbox</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.rajeshsood.toolbox</string>
	<key>CFBundleName</key>
	<string>Toolbox</string>
	<key>CFBundleDisplayName</key>
	<string>Toolbox</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<false/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 Rajesh Sood</string>
</dict>
</plist>
PLIST

# --- App icon: build AppIcon.icns from logo.jpg (padded to a square canvas) ---
if [ -f logo.jpg ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  SQ="$(mktemp).png"
  # Pad to square (white background) so the icon isn't stretched, then fit to 1024.
  DIM=$(sips -g pixelHeight -g pixelWidth logo.jpg | awk '/pixel/{print $2}' | sort -rn | head -1)
  sips -s format png --padColor FFFFFF --padToHeightWidth "$DIM" "$DIM" logo.jpg --out "$SQ" >/dev/null
  for size in 16 32 128 256 512; do
    sips -z $size $size "$SQ" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size*2)) $((size*2)) "$SQ" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  echo "Icon:  AppIcon.icns generated from logo.jpg"
fi

SOURCES=$(find Sources -name '*.swift')

# SwiftUI @main requires -parse-as-library. Frameworks auto-link via `import`;
# if linking ever fails, append: -framework SwiftUI -framework PDFKit -framework Vision
swiftc -O -parse-as-library \
  -o "$APP/Contents/MacOS/$BIN" \
  $SOURCES

echo "Built $APP"

# --- Install to /Applications ---
DEST="/Applications/$APP"
if [ -d "$DEST" ]; then rm -rf "$DEST"; fi
if ditto "$APP" "$DEST" 2>/dev/null; then
  echo "Installed to $DEST"
  echo "Run:  open \"$DEST\""
else
  echo "WARN: could not write to /Applications (permissions?). Retrying with sudo…"
  sudo rm -rf "$DEST" && sudo ditto "$APP" "$DEST" && echo "Installed to $DEST (sudo)"
fi
