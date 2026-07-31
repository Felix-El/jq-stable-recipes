# SPDX-License-Identifier: MIT
#
# Normalizes cargo deny --format json NDJSON event stream into stable,
# order-independent JSON. Drops log events (timestamps vary every run).
# Keeps diagnostic events with sorted internal arrays (graphs, labels,
# notes) and the summary event. Sorts diagnostics deterministically by
# (code, message, primary-crate name, version). Recursively sorts all
# object keys.
def sort_object_keys:
  walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end);

def normalize_graph_entry:
  if has("parents") then
    .parents |= (sort_by(.Krate.name, .Krate.version) | map(normalize_graph_entry))
  else .
  end;

def normalize_diagnostic_fields:
  if has("graphs") then
    .graphs |= (sort_by(.Krate.name, .Krate.version) | map(normalize_graph_entry))
  else . end
  | if has("labels") then .labels |= sort_by(.line, .column, .message) else . end
  | if has("notes") then .notes |= sort else . end;

(map(select(.type == "diagnostic") | .fields |= normalize_diagnostic_fields)
  | sort_by([
      .fields.code,
      .fields.message,
      (.fields.graphs[0].Krate.name // ""),
      (.fields.graphs[0].Krate.version // "")
    ]))
+ map(select(.type == "summary"))
| sort_object_keys
