#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Pretty-JSON check: verifies every version-controlled JSON file is in
# canonical pretty form — jq's 2-space pretty print for single documents,
# or jq -c compact output for NDJSON (one JSON value per line).
# Optionally scoped to a single fixture family.
#
# Usage:
#   tests/check-json.sh             Check all version-controlled JSONs
#   tests/check-json.sh <family>    Check only tests/fixtures/<family>/
#
# Exits 0 iff every checked file is canonical, else 1.
set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed. Install it first (e.g. sudo apt-get install jq)."
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_DIR="$ROOT/tests/fixtures"
exit_code=0

# ----------------------------------------------------------------
# Parse arguments and build the file list from version-controlled
# JSON files only (git ls-files).
# ----------------------------------------------------------------
if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [family]"
  echo "  family  a fixture family name (e.g. cargo-audit) to check only tests/fixtures/<family>/"
  exit 1
fi

if [ "$#" -eq 1 ]; then
  family="$1"
  family_dir="$FIXTURE_DIR/$family"
  if [ ! -d "$family_dir" ]; then
    echo "ERROR: fixture family '$family' does not exist (expected $family_dir)"
    exit 1
  fi
  files=$(git -C "$ROOT" ls-files '*.json' | grep "^tests/fixtures/$family/")
else
  files=$(git -C "$ROOT" ls-files '*.json')
fi

# ----------------------------------------------------------------
# check_file: verify a single JSON file is in canonical pretty form.
#
#   n > 1 → NDJSON: every non-empty line must byte-match jq -c . output
#   n = 1 → single document: file must byte-match jq . output
#   n = 0 → unparseable: fail
#
# The document count n is obtained via `jq -s 'length'` which slurps
# all top-level JSON values into an array and reports its length.
# ----------------------------------------------------------------
check_file() {
  local f="$1"
  local rel="${f#"$ROOT"/}"
  local n
  n=$(jq -s 'length' "$f" 2>/dev/null || echo 0)

  if [ "$n" -eq 0 ]; then
    echo "FAIL: $rel — unparseable JSON"
    return 1
  fi

  if [ "$n" -gt 1 ]; then
    # NDJSON: every non-empty line must match jq -c . output
    local line canon
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      canon=$(jq -c . <<<"$line" 2>/dev/null) || {
        echo "FAIL: $rel — unparseable NDJSON line"
        return 1
      }
      if [ "$line" != "$canon" ]; then
        echo "FAIL: $rel — NDJSON line not in canonical compact form"
        return 1
      fi
    done < "$f"
    echo "PASS: $rel"
    return 0
  fi

  # n == 1: single document — must byte-match jq . output
  if diff <(jq . "$f" 2>/dev/null) "$f" >/dev/null 2>&1; then
    echo "PASS: $rel"
    return 0
  else
    echo "FAIL: $rel — not in canonical pretty form (jq . mismatch)"
    return 1
  fi
}

# ----------------------------------------------------------------
# Main: iterate over files and check each one.
# ----------------------------------------------------------------
if [ -z "$files" ]; then
  echo "No version-controlled JSON files found."
  exit 0
fi

total=0
passed=0
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  total=$((total + 1))
  if check_file "$ROOT/$rel"; then
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
