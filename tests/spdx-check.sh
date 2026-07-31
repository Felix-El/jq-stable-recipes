#!/usr/bin/env bash
# SPDX license header check: every filter (.jq) file under filters/ must
# start with an SPDX license tag as the first line of its header comment,
# followed by a blank line.
#
# Exits 1 when any filter violates the convention.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILTER_DIR="$ROOT/filters"

fail=0
while IFS= read -r -d '' file; do
  rel="${file#"$ROOT"/}"
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
done < <(find "$FILTER_DIR" -name '*.jq' -type f -print0)

if [ "$fail" -eq 0 ]; then
  echo "PASS: all filter headers carry an SPDX license tag"
fi
exit $fail
