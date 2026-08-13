#!/usr/bin/env bash
# Follows Lua.log live and appends parsed events to events.jsonl as they
# happen, instead of waiting for a manual parser.lua run after the
# session ends. The game truncates Lua.log on every launch, so without
# this an unexpected server crash loses the whole session's log; `tail
# -F` reopens the file by name when it's truncated/replaced, so only
# the last unflushed line (if any) is at risk.
#
# Usage:
#   tools/watch.sh <path/to/Lua.log> <path/to/events.jsonl>
#
# Runs until killed (Ctrl-C, SIGTERM) — meant to be supervised
# (systemd on the pitboss server, launchd for local testing). See
# tools/README.md for unit/plist examples.

set -euo pipefail

LUA_LOG="${1:-}"
EVENTS_OUT="${2:-}"

if [[ -z "$LUA_LOG" || -z "$EVENTS_OUT" ]]; then
  echo "usage: $0 <path/to/Lua.log> <path/to/events.jsonl>" >&2
  exit 1
fi
command -v luajit >/dev/null 2>&1 || { echo "watch: luajit not found in PATH" >&2; exit 1; }

cd "$(dirname "$0")/.."

exec tail -F -n 0 "$LUA_LOG" | luajit tools/parser.lua >> "$EVENTS_OUT"
