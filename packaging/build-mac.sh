#!/usr/bin/env bash
# Build "Voice Transcriber.app" and a .dmg for Apple Silicon Macs.
#   packaging/build-mac.sh            uses python3.12 (or $PYTHON)
# Output: dist/Voice-Transcriber-<version>-mac-arm64.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Voice Transcriber"
VERSION="$(sed -n 's/^VERSION = "\(.*\)"/\1/p' packaging/voice-transcriber.spec)"
PYTHON="${PYTHON:-python3.12}"
VENV=.build/venv

[ "$(uname -m)" = arm64 ] || { echo "Build this on an Apple Silicon Mac."; exit 1; }

if [ ! -x "$VENV/bin/python" ]; then
  "$PYTHON" -m venv "$VENV"
fi
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q -r requirements.txt "pyinstaller>=6.10,<7"

rm -rf "dist/$NAME" "dist/$NAME.app"
"$VENV/bin/pyinstaller" --noconfirm --clean --log-level WARN \
  --workpath .build/pyinstaller --distpath dist packaging/voice-transcriber.spec

# ad-hoc signature, so macOS runs it on Apple Silicon (not a Developer ID)
codesign --force --deep --sign - "dist/$NAME.app"

# disk image: the app plus a shortcut to Applications to drag it onto
stage=.build/dmg
rm -rf "$stage" && mkdir -p "$stage"
cp -R "dist/$NAME.app" "$stage/"
ln -s /Applications "$stage/Applications"
dmg="dist/Voice-Transcriber-$VERSION-mac-arm64.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname "$NAME" -srcfolder "$stage" -fs HFS+ -format UDZO "$dmg"
rm -rf "$stage"
echo "Built $dmg ($(du -h "$dmg" | cut -f1))"
