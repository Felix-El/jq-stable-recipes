#!/usr/bin/env bash
# Env combination coverage: for each filter with @env: declarations, compare
# the possible ENV combinations (declared values + null for optional vars)
# against the combinations actually exercised by the golden dispatcher.
#
# Exits 1 when any filter's coverage is below the target percentage, or when
# the overall coverage is below it.
# Target: ENV_COVERAGE_TARGET (default 50).
set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed. Install it first (e.g. sudo apt-get install jq)."
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILTER_DIR="$ROOT/filters"
FIXTURE_DIR="$ROOT/tests/fixtures"
TARGET="${ENV_COVERAGE_TARGET:-50}"

if ! [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  echo "ERROR: ENV_COVERAGE_TARGET must be an integer percentage (got: '$TARGET')"
  exit 1
fi

# ----------------------------------------------------------------
# Parse @env: declarations from .jq header (same format as run-tests.sh)
# Output: one line per var: "name|optional|values"
#   optional = "yes" or "no"
#   values   = raw string after the colon (e.g. "1" or "true|false")
# ----------------------------------------------------------------
parse_env_decls() {
  local filter_file="$1"
  while IFS= read -r line; do
    if [[ "$line" =~ ^#\ @env:([^?:\ ]+)\??:(.+)$ ]]; then
      local name="${BASH_REMATCH[1]}"
      local rest="${BASH_REMATCH[2]}"
      if [[ "$line" =~ ^#\ @env:([^:]+?)\?: ]]; then
        echo "$name|yes|$rest"
      else
        echo "$name|no|$rest"
      fi
    fi
  done < "$filter_file"
}

total_possible=0
total_covered=0
measured=0
exit_code=0

for filter_dir in "$FILTER_DIR"/*/; do
  [ -d "$filter_dir" ] || continue
  dir_name="$(basename "$filter_dir")"
  fixture_base="$FIXTURE_DIR/$dir_name"
  [ -d "$fixture_base" ] || continue

  for filter_file in "$filter_dir"/*.jq; do
    [ -f "$filter_file" ] || continue
    filter_name="$(basename "$filter_file" .jq)"
    label="$dir_name/$filter_name"

    # Build decls as JSON: [{"name":..., "optional":bool, "values":[...]}]
    decls_json="[]"
    while IFS= read -r decl; do
      [ -z "$decl" ] && continue
      name="${decl%%|*}"
      rest="${decl#*|}"
      optional="${rest%%|*}"
      values="${rest#*|}"
      opt_json="false"
      [ "$optional" = "yes" ] && opt_json="true"
      vals_json="$(printf '%s' "$values" | tr '|' '\n' | jq -R -s -c 'split("\n") | map(select(length > 0))')"
      decls_json="$(printf '%s' "$decls_json" | jq -c --arg n "$name" --argjson o "$opt_json" --argjson v "$vals_json" '. + [{name: $n, optional: $o, values: $v}]')"
    done < <(parse_env_decls "$filter_file")

    if [ "$(printf '%s' "$decls_json" | jq 'length')" -eq 0 ]; then
      echo "SKIP: $label — no @env: declarations"
      continue
    fi

    golden_file="$fixture_base/$filter_name.test.json"
    if [ ! -f "$golden_file" ]; then
      echo "FAIL: $label — no golden dispatcher ($filter_name.test.json), 0% coverage"
      exit_code=1
      continue
    fi

    # Compute possible vs tested combinations in jq.
    # Possible: cartesian product over vars of (values + [null] if optional).
    # Tested:   golden entries' .env projected onto declared vars.
    # Coverage: |possible ∩ tested| / |possible|.
    # The reduce is inlined: binding a var to a reduce result is a jq < 1.8
    # parse error (Ubuntu noble ships 1.7.1).
    result="$(jq -n -c \
      --argjson decls "$decls_json" \
      --slurpfile golden "$golden_file" \
      '
      def canon: to_entries | sort_by(.key) | tostring;
      ($decls | map({name, states: ((if .optional then [null] else [] end) + (.values // []))})) as $vars
      | ($vars | map(.name)) as $names
      | ([ reduce $vars[] as $v ({combos: [{}]};
            .combos as $prev
            | .combos = [ $prev[] as $c | $v.states[] as $s | $c + {($v.name): $s} ]
          )
          | .combos[] | canon ] | unique) as $possible
      | ([ ($golden[0] | to_entries[] | .value.env // {}) as $e
            | (reduce $names[] as $n ({}; .[$n] = $e[$n])) | canon ] | unique) as $tested
      | ([ $possible[] | select(IN($tested[])) ] | length) as $covered
      | { possible: ($possible | length), covered: $covered }
      ')"

    possible="$(printf '%s' "$result" | jq -r '.possible')"
    covered="$(printf '%s' "$result" | jq -r '.covered')"

    if [ "$possible" -eq 0 ]; then
      echo "SKIP: $label — no possible env combinations"
      continue
    fi

    pct=$((covered * 100 / possible))
    total_possible=$((total_possible + possible))
    total_covered=$((total_covered + covered))
    measured=$((measured + 1))

    if [ "$pct" -lt "$TARGET" ]; then
      echo "FAIL: $label — $covered/$possible env combinations tested ($pct% < ${TARGET}%)"
      exit_code=1
    else
      echo "PASS: $label — $covered/$possible env combinations tested ($pct%)"
    fi
  done
done

if [ "$measured" -gt 0 ]; then
  overall_pct=$((total_covered * 100 / total_possible))
  echo "----------------------------------------"
  if [ "$overall_pct" -lt "$TARGET" ]; then
    echo "FAIL: overall $total_covered/$total_possible env combinations tested (${overall_pct}% < ${TARGET}%)"
    exit_code=1
  else
    echo "PASS: overall $total_covered/$total_possible env combinations tested (${overall_pct}% >= ${TARGET}%)"
  fi
else
  echo "No filters with @env: declarations measured."
fi

exit $exit_code
