# Show recipe list, filter inventory, and usage hints
default: _discover

# Alias for `just default` (recipe list + filter inventory)
list: _discover

# Run a filter on its fixture input: just run <family/name>
run filter:
    #!/usr/bin/env bash
    set -euo pipefail
    arg={{quote(filter)}}

    if [[ "$arg" != */* ]]; then
        echo "ERROR: filter must be <family>/<name>, got '$arg'" >&2
        echo >&2
        echo "Available filters:" >&2
        just --justfile {{justfile()}} _filters >&2
        exit 1
    fi
    family="${arg%%/*}"
    name="${arg#*/}"
    filter_file="filters/$family/$name.jq"
    if [ ! -f "$filter_file" ]; then
        echo "ERROR: filter file not found: $filter_file" >&2
        echo >&2
        echo "Available filters:" >&2
        just --justfile {{justfile()}} _filters >&2
        exit 1
    fi
    input_file="tests/fixtures/$family/mutants/input.json"
    if [ ! -f "$input_file" ]; then
        echo "ERROR: input fixture not found: $input_file" >&2
        exit 1
    fi
    jq -s -f "$filter_file" "$input_file"

# Run tests: just test (all), just test <family>, just test <family/name>
test filter="":
    #!/usr/bin/env bash
    set -euo pipefail
    arg={{quote(filter)}}
    if [ -z "$arg" ]; then
        just --justfile {{justfile()}} _test
    elif [[ "$arg" == */* ]]; then
        just --justfile {{justfile()}} _test "${arg%%/*}" "${arg#*/}"
    else
        just --justfile {{justfile()}} _test "$arg"
    fi

# Check SPDX license headers on all filter files
lint: _spdx-check

# Check env-combination coverage (ENV_COVERAGE_TARGET, default 50)
coverage: _coverage-check

# Validate JSON fixtures: just check-json [family]
check-json family="":
    #!/usr/bin/env bash
    set -euo pipefail
    fam={{quote(family)}}
    if [ -z "$fam" ]; then
        just --justfile {{justfile()}} _check-json
    else
        just --justfile {{justfile()}} _check-json "$fam"
    fi

# ================================================================
# Private recipes — internal helpers, hidden from `just --list`.
# ================================================================

# (private) discovery output: recipe list + filter inventory + usage hint
_discover:
    #!/usr/bin/env bash
    set -euo pipefail
    just --justfile {{justfile()}} --list
    echo
    echo "Available filters:"
    just --justfile {{justfile()}} _filters
    echo
    echo "Usage: just run <family/name>, just test [family/name], just check-json [family]"

# (private) filter inventory: one indented `<family>/<name>` per line
_filters:
    #!/usr/bin/env bash
    set -euo pipefail
    for d in filters/*/; do
        [ -d "$d" ] || continue
        fam="$(basename "$d")"
        for f in "$d"*.jq; do
            [ -f "$f" ] || continue
            echo "  $fam/$(basename "$f" .jq)"
        done
    done

# (private) parse `# @env:` declarations from a filter header
#   output: one line per var: "name|optional|values"
_env-decls file:
    #!/usr/bin/env bash
    set -euo pipefail
    while IFS= read -r line; do
        if [[ "$line" =~ ^#\ @env:([^?:\ ]+)\??:(.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
            rest="${BASH_REMATCH[2]}"
            # Optional if '?' follows the name
            if [[ "$line" =~ ^#\ @env:([^:]+?)\?: ]]; then
                echo "$name|yes|$rest"
            else
                echo "$name|no|$rest"
            fi
        fi
    done < {{quote(file)}}

# (private) test runner: golden + mutation tests + @env coverage validation.
#   just _test               all filters
#   just _test <family>      one family
#   just _test <family> <f>  one filter file
_test family="" filter="":
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is not installed. Install it first (e.g. sudo apt-get install jq)."
        exit 1
    fi

    FILTER_DIR="filters"
    FIXTURE_DIR="tests/fixtures"
    FAMILY_FILTER={{quote(family)}}
    FILTER_FILTER={{quote(filter)}}
    exit_code=0
    tests_run=0

    # Validate the requested family/filter, if any
    if [ -n "$FAMILY_FILTER" ] && [ ! -d "$FILTER_DIR/$FAMILY_FILTER" ]; then
        echo "ERROR: family '$FAMILY_FILTER' not found at $FILTER_DIR/$FAMILY_FILTER" >&2
        exit 1
    fi
    if [ -n "$FILTER_FILTER" ] && [ ! -f "$FILTER_DIR/$FAMILY_FILTER/$FILTER_FILTER.jq" ]; then
        echo "ERROR: filter '$FAMILY_FILTER/$FILTER_FILTER' not found at $FILTER_DIR/$FAMILY_FILTER/$FILTER_FILTER.jq" >&2
        exit 1
    fi

    # Build env argument array from a golden entry's env object.
    # Null values = skip (don't set), string values = "NAME=VALUE".
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

    # Mutation test: apply filter to all fixture inputs under given env,
    # verify all outputs match.
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

    # Golden test: apply filter to a specific input with given env,
    # compare output byte-for-byte against expected file.
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

    # Validate that all @env: declarations are covered by golden entries.
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

    # ---- Main loop over families and filters ----
    for filter_dir in "$FILTER_DIR"/*/; do
        [ -d "$filter_dir" ] || continue
        dir_name="$(basename "$filter_dir")"

        # Family filter: when a family is requested, skip all others silently.
        if [ -n "$FAMILY_FILTER" ] && [ "$dir_name" != "$FAMILY_FILTER" ]; then
            continue
        fi

        fixture_base="$FIXTURE_DIR/$dir_name"

        if [ ! -d "$fixture_base" ]; then
            echo "SKIP: $dir_name — no fixtures at $fixture_base"
            continue
        fi

        for filter_file in "$filter_dir"/*.jq; do
            [ -f "$filter_file" ] || continue
            filter_name="$(basename "$filter_file" .jq)"

            # Filter filter: when a specific filter is requested, skip all others.
            if [ -n "$FILTER_FILTER" ] && [ "$filter_name" != "$FILTER_FILTER" ]; then
                continue
            fi
            tests_run=$((tests_run + 1))

            label_base="$dir_name/$filter_name"

            # Parse @env: declarations from header
            mapfile -t env_decls < <(just --justfile {{justfile()}} _env-decls "$filter_file")

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

    # When a family/filter was explicitly requested, zero tests run means the
    # request matched nothing runnable (e.g. family has no fixtures) — fail loudly.
    if { [ -n "$FAMILY_FILTER" ] || [ -n "$FILTER_FILTER" ]; } && [ "$tests_run" -eq 0 ]; then
        echo "ERROR: no tests ran for '$FAMILY_FILTER${FILTER_FILTER:+/$FILTER_FILTER}'" >&2
        exit 1
    fi

    exit $exit_code

# (private) SPDX header check: every filters/*.jq must start with an SPDX
# license tag as the first line of its header comment, followed by a blank line.
_spdx-check:
    #!/usr/bin/env bash
    set -euo pipefail

    fail=0
    while IFS= read -r -d '' file; do
        rel="${file#filters/}"
        line1="$(sed -n '1p' "$file")"
        line2="$(sed -n '2p' "$file")"

        if ! [[ "$line1" =~ ^#\ SPDX-License-Identifier:\ [A-Za-z0-9.\-]+$ ]]; then
            echo "FAIL: $rel — line 1 is not an SPDX tag (got: '$line1')"
            fail=1
            continue
        fi
        if ! [[ "$line2" == "" || "$line2" == "#" ]]; then
            echo "FAIL: $rel — line 2 must be blank after the SPDX tag (got: '$line2')"
            fail=1
        fi
    done < <(find filters -name '*.jq' -type f -print0)

    if [ "$fail" -eq 0 ]; then
        echo "PASS: all filter headers carry an SPDX license tag"
    fi
    exit $fail

# (private) env-combination coverage check (ENV_COVERAGE_TARGET, default 50)
_coverage-check:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is not installed. Install it first (e.g. sudo apt-get install jq)."
        exit 1
    fi

    FILTER_DIR="filters"
    FIXTURE_DIR="tests/fixtures"
    TARGET="${ENV_COVERAGE_TARGET:-50}"

    if ! [[ "$TARGET" =~ ^[0-9]+$ ]]; then
        echo "ERROR: ENV_COVERAGE_TARGET must be an integer percentage (got: '$TARGET')"
        exit 1
    fi

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
            done < <(just --justfile {{justfile()}} _env-decls "$filter_file")

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

# (private) canonical pretty-JSON check, optionally scoped to a fixture family.
#   just _check-json             all version-controlled JSONs
#   just _check-json <family>    only tests/fixtures/<family>/
_check-json family="":
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is not installed. Install it first (e.g. sudo apt-get install jq)."
        exit 1
    fi

    family={{quote(family)}}
    exit_code=0

    if [ -n "$family" ]; then
        family_dir="tests/fixtures/$family"
        if [ ! -d "$family_dir" ]; then
            echo "ERROR: fixture family '$family' does not exist (expected $family_dir)"
            exit 1
        fi
        files=$(git ls-files '*.json' | grep "^tests/fixtures/$family/")
    else
        files=$(git ls-files '*.json')
    fi

    # check_file: verify a single JSON file is in canonical pretty form.
    #   n > 1 → NDJSON: every non-empty line must byte-match jq -c . output
    #   n = 1 → single document: file must byte-match jq . output
    #   n = 0 → unparseable: fail
    # n is obtained via `jq -s 'length'` (slurp all top-level JSON values).
    check_file() {
        local f="$1"
        local n
        n=$(jq -s 'length' "$f" 2>/dev/null || echo 0)

        if [ "$n" -eq 0 ]; then
            echo "FAIL: $f — unparseable JSON"
            return 1
        fi

        if [ "$n" -gt 1 ]; then
            # NDJSON: every non-empty line must match jq -c . output
            local line canon
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                canon=$(jq -c . <<<"$line" 2>/dev/null) || {
                    echo "FAIL: $f — unparseable NDJSON line"
                    return 1
                }
                if [ "$line" != "$canon" ]; then
                    echo "FAIL: $f — NDJSON line not in canonical compact form"
                    return 1
                fi
            done < "$f"
            echo "PASS: $f"
            return 0
        fi

        # n == 1: single document — must byte-match jq . output
        if diff <(jq . "$f" 2>/dev/null) "$f" >/dev/null 2>&1; then
            echo "PASS: $f"
            return 0
        else
            echo "FAIL: $f — not in canonical pretty form (jq . mismatch)"
            return 1
        fi
    }

    if [ -z "$files" ]; then
        echo "No version-controlled JSON files found."
        exit 0
    fi

    total=0
    passed=0
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        total=$((total + 1))
        if check_file "$rel"; then
            passed=$((passed + 1))
        else
            exit_code=1
        fi
    done <<< "$files"

    echo "----------------------------------------"
    if [ "$passed" -eq "$total" ]; then
        echo "PASS: $passed/$total JSON files are canonical"
    else
        echo "FAIL: $passed/$total JSON files are canonical"
    fi

    exit $exit_code
