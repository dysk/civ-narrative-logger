#!/bin/sh
# Installs the logger into an existing LEKMOD DLC folder on THIS
# machine (the pitboss server or a local test install). Clients need
# nothing. Re-run after LEKMOD updates or after running its
# ui_check.bat, which regenerates InGame.lua and drops our line.
set -e

LEKMOD_DIR="$1"
INGAME="$LEKMOD_DIR/Lua/UI/InGame.lua"

if [ -z "$LEKMOD_DIR" ] || [ ! -f "$INGAME" ]; then
  echo "usage: $0 <path-to-LEKMOD-DLC-folder>" >&2
  echo "note: LEKMOD's Lua/UI/InGame.lua must exist (run its ui_check first)" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

if command -v luajit >/dev/null 2>&1; then
  luajit tools/build.lua dist/CivNarrativeLogger.lua
fi

cp dist/CivNarrativeLogger.lua "$LEKMOD_DIR/Lua/"

LINE='ContextPtr:LoadNewContext("CivNarrativeLogger")'
if ! grep -qF "$LINE" "$INGAME"; then
  printf '\n%s\n' "$LINE" >> "$INGAME"
fi

echo "installed into $LEKMOD_DIR"
echo "remember: logging also needs the enabled flag (see tools/README.md)"
