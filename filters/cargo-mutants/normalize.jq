# Normalizes cargo-mutants outcomes.json into stable, order-independent
# JSON. Sorts outcomes and phase results for consistent ordering,
# optionally strips absolute paths to basenames. All fields preserved.
#
# Works with both raw and -s (slurp) input: single object or [object].
#
# @env:STRIP_PATHS?:1

if type == "array" then .[0] else . end
| def sort_object_keys:
    walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end);

{
  outcomes: (.outcomes | sort_by(.scenario) | map(
    .phase_results |= sort_by(.phase)
  )),
  total_mutants,
  missed,
  caught,
  timeout,
  unviable,
  success,
  start_time,
  end_time,
  cargo_mutants_version
}
| sort_object_keys
| if (env.STRIP_PATHS // "") == "1" then
    walk(if type == "string" and startswith("/") then sub(".*/"; "") else . end)
  else . end
