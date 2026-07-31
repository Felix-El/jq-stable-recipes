# SPDX-License-Identifier: MIT
#
# Generates stable output from cargo-audit JSON by sorting the variable parts
# of the JSON fragment: vulnerability and warning lists, dependency arrays,
# advisory sub-arrays, and object keys. Drops non-deterministic database
# metadata (last-commit, last-updated) that resists ordering-only treatment.
# Sorts the vulnerability list and each warning category array by advisory.id;
# sorts package dependency arrays by name; sorts advisory sub-arrays (aliases,
# categories, keywords, related, references) and affected os/arch arrays;
# recursively sorts all object keys. All semantically meaningful fields kept.
#
# Works with both raw and -s (slurp) input: single object or [object].

if type == "array" then .[0] else . end
| def sort_object_keys:
    walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end);

def norm_entry:
  .package.dependencies |= sort_by(.name)
  | .advisory.aliases    |= sort
  | .advisory.categories |= sort
  | .advisory.keywords   |= sort
  | .advisory.related    |= sort
  | .advisory.references |= sort
  | if .affected != null then
      .affected.arch |= sort
      | .affected.os |= sort
      | .affected.functions |= (to_entries | map(.value |= sort) | from_entries)
    else . end;

{
  database: {
    "advisory-count": .database["advisory-count"]
  },
  lockfile,
  settings: (
    .settings
    | .target_arch            |= sort
    | .target_os              |= sort
    | .ignore                 |= sort
    | .informational_warnings |= sort
  ),
  vulnerabilities: {
    found: .vulnerabilities.found,
    count: .vulnerabilities.count,
    list: (
      .vulnerabilities.list
      | sort_by(.advisory.id)
      | map(norm_entry)
    )
  },
  warnings: (
    .warnings
    | to_entries
    | map(.value |= (sort_by(.advisory.id) | map(norm_entry)))
    | from_entries
  )
}
| sort_object_keys
