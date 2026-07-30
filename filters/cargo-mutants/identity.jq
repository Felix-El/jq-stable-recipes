# Projects cargo-mutants outcomes.json down to the minimum fields
# needed to determine if two mutation test runs are semantically
# identical: mutation counts, scenario names, per-scenario summary
# statuses, and phase-level pass/fail — no timing, paths, or
# environment-specific data.
#
# Works with both raw and -s (slurp) input: single object or [object].
#
# @env:STRIP_PATHS?:1

if type == "array" then .[0] else . end
| {
  total_mutants,
  missed,
  caught,
  timeout,
  unviable,
  success,
  outcomes: (.outcomes | sort_by(.scenario) | map({
    scenario,
    summary,
    phase_results: (.phase_results | sort_by(.phase) | map({
      phase,
      process_status
    }))
  }))
}
| walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end)
| if (env.STRIP_PATHS // "") == "1" then
    walk(if type == "string" and startswith("/") then sub(".*/"; "") else . end)
  else . end
