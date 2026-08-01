# SPDX-License-Identifier: MIT
#
# Generates deterministic output from cargo-mutants mutants.json by sorting
# the mutant array by name and dropping the regenerable per-mutant unified
# diff. Every identifying field is preserved — name, package, file, span,
# replacement, genre, and function — so two runs that generated the same
# mutants produce identical output. Suitable as a stable test key or piped
# to sha256sum.
#
# Works with both raw and -s (slurp) input: bare array or [array].
#
# @env:STRIP_PATHS?:1

if type == "array" and length == 1 and (.[0] | type) == "array" then .[0] else . end
| sort_by(.name)
| map(del(.diff))
| walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end)
| if (env.STRIP_PATHS // "") == "1" then
    walk(if type == "string" and startswith("/") then sub(".*/"; "") else . end)
  else . end
