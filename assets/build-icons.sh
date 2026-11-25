#!/usr/bin/env bash
# Rebuilds the compiled icon files in assets/. Needs macOS with Xcode installed.
# Only run this after changing the design: the outputs are committed, so
# install-shortcut.sh works without Xcode.
#
#   AppIcon.icon/  layered icon (edit in Icon Composer)  -> Assets.car  (macOS 26+)
#   icon.svg       flat icon, used as is on Linux         -> icon.icns   (older macOS)
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

qlmanage -t -s 1024 -o "$TMP" icon.svg >/dev/null
mkdir "$TMP/icon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.svg.png" --out "$TMP/icon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$TMP/icon.svg.png" --out "$TMP/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/icon.iconset" -o icon.icns

xcrun actool "$PWD/AppIcon.icon" --compile "$TMP" --platform macosx \
  --minimum-deployment-target 11.0 --app-icon AppIcon \
  --output-partial-info-plist "$TMP/partial.plist" >/dev/null
cp "$TMP/Assets.car" Assets.car
echo "Built icon.icns and Assets.car"
