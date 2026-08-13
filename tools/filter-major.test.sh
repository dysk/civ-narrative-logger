#!/usr/bin/env bash
# Red/green check for tools/filter-major.sh: keeps a line iff some string
# value anywhere in it names one of the majors from the first
# session_started record, regardless of which field holds it (civ, civs,
# killer/victim, city_state+civ, attacker_civs/defender_civs, ...).
# Order-sensitive (it's a stream filter), key-order-insensitive per line.
#
# Usage: tools/filter-major.test.sh

set -euo pipefail
cd "$(dirname "$0")/.."

FIXTURE="tools/testdata/filter_major_fixture.jsonl"
EXPECTED="tools/testdata/filter_major_fixture.expected.jsonl"
TOOL="tools/filter-major.sh"

if [[ ! -x "$TOOL" ]]; then
  echo "FAIL: $TOOL does not exist yet (or isn't executable)" >&2
  exit 1
fi

ACTUAL="$("$TOOL" "$FIXTURE" | jq -cS .)"
WANT="$(jq -cS . "$EXPECTED")"

if [[ "$ACTUAL" == "$WANT" ]]; then
  echo "PASS: filter-major matches the fixture"
else
  echo "FAIL: filter-major output differs from expected" >&2
  diff <(echo "$ACTUAL") <(echo "$WANT") >&2
  exit 1
fi
