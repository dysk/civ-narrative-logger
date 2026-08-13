#!/usr/bin/env bash
# Chains the two deterministic prep tools into one command: reconcile
# unit_lost causes, then filter down to the major nations. The result is
# one JSONL file ready to hand to any LLM (local or hosted) or to a
# future strategy-analysis tool - no ask-local dependency here, since not
# everyone running this repo has a local model set up. Each stage is also
# a standalone tool (reconcile-unit-lost.jq, filter-major.sh) if you want
# to inspect or rerun just one of them.
#
# Usage:
#   tools/pipeline.sh <events.jsonl> [--out file]
#
#   --out file   where to write the result (default: stdout)
#
# Requires: jq

set -euo pipefail

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
}

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

cd "$(dirname "$0")/.."

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "pipeline: reconciling unit_lost causes..." >&2
jq -c -s -f tools/reconcile-unit-lost.jq "$EVENTS" > "$WORKDIR/reconciled.jsonl"

echo "pipeline: filtering to major nations..." >&2
if [[ -n "$OUT" ]]; then
  tools/filter-major.sh "$WORKDIR/reconciled.jsonl" --out "$OUT"
else
  tools/filter-major.sh "$WORKDIR/reconciled.jsonl"
fi
