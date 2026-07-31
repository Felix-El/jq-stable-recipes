# SPDX-License-Identifier: MIT
#
# Generates stable output from cargo build --message-format json NDJSON by
# sorting the variable parts of the JSON fragment: message order, array order,
# and object keys. Also normalizes caching state. All fields are preserved.
#
# Determinism contract: two runs are byte-identical iff they were built with
# the same toolchain (rustc version, target), the same feature set, profile,
# and RUSTFLAGS, and the same dependency graph. Artifact hash suffixes
# (e.g. -be9f3faac0a26ef0) encode exactly that configuration and are therefore
# preserved, not normalized.
#
# @env:STRIP_PATHS?:1
def sort_array($key):
  if (.[$key] | type) == "array" then .[$key] |= sort else . end;

def normalize_target:
  if (.target | type) == "object" then
    .target |= (
      sort_array("kind")
      | sort_array("crate_types")
      | sort_array("required-features")
    )
  else . end;

def normalize_message:
  del(.fresh, .executable)
  | if (.filenames | type) == "array" then .filenames |= sort else . end
  | sort_array("features")
  | sort_array("linked_libs")
  | sort_array("linked_paths")
  | sort_array("cfgs")
  | if (.env | type) == "array" then .env |= (sort_by(.[0])) else . end
  | normalize_target;

def sort_object_keys:
  walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end);

map(select(type == "object" and has("reason")) | normalize_message)
| sort_by(.package_id // "", .reason // "")
| sort_object_keys
| if (env.STRIP_PATHS // "") == "1" then
    walk(if type == "string" and startswith("/") then sub(".*/"; "") else . end)
  else . end
