# SPDX-License-Identifier: MIT
#
# Simple showcase: generates stable output from a tiny JSON object by sorting
# the variable parts of the JSON fragment — object keys and every array. All
# fields are preserved; only ordering is canonicalized.

if type == "array" then .[0] else . end
| walk(if type == "object" then to_entries | sort_by(.key) | from_entries elif type == "array" then sort else . end)
