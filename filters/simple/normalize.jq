# SPDX-License-Identifier: MIT
#
# Simple showcase: turns a tiny JSON object into stable form — recursively sorts
# object keys and sorts every array. All fields are preserved; only ordering is
# canonicalized.

if type == "array" then .[0] else . end
| walk(if type == "object" then to_entries | sort_by(.key) | from_entries elif type == "array" then sort else . end)
