#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed. Install it first (e.g. sudo apt-get install jq)."
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILTER_DIR="$ROOT/filters"
FIXTURE_DIR="$ROOT/tests/fixtures"
exit_code=0

for filter_dir in "$FILTER_DIR"/*/; do
  [ -d "$filter_dir" ] || continue
  filter_name="$(basename "$filter_dir")"
  filter_file="$filter_dir/$filter_name.jq"
  fixture_base="$FIXTURE_DIR/$filter_name"

  if [ ! -f "$filter_file" ]; then
    echo "FAIL: $filter_name — missing $filter_file"
    exit_code=1
    continue
  fi

  if [ ! -d "$fixture_base" ]; then
    echo "FAIL: $filter_name — no fixtures at $fixture_base"
    exit_code=1
    continue
  fi

  fixtures=("$fixture_base"/*.json)
  if [ ${#fixtures[@]} -lt 2 ]; then
    echo "FAIL: $filter_name — need at least 2 fixtures (got ${#fixtures[@]})"
    exit_code=1
    continue
  fi

  # Apply filter to each fixture, collect outputs
  outputs=()
  for fixture in "${fixtures[@]}"; do
    if ! output="$(jq -s -f "$filter_file" "$fixture" 2>&1)"; then
      echo "FAIL: $filter_name — jq error on $(basename "$fixture")"
      echo "$output"
      exit_code=1
      continue 2
    fi
    outputs+=("$output")
  done

  # Compare all outputs pairwise
  first="${outputs[0]}"
  all_match=true
  for i in "${!outputs[@]}"; do
    if [ "${outputs[$i]}" != "$first" ]; then
      echo "FAIL: $filter_name — fixtures differ (fixture $i vs fixture 0)"
      echo "diff between fixture 0 and fixture $i:"
      diff <(echo "$first") <(echo "${outputs[$i]}") || true
      all_match=false
      exit_code=1
    fi
  done

  if $all_match; then
    echo "PASS: $filter_name (${#fixtures[@]} fixtures)"
  fi
done

exit $exit_code
