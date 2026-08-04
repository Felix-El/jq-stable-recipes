# SPDX-License-Identifier: MIT
#
# Generates stable output from cargo deny --format json NDJSON event stream by
# sorting the variable parts of the JSON fragment: diagnostics, log events,
# internal arrays (graphs, labels, notes), and object keys. Keeps all event
# types: diagnostic events, log events (sorted by timestamp), and the summary
# event.
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
+ (map(select(.type == "log"))
  | sort_by(.fields.timestamp // ""))
+ map(select(.type == "summary"))
| sort_object_keys
