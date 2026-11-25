#!/usr/bin/env bash
# shortcut target: run in background, or just open the page if already up
cd "$(dirname "$(readlink -f "$0")")"
URL="http://127.0.0.1:${PORT:-7860}"
OS="$(uname -s)"

open_url() {
  if [ "$OS" = Darwin ]; then open "$1"; else xdg-open "$1" >/dev/null 2>&1; fi
}

notify() {
  if [ "$OS" = Darwin ]; then
    osascript -e "display notification \"$1\" with title \"Voice Transcriber\"" 2>/dev/null || true
  else
    notify-send -a "Voice Transcriber" -i audio-input-microphone "Voice Transcriber" "$1" 2>/dev/null || true
  fi
}

# Run start.sh in a terminal window, so it can ask before installing things.
open_terminal() {
  if [ "$OS" = Darwin ]; then
    open -a Terminal "$PWD/start.sh" && return 0
  else
    local t
    for t in konsole gnome-terminal kitty alacritty xfce4-terminal x-terminal-emulator xterm; do
      command -v "$t" >/dev/null 2>&1 || continue
      case "$t" in
        gnome-terminal) "$t" -- "$PWD/start.sh" & ;;
        *) "$t" -e "$PWD/start.sh" & ;;
      esac
      return 0
    done
  fi
  return 1
}

if curl -fs -o /dev/null "$URL/api/models"; then
  open_url "$URL"
  exit 0
fi

if ! ./start.sh --check >/dev/null 2>&1; then
  notify "Some things need to be installed first. Follow the steps in the terminal."
  open_terminal || notify "Open a terminal and run ./start.sh to finish the setup."
  exit 0
fi

if [ -x .venv/bin/python ]; then
  notify "Starting…"
else
  notify "First run: installing Python packages, this takes a few minutes…"
fi
if command -v setsid >/dev/null 2>&1; then
  setsid nohup ./start.sh >app.log 2>&1 </dev/null &
else
  nohup ./start.sh >app.log 2>&1 </dev/null &
fi
disown 2>/dev/null || true
