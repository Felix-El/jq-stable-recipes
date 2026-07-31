# Show recipe list, filter inventory, and usage hints
default: _discover

# Alias for `just default` (recipe list + filter inventory)
list: _discover

# Run a filter on its fixture input: just run <family/name>
run filter:
    #!/usr/bin/env bash
    set -euo pipefail
    arg={{quote(filter)}}

    print_inventory() {
        echo "Available filters:"
        for d in filters/*/; do
            [ -d "$d" ] || continue
            fam="$(basename "$d")"
            for f in "$d"*.jq; do
                [ -f "$f" ] || continue
                echo "  $fam/$(basename "$f" .jq)"
            done
        done
    }

    if [[ "$arg" != */* ]]; then
        echo "ERROR: filter must be <family>/<name>, got '$arg'" >&2
        echo
        print_inventory >&2
        exit 1
    fi
    family="${arg%%/*}"
    name="${arg#*/}"
    filter_file="filters/$family/$name.jq"
    if [ ! -f "$filter_file" ]; then
        echo "ERROR: filter file not found: $filter_file" >&2
        echo
        print_inventory >&2
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
        bash tests/run-tests.sh
    elif [[ "$arg" == */* ]]; then
        bash tests/run-tests.sh "${arg%%/*}" "${arg#*/}"
    else
        bash tests/run-tests.sh "$arg"
    fi

# Check SPDX license headers on all filter files
lint:
    bash tests/spdx-check.sh

# Check env-combination coverage (ENV_COVERAGE_TARGET, default 50)
coverage:
    bash tests/coverage.sh

# Validate JSON fixtures: just check-json [family]
check-json family="":
    #!/usr/bin/env bash
    set -euo pipefail
    fam={{quote(family)}}
    if [ -z "$fam" ]; then
        bash tests/check-json.sh
    else
        bash tests/check-json.sh "$fam"
    fi

# (private) print discovery output: recipe list + filter inventory + usage
_discover:
    #!/usr/bin/env bash
    set -euo pipefail
    just --justfile {{justfile()}} --list
    echo
    echo "Available filters:"
    for d in filters/*/; do
        [ -d "$d" ] || continue
        fam="$(basename "$d")"
        for f in "$d"*.jq; do
            [ -f "$f" ] || continue
            echo "  $fam/$(basename "$f" .jq)"
        done
    done
    echo
    echo "Usage: just run <family/name>, just test [family/name], just check-json [family]"
