# SPDX-License-Identifier: MIT
#
# Generates deterministic output from cargo-geiger --output-format Json by
# additionally dropping undeterministic data: dependency edges (structural
# metadata, not scan results) and exact unscanned-file lists. Projects to the
# minimum fields needed to determine if two geiger runs are semantically
# identical: per-package name, version, forbids_unsafe flag, and all unsafety
# counts (used and unused, all five categories).
#
# Works with both raw and -s (slurp) input: single object or [object].

if type == "array" then .[0] else . end
| {
    packages: (
      .packages
      | sort_by([.package.id.name, .package.id.version])
      | map({
          name: .package.id.name,
          version: .package.id.version,
          forbids_unsafe: .unsafety.forbids_unsafe,
          used: .unsafety.used,
          unused: .unsafety.unused
        })
    ),
    packages_without_metrics_count: (.packages_without_metrics | length),
    used_but_not_scanned_files_count: (.used_but_not_scanned_files | length)
  }
| walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end)
