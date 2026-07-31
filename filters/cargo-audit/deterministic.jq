# SPDX-License-Identifier: MIT
#
# Generates deterministic output from cargo-audit JSON by additionally dropping
# undeterministic data: database metadata, timing, descriptions, and warning
# details. Projects to the minimum fields needed to determine whether two audit
# runs are semantically identical: lockfile dependency count, vulnerability
# found/count, and per-vulnerability advisory id, cvss, package name+version,
# checksum, and affected os list.
#
# Determinism contract: two runs are byte-identical iff they audited the same
# lockfile against the same advisory database. package.checksum (the crates.io
# SHA-256 of the exact crate file) is a content hash and is therefore
# preserved, not dropped.
#
# Works with both raw and -s (slurp) input: single object or [object].

if type == "array" then .[0] else . end
| {
    lockfile: {
      "dependency-count": .lockfile["dependency-count"]
    },
    vulnerabilities: {
      found: .vulnerabilities.found,
      count: .vulnerabilities.count,
      list: (
        .vulnerabilities.list
        | sort_by(.advisory.id)
        | map({
            advisory: {
              id:   .advisory.id,
              cvss: .advisory.cvss
            },
            affected: {
              os: ((.affected.os // []) | sort)
            },
            package: {
              name:     .package.name,
              version:  .package.version,
              checksum: .package.checksum
            }
          })
      )
    }
  }
| walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end)
