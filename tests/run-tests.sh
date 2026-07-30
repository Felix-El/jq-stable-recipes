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

# ----------------------------------------------------------------
# Parse @env: declarations from .jq header
#   # @env:VAR:values       — VAR is required
#   # @env:VAR?:values      — VAR is optional, null/unset is valid
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
      # Determine if optional by checking for '?' after the name in original
      if [[ "$line" =~ ^#\ @env:([^:]+?)\?: ]]; then
        echo "$name|yes|$rest"
      else
        echo "$name|no|$rest"
      fi
    fi
  done < "$filter_file"
}

# ----------------------------------------------------------------
# Build env argument array from a golden entry's env object.
# Input: a JSON object with .value.env (from to_entries[]).
# Null values = skip (don't set), string values = "NAME=VALUE".
# Output: env_args array is populated in the caller's scope.
# ----------------------------------------------------------------
build_env_args() {
  local golden_entry="$1"
  env_args=()
  local env_obj
  env_obj="$(echo "$golden_entry" | jq -c '.value.env')"
  [ "$env_obj" = "null" ] && return 0
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    local val
    val="$(echo "$env_obj" | jq -r ".[\"$key\"]")"
    if [ "$val" != "null" ]; then
      env_args+=("$key=$val")
    fi
  done < <(echo "$env_obj" | jq -r 'keys[]')
}

# ----------------------------------------------------------------
# Mutation test: apply filter to all fixture inputs under given env,
# verify all outputs match.
# ----------------------------------------------------------------
run_mutation_test() {
  local label="$1"
  local filter_file="$2"
  local fixture_dir="$3"
  shift 3
  local -a env_args=("$@")

  local fixtures=("$fixture_dir"/mutants/*.json)
  if [ ${#fixtures[@]} -lt 2 ]; then
    echo "SKIP: $label mutation — need ≥2 fixtures (got ${#fixtures[@]})"
    return 0
  fi

  local outputs=()
  for fixture in "${fixtures[@]}"; do
    if [ ${#env_args[@]} -eq 0 ]; then
      output="$(jq -s -f "$filter_file" "$fixture" 2>&1)" || {
        echo "FAIL: $label mutation — jq error on $(basename "$fixture")"
        echo "$output"
        return 1
      }
    else
      output="$(env "${env_args[@]}" jq -s -f "$filter_file" "$fixture" 2>&1)" || {
        echo "FAIL: $label mutation — jq error on $(basename "$fixture")"
        echo "$output"
        return 1
      }
    fi
    outputs+=("$output")
  done

  local first="${outputs[0]}"
  for i in "${!outputs[@]}"; do
    if [ "${outputs[$i]}" != "$first" ]; then
      echo "FAIL: $label mutation — fixtures differ (fixture $i vs 0)"
      diff <(echo "$first") <(echo "${outputs[$i]}") || true
      return 1
    fi
  done

  echo "PASS: $label mutation (${#fixtures[@]} fixtures)"
  return 0
}

# ----------------------------------------------------------------
# Golden test: apply filter to a specific input with given env,
# compare output byte-for-byte against expected file.
# ----------------------------------------------------------------
run_golden_test() {
  local label="$1"
  local filter_file="$2"
  local input_file="$3"
  local expected_file="$4"
  shift 4
  local -a env_args=("$@")

  if [ ! -f "$input_file" ]; then
    echo "FAIL: $label golden — input not found: $input_file"
    return 1
  fi
  if [ ! -f "$expected_file" ]; then
    echo "FAIL: $label golden — expected output not found: $expected_file"
    return 1
  fi

  local output
  if [ ${#env_args[@]} -eq 0 ]; then
    output="$(jq -s -f "$filter_file" "$input_file" 2>&1)" || {
      echo "FAIL: $label golden — jq error"
      echo "$output"
      return 1
    }
  else
    output="$(env "${env_args[@]}" jq -s -f "$filter_file" "$input_file" 2>&1)" || {
      echo "FAIL: $label golden — jq error"
      echo "$output"
      return 1
    }
  fi

  if ! diff <(echo "$output") "$expected_file" >/dev/null; then
    echo "FAIL: $label golden — output differs from $expected_file"
    diff <(echo "$output") "$expected_file" || true
    return 1
  fi

  echo "PASS: $label golden"
  return 0
}

# ----------------------------------------------------------------
# Validate that all @env: declarations are covered by golden entries.
# ----------------------------------------------------------------
validate_coverage() {
  local label="$1"
  local golden_file="$2"
  shift 2
  local -a decls=("$@")

  local ok=0
  for decl in "${decls[@]}"; do
    local name="${decl%%|*}"
    local rest="${decl#*|}"
    local optional="${rest%%|*}"
    local values="${rest#*|}"

    # Collect values for this var across all golden entries
    local set_count=0
    local null_count=0
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      local val
      val="$(echo "$entry" | jq -r ".env[\"$name\"]")"
      if [ "$val" = "null" ]; then
        null_count=$((null_count + 1))
      else
        set_count=$((set_count + 1))
      fi
    done < <(jq -c 'to_entries[] | .value' "$golden_file")

    if [ "$optional" = "no" ]; then
      if [ "$set_count" -eq 0 ]; then
        echo "FAIL: $label — required var $name never set in golden file"
        ok=1
      fi
    else
      # optional — must have both a set and a null entry
      if [ "$set_count" -eq 0 ]; then
        echo "FAIL: $label — optional var $name? has no set entry in golden file"
        ok=1
      fi
      if [ "$null_count" -eq 0 ]; then
        echo "FAIL: $label — optional var $name? has no null/unset entry in golden file"
        ok=1
      fi
    fi
  done

  return $ok
}

# ================================================================
# Main loop
# ================================================================
for filter_dir in "$FILTER_DIR"/*/; do
  [ -d "$filter_dir" ] || continue
  dir_name="$(basename "$filter_dir")"
  fixture_base="$FIXTURE_DIR/$dir_name"

  if [ ! -d "$fixture_base" ]; then
    echo "SKIP: $dir_name — no fixtures at $fixture_base"
    continue
  fi

  for filter_file in "$filter_dir"/*.jq; do
    [ -f "$filter_file" ] || continue
    filter_name="$(basename "$filter_file" .jq)"
    label_base="$dir_name/$filter_name"

    # Parse @env: declarations from header
    mapfile -t env_decls < <(parse_env_decls "$filter_file")

    # Look for golden dispatcher
    golden_file="$fixture_base/$filter_name.test.json"

    if [ -f "$golden_file" ]; then
      # ---- Golden dispatcher exists: run per-entry tests ----
      golden_entries="$(jq -c 'to_entries[]' "$golden_file")"

      while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        entry_label="$(echo "$entry" | jq -r '.key')"
        variant="$label_base ($entry_label)"

        # Build env args from this entry
        build_env_args "$entry"
        local_input="$(echo "$entry" | jq -r '.value.input // "mutants/input.json"')"
        local_input_path="$fixture_base/$local_input"
        expected_file="$fixture_base/$(echo "$entry" | jq -r '.value.expected')"

        run_mutation_test "$variant" "$filter_file" "$fixture_base" "${env_args[@]}" || exit_code=1
        run_golden_test "$variant" "$filter_file" "$local_input_path" "$expected_file" "${env_args[@]}" || exit_code=1
      done < <(echo "$golden_entries")

      # Validate coverage: every @env: declaration must be covered
      if [ ${#env_decls[@]} -gt 0 ]; then
        validate_coverage "$label_base" "$golden_file" "${env_decls[@]}" || exit_code=1
      fi
    else
      # ---- No golden file: default mutation test only ----
      if [ ${#env_decls[@]} -gt 0 ]; then
        echo "WARN: $label_base — @env: declared but no golden file (mutation only)"
      fi
      run_mutation_test "$label_base (default)" "$filter_file" "$fixture_base" || exit_code=1
    fi
  done
done

exit $exit_code
