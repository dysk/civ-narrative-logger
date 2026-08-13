#!/usr/bin/env bash
# Keeps only the events.jsonl lines that concern the major nations (the
# players listed in the first session_started record), dropping lines
# that are purely about city-states or barbarians. A line survives if any
# string value anywhere in it names a major - not just the .civ field,
# since the name shows up under different keys depending on event type
# (civ, civs, killer/victim, city_state+civ, attacker_civs/defender_civs,
# team_a_civs/team_b_civs, new_ally/old_ally, ...). This also keeps
# minor-nation events that involve a major, e.g. a city-state's unit
# killed_by a major, or a major's war against a city-state.
#
# Usage:
#   tools/filter-major.sh <events.jsonl> [--out file]
#
# Requires: jq

set -euo pipefail

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

command -v jq >/dev/null 2>&1 || { echo "filter-major: 'jq' not found in PATH" >&2; exit 2; }

EVENTS=""
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) EVENTS="$1"; shift ;;
  esac
done

if [[ -z "$EVENTS" || ! -f "$EVENTS" ]]; then
  usage
  exit 2
fi

FIRST_LINE="$(head -n 1 "$EVENTS")"
if [[ "$(jq -r '.event' <<<"$FIRST_LINE")" != "session_started" ]]; then
  echo "filter-major: first line of $EVENTS is not session_started" >&2
  exit 2
fi
MAJORS_JSON="$(jq -c '.players | map(.civ)' <<<"$FIRST_LINE")"

FILTERED="$(jq -c --argjson majors "$MAJORS_JSON" \
  'select([.. | strings] as $vals | any($majors[]; . as $m | $vals | index($m) != null))' \
  "$EVENTS")"

if [[ -n "$OUT" ]]; then
  printf '%s\n' "$FILTERED" > "$OUT"
  echo "filter-major: written to $OUT" >&2
else
  printf '%s\n' "$FILTERED"
fi
