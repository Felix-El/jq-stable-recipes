# SPDX-License-Identifier: MIT
#
# Generates deterministic output from cargo build --message-format json by
# additionally dropping undeterministic data. Projects each message down to
# the minimum fields needed to determine if two builds are semantically
# identical: package identity, target kind, features, diagnostic codes, build
# script configuration, and build result.
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

# Project to meaningful minimum per message type
def project_message:
  if .reason == "compiler-artifact" then
    {reason: "artifact", package: .package_id, target: .target.name, kind: .target.kind, features: .features}
  elif .reason == "compiler-message" then
    {reason: "diagnostic", package: .package_id, target: .target.name, level: .message.level, code: .message.code.code}
  elif .reason == "build-script-executed" then
    {reason: "build_script", package: .package_id, cfgs: .cfgs, linked_libs: .linked_libs, linked_paths: .linked_paths}
  elif .reason == "build-finished" then
    {reason: "result", success: .success}
  else .
  end;

def sort_object_keys:
  walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end);

map(select(type == "object" and has("reason")) | normalize_message | project_message)
| sort_by(.package // "", .reason // "", .target // "")
| sort_object_keys
| if (env.STRIP_PATHS // "") == "1" then
    walk(if type == "string" and startswith("/") then sub(".*/"; "") else . end)
  else . end
