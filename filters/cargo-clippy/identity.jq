# SPDX-License-Identifier: MIT
#
# Projects cargo clippy --message-format json messages down to the
# minimum fields needed to determine if two clippy runs are semantically
# identical: package identity, lint codes and primary source locations,
# target info, build script configuration, and build result. Drops
# diagnostic text, span details, profile metadata, artifact paths, and
# all rendering noise.
#
# @env:STRIP_PATHS?:1
def sort_array($key):
  if (.[$key] | type) == "array" then .[$key] |= sort else . end;

def normalize_target:
  if (.target | type) == "object" then
    .target |= (
      sort_array("kind")
      | sort_array("crate_types")
    )
  else . end;

def normalize_message:
  del(.fresh, .executable)
  | sort_array("features")
  | sort_array("linked_libs")
  | sort_array("linked_paths")
  | sort_array("cfgs")
  | normalize_target;

def primary_span:
  ((.message.spans // []) | map(select(.is_primary)) | .[0]);

def project_message:
  if .reason == "compiler-artifact" then
    { reason: "artifact",
      package: .package_id,
      target: .target.name,
      kind: .target.kind,
      features: .features }
  elif .reason == "compiler-message" then
    { reason: "diagnostic",
      package: .package_id,
      target: .target.name,
      level: .message.level,
      code: .message.code.code,
      file: (primary_span | .file_name // null),
      line: (primary_span | .line_start // null) }
  elif .reason == "build-script-executed" then
    { reason: "build_script",
      package: .package_id,
      cfgs: .cfgs,
      linked_libs: .linked_libs,
      linked_paths: .linked_paths }
  elif .reason == "build-finished" then
    { reason: "result", success: .success }
  else .
  end;

def sort_object_keys:
  walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end);

map(select(type == "object" and has("reason")) | normalize_message | project_message)
| sort_by(.package // "", .reason // "", .target // "", .code // "", .file // "", (.line // 0))
| sort_object_keys
| if (env.STRIP_PATHS // "") == "1" then
    walk(if type == "string" and startswith("/") then sub(".*/"; "") else . end)
  else . end
