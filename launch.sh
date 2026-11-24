#!/usr/bin/env bash
# desktop entry target: run in background, or just open the page if already up
cd "$(dirname "$(readlink -f "$0")")"
URL="http://127.0.0.1:${PORT:-7860}"
if curl -fs -o /dev/null "$URL/api/models"; then
  xdg-open "$URL" >/dev/null 2>&1
  exit 0
fi
if [ -x .venv/bin/python ]; then
  msg="Starting…"
else
  msg="First run: installing dependencies, this takes a few minutes…"
fi
notify-send -a "Voice Transcriber" -i audio-input-microphone "Voice Transcriber" "$msg" 2>/dev/null || true
setsid nohup ./start.sh >app.log 2>&1 </dev/null &
