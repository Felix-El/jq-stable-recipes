# SPDX-License-Identifier: MIT
#
# Normalizes cargo build --message-format json NDJSON into stable,
# order-independent JSON. Handles message reordering from parallel
# compilation, hash suffixes in artifact filenames, array ordering,
# and caching state. All fields are preserved.
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
  | if (.filenames | type) == "array" then
      .filenames |= (map(gsub("-[0-9a-f]{16}"; "-HASH")) | sort)
    else . end
  | sort_array("features")
  | sort_array("linked_libs")
  | sort_array("linked_paths")
  | sort_array("cfgs")
  | if (.env | type) == "array" then .env |= (map(map(if type == "string" then gsub("-[0-9a-f]{16}"; "-HASH") else . end)) | sort_by(.[0])) else . end
  | if has("out_dir") then .out_dir |= gsub("-[0-9a-f]{16}"; "-HASH") else . end
  | normalize_target;

def sort_object_keys:
  walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end);

map(select(type == "object" and has("reason")) | normalize_message)
| sort_by(.package_id // "", .reason // "")
| sort_object_keys
| if (env.STRIP_PATHS // "") == "1" then
    walk(if type == "string" and startswith("/") then sub(".*/"; "") else . end)
  else . end
