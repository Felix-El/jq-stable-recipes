# SPDX-License-Identifier: MIT
#
# Generic fallback: schema-agnostic stable filter for unknown JSON shapes.
# Recursively sorts object keys — the one canonicalization that is safe for
# every possible schema, since JSON object keys are unordered by definition,
# while array order and every value are meaningful and preserved as emitted.
#
# This is deliberately the weakest filter in the repository. Without a schema
# there is no way to know which fields are run-to-run noise, so nothing is
# dropped and no deterministic filter is possible either. jq's own canonical
# number serialization and duplicate-key handling apply for free — see the
# README.

if type == "array" and length == 1 then .[0] else . end
| walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end)
