#!/usr/bin/env bash
# Red/green check for tools/reconcile-unit-lost.jq against a hand-computed
# fixture covering every classification rule (see the tool's header) plus
# the one-to-one unit_killed consumption and the Barbarians-guard edge
# case. Compares parsed JSON (key order ignored), not raw text.
#
# Usage: tools/reconcile-unit-lost.test.sh

set -euo pipefail
cd "$(dirname "$0")/.."

FIXTURE="tools/testdata/unit_lost_fixture.jsonl"
EXPECTED="tools/testdata/unit_lost_fixture.expected.jsonl"
FILTER="tools/reconcile-unit-lost.jq"

if [[ ! -f "$FILTER" ]]; then
  echo "FAIL: $FILTER does not exist yet" >&2
  exit 1
fi

ACTUAL="$(jq -cS . <(jq -s -f "$FILTER" "$FIXTURE"))"
WANT="$(jq -cS . "$EXPECTED")"

if [[ "$ACTUAL" == "$WANT" ]]; then
  echo "PASS: reconcile-unit-lost matches the fixture"
else
  echo "FAIL: reconcile-unit-lost output differs from expected" >&2
  diff <(echo "$ACTUAL") <(echo "$WANT") >&2
  exit 1
fi
