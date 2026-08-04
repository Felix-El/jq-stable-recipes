# SPDX-License-Identifier: MIT
#
# Generates stable output from cargo clippy --message-format json NDJSON by
# sorting the variable parts of the JSON fragment: message order, span order,
# array order, and object keys. All fields are preserved.
#
# Determinism contract: two runs are byte-identical iff they were built with
# the same toolchain (rustc/clippy version, target), the same feature set,
# profile, and RUSTFLAGS, and the same dependency graph. Artifact hash suffixes
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

def normalize_span:
  if (.text | type) == "array" then .text |= sort_by(.text) else . end;

def normalize_spans:
  if (.spans | type) == "array" then
    .spans |= (map(normalize_span) | sort_by(.file_name // "", (.line_start // 0), (.column_start // 0)))
  else . end;

def normalize_children:
  if (.children | type) == "array" then
    .children |= (
      map(normalize_spans | normalize_children)
      | sort_by(.level // "", .message // "")
    )
  else . end;

def normalize_compiler_message:
  if .reason == "compiler-message" then
    .message |= (
      normalize_spans
      | normalize_children
    )
  else . end;

def normalize_message:
  if (.filenames | type) == "array" then .filenames |= sort else . end
  | sort_array("features")
  | sort_array("linked_libs")
  | sort_array("linked_paths")
  | sort_array("cfgs")
  | if (.env | type) == "array" then .env |= (sort_by(.[0])) else . end
  | normalize_target
  | normalize_compiler_message;

def primary_span:
  ((.message.spans // []) | map(select(.is_primary)) | .[0]);

def sort_key:
  [ .package_id // "",
    .reason // "",
    (.target.name // ""),
    ((.target.kind // []) | sort | .[0] // ""),
    (.message.code.code // ""),
    (primary_span | .file_name // ""),
    (primary_span | .line_start // 0),
    (primary_span | .column_start // 0),
    (.message.message // "") ];

def sort_object_keys:
  walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end);

map(select(type == "object" and has("reason")) | normalize_message)
| sort_by(sort_key)
| sort_object_keys
| if (env.STRIP_PATHS // "") == "1" then
    walk(if type == "string" and startswith("/") then sub(".*/"; "") else . end)
  else . end
