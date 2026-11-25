#!/usr/bin/env bash
# re-run after moving the folder
set -e
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

if [ "$(uname -s)" = Darwin ]; then
  APP="$HOME/Applications/Voice Transcriber.app"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  # Assets.car: layered icon for macOS 26+ (dark, tinted, clear); icon.icns: older macOS
  cp "$DIR/assets/Assets.car" "$DIR/assets/icon.icns" "$APP/Contents/Resources/"
  cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Voice Transcriber</string>
  <key>CFBundleDisplayName</key><string>Voice Transcriber</string>
  <key>CFBundleIdentifier</key><string>local.voice-transcriber</string>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
EOF
  cat > "$APP/Contents/MacOS/launcher" <<EOF
#!/bin/bash
export VT_APP_BUNDLE="\$(cd "\$(dirname "\$0")/../.." && pwd)"
exec "$DIR/launch.sh"
EOF
  chmod +x "$APP/Contents/MacOS/launcher"
  touch "$APP"  # make Finder pick up the new icon
  echo "Added $APP (find it with Spotlight or Launchpad, or drag it to the Dock)."

  if [ -d "$HOME/Desktop" ]; then
    ln -sfn "$APP" "$HOME/Desktop/Voice Transcriber"
    echo "Added to the desktop."
  fi
  exit 0
fi

ENTRY="[Desktop Entry]
Type=Application
Name=Voice Transcriber
Comment=Turn voice messages into English text, locally
Exec=\"$DIR/launch.sh\"
Icon=$DIR/assets/icon.svg
Terminal=false
Categories=AudioVideo;Utility;"

APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$APPS"
printf '%s\n' "$ENTRY" > "$APPS/voice-transcriber.desktop"
chmod +x "$APPS/voice-transcriber.desktop"
echo "Added to the app menu."

DESKTOP="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
if [ -d "$DESKTOP" ]; then
  printf '%s\n' "$ENTRY" > "$DESKTOP/Voice Transcriber.desktop"
  chmod +x "$DESKTOP/Voice Transcriber.desktop"
  echo "Added to the desktop."
fi
