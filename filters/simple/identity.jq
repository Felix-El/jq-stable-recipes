# SPDX-License-Identifier: MIT
#
# Simple showcase: minimal fingerprint of a tiny JSON object. Drops volatile
# fields (score) and keeps only what identifies the object: name, version, and
# sorted tags.

if type == "array" then .[0] else . end
| {name, version, tags: (.tags | sort)}
| walk(if type == "object" then to_entries | sort_by(.key) | from_entries elif type == "array" then sort else . end)
