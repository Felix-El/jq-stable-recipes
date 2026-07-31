# SPDX-License-Identifier: MIT
#
# Generates stable output from cargo-geiger --output-format Json by sorting
# the variable parts of the JSON fragment: packages by name then version,
# dependency arrays within each package, and object keys. All unsafety metrics
# (used/unused per category) and the forbids_unsafe flag are preserved
# unchanged.
#
# Works with both raw and -s (slurp) input: single object or [object].
#
# @env:STRIP_PATHS?:1

if type == "array" then .[0] else . end
| def sort_object_keys:
    walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end);

def sort_deps:
  sort_by([.name, .version]);

{
  packages: (
    .packages
    | sort_by([.package.id.name, .package.id.version])
    | map(
        .package |= (
          .dependencies |= sort_deps
          | .dev_dependencies |= sort_deps
          | .build_dependencies |= sort_deps
        )
      )
  ),
  packages_without_metrics: (
    .packages_without_metrics | sort_by(tostring)
  ),
  used_but_not_scanned_files: (
    .used_but_not_scanned_files | sort_by(tostring)
  )
}
| sort_object_keys
| if (env.STRIP_PATHS // "") == "1" then
    walk(if type == "string" and (startswith("/") or startswith("file://"))
         then sub(".*/"; "") else . end)
  else . end
