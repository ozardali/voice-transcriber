#!/usr/bin/env bash
# re-run after moving the folder
set -e
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ENTRY="[Desktop Entry]
Type=Application
Name=Voice Transcriber
Comment=Turn voice messages into English text, locally
Exec=\"$DIR/launch.sh\"
Icon=audio-input-microphone
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
