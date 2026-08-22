#!/usr/bin/env bash
# Turns events.jsonl into a chronicle-style narrative via the local LLM
# (ask-local), splitting the log into turn-range chunks first so a
# multi-session log doesn't overflow the model's context window.
#
# Two passes:
#   1. map   — each turn-range chunk is compacted into terse bullet
#              notes for the nations found in the session_started event.
#              A chunk that still doesn't fit is bisected by turn and
#              retried (recursively) rather than failing outright.
#   2. reduce — the compacted notes (much smaller than the raw log) are
#              woven into one narrative in a single final call.
#
# Usage:
#   tools/chronicle.sh <events.jsonl> [--turns-per-chunk N] [--out plik]
#
#   --turns-per-chunk N   tury na fragment w pierwszym przebiegu (domyślnie 20)
#   --out plik            gdzie zapisać finalną kronikę (domyślnie stdout)
#
# Wymaga: ask-local, jq

set -euo pipefail

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

for bin in ask-local jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "chronicle: brak '$bin' w PATH" >&2
    exit 2
  }
done

EVENTS=""
TURNS_PER_CHUNK=20
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --turns-per-chunk) TURNS_PER_CHUNK="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) EVENTS="$1"; shift ;;
  esac
done

if [[ -z "$EVENTS" || ! -f "$EVENTS" ]]; then
  usage
  exit 2
fi
if ! [[ "$TURNS_PER_CHUNK" =~ ^[0-9]+$ && "$TURNS_PER_CHUNK" -ge 1 ]]; then
  echo "chronicle: --turns-per-chunk musi być liczbą całkowitą >= 1" >&2
  exit 2
fi

FIRST_LINE="$(head -n 1 "$EVENTS")"
if [[ "$(jq -r '.event' <<<"$FIRST_LINE")" != "session_started" ]]; then
  echo "chronicle: pierwsza linia $EVENTS to nie session_started" >&2
  exit 2
fi
PLAYERS="$(jq -r '.players | map(.civ) | join(", ")' <<<"$FIRST_LINE")"
MAX_TURN="$(jq -r '.turn // 0' "$EVENTS" | sort -n | tail -1)"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
NOTES_FILE="$WORKDIR/notes.md"
: > "$NOTES_FILE"

compact_chunk() {
  local from="$1" to="$2"
  local chunk
  chunk="$(jq -c --argjson from "$from" --argjson to "$to" \
    'select(.event != "session_started" and (.turn // 0) >= $from and (.turn // 0) <= $to)' \
    "$EVENTS")"
  [[ -n "$chunk" ]] || return 0

  local prompt="Poniżej fragment logu zdarzeń (tury $from-$to) z rozgrywki Civilization w formacie JSONL, dotyczący nacji: $PLAYERS (pomiń wydarzenia innych stron, jeśli się pojawią). Zredukuj go do zwięzłych, kronikarskich notatek punktowanych po turach — tylko istotne wydarzenia (miasta, wojny, dyplomacja, cuda, wzloty i upadki), bez powtarzania surowych pól JSON. Pisz po polsku, terse."

  local out
  if out="$(printf '%s\n' "$chunk" | ask-local "$prompt")"; then
    { printf '## Tury %s-%s\n' "$from" "$to"; printf '%s\n\n' "$out"; } >> "$NOTES_FILE"
    return 0
  fi

  local span=$(( to - from ))
  if (( span <= 0 )); then
    echo "chronicle: tura $from ma za dużo zdarzeń, żeby zmieścić się w oknie modelu — pomijam ją." >&2
    return 0
  fi
  local mid=$(( from + span / 2 ))
  echo "chronicle: fragment $from-$to nie zmieścił się w oknie modelu, dzielę na $from-$mid i $((mid + 1))-$to" >&2
  compact_chunk "$from" "$mid"
  compact_chunk "$((mid + 1))" "$to"
}

for ((start = 0; start <= MAX_TURN; start += TURNS_PER_CHUNK)); do
  end=$(( start + TURNS_PER_CHUNK - 1 ))
  compact_chunk "$start" "$end"
done

FINAL_PROMPT="Poniżej skrócone notatki kronikarskie z kolejnych fragmentów rozgrywki Civilization, dotyczące nacji: $PLAYERS. Połącz je w jedno spójne opowiadanie w stylu dawnej kroniki dziejopisarskiej, zachowując chronologię i archaiczny styl narracji. Pisz po polsku."
RESULT="$(cat "$NOTES_FILE" | ask-local "$FINAL_PROMPT")"

if [[ -n "$OUT" ]]; then
  printf '%s\n' "$RESULT" > "$OUT"
  echo "chronicle: zapisano do $OUT" >&2
else
  printf '%s\n' "$RESULT"
fi
