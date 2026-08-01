# SPDX-License-Identifier: MIT
#
# Generates stable output from cargo-mutants mutants.json by sorting the
# mutant array by name (the unique human-readable identifier) and sorting
# object keys recursively. All fields are preserved, including the
# per-mutant unified diff. mutants.json paths are tree-relative, so
# STRIP_PATHS only matters if a future version emits absolute paths.
#
# Works with both raw and -s (slurp) input: bare array or [array].
#
# @env:STRIP_PATHS?:1

if type == "array" and length == 1 and (.[0] | type) == "array" then .[0] else . end
| sort_by(.name)
| walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end)
| if (env.STRIP_PATHS // "") == "1" then
    walk(if type == "string" and startswith("/") then sub(".*/"; "") else . end)
  else . end
