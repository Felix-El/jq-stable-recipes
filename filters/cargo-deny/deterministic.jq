# SPDX-License-Identifier: MIT
#
# Generates deterministic output from cargo deny --format json event stream by
# additionally dropping undeterministic data: log events, graph parent chains,
# label spans, and advisory prose. Projects to the minimum fields needed to
# determine if two deny runs are semantically identical: per-diagnostic code,
# severity, message, primary crate identity, and advisory ID when present;
# summary check-category counts.
def sort_object_keys:
  walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end);

def project_diagnostic:
  (if (.graphs | type) == "array" then .graphs | sort_by(.Krate.name, .Krate.version) else [] end) as $g
  | { type: "diagnostic",
      code: .code,
      severity: .severity,
      message: .message,
      crate: (($g[0].Krate.name // "") + "@" + ($g[0].Krate.version // ""))
    }
  + if has("advisory") then {advisory_id: .advisory.id} else {} end;

(map(
    select(.type == "diagnostic")
    | .fields | project_diagnostic
  )
  | sort_by([.code, .severity, .message, .crate]))
+ map(
    select(.type == "summary")
    | {type: "summary"} + .fields
  )
| sort_object_keys
