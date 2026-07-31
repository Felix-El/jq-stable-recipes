# cargo-audit

Two filters for [`cargo-audit`](https://github.com/rustsec/rustsec/tree/main/cargo-audit) `--json` output, at different levels of projection.

## Determinism

Both filters are deterministic under filter-specific conditions: two runs produce byte-identical output iff they audited the same lockfile against the same advisory database. The database-metadata fields that change on every update (`database.last-commit`, `database.last-updated`) are dropped. `package.checksum` (the crates.io SHA-256 of the exact crate file) is a content hash of the audited input and is **preserved** by both filters — two lockfiles referencing different crate contents would differ here.

## stable.jq

Full normalization: generates stable, order-independent output from `cargo audit --json` by sorting the variable parts of the JSON — vulnerability and warning lists, package dependency arrays, advisory sub-arrays, and object keys. Drops non-deterministic database metadata that resists ordering-only treatment. All semantically meaningful fields are preserved.

```
cargo audit --json 2>/dev/null | jq -s -f filters/cargo-audit/stable.jq

# Or from a saved file:
jq -s -f filters/cargo-audit/stable.jq cargo-audit.json
```

### What stable.jq Does

| Variation | Treatment |
|---|---|
| `database.last-commit` | Dropped (changes on every DB update) |
| `database.last-updated` | Dropped (changes on every DB update) |
| Vulnerability list order | Sort by `advisory.id` |
| Warning category array order | Sort by `advisory.id` within each kind |
| `package.dependencies` order | Sort by `name` |
| `advisory.aliases` order | Sort alphabetically |
| `advisory.categories` order | Sort alphabetically |
| `advisory.keywords` order | Sort alphabetically |
| `advisory.related` order | Sort alphabetically |
| `advisory.references` order | Sort alphabetically |
| `affected.os` / `affected.arch` order | Sort alphabetically |
| `affected.functions` version ranges | Sort per function |
| `settings.informational_warnings` order | Sort alphabetically |
| Object key ordering | Recursively sort keys alphabetically |

### Limitations

- `database.advisory-count` is preserved and may change when the advisory database is updated without new findings in the project.
- `settings.severity`, `settings.ignore`, `settings.target_arch`, and `settings.target_os` reflect the invocation flags, not the project state, so a different invocation on the same lockfile may produce different output.
- For a minimal stable projection, use `deterministic.jq`.

## deterministic.jq

Deterministic projection. Does what `stable.jq` does, and additionally drops undeterministic data (database metadata, invocation settings, advisory prose): only the fields needed to determine if two audit runs found the same vulnerabilities remain — lockfile dependency count, vulnerability found/count flags, and per-vulnerability advisory id, cvss score, package name+version, checksum, and affected os list. Suitable as a stable cache key or piped to `sha256sum`.

```
cargo audit --json 2>/dev/null | jq -s -f filters/cargo-audit/deterministic.jq

# Or from a saved file:
jq -s -f filters/cargo-audit/deterministic.jq cargo-audit.json
```

### Projected Fields

| Category | Kept fields |
|---|---|
| Lockfile | `dependency-count` |
| Vulnerabilities summary | `found`, `count` |
| Per vulnerability | `advisory.id`, `advisory.cvss`, `package.name`, `package.version`, `package.checksum`, `affected.os` |

### What deterministic.jq Drops

| Field | Reason |
|---|---|
| `database.*` | DB metadata, not a result |
| `settings.*` | Invocation flags, not findings |
| `advisory.title`, `advisory.description` | Prose, not identity |
| `advisory.aliases`, `advisory.categories`, `advisory.keywords` | Informational, not identity |
| `advisory.date`, `advisory.url`, `advisory.license` | Metadata, not identity |
| `advisory.references`, `advisory.related` | Informational, not identity |
| `versions.patched`, `versions.unaffected` | Advisory metadata, not finding |
| `affected.arch`, `affected.functions` | Fine-grained detail; `affected.os` covers platform identity |
| `package.source`, `package.dependencies` | Registry detail, not identity |
| `package.replace` | Rarely set, not identity |
| `warnings` | Informational only; not security vulnerabilities |

### Limitations

- Warnings (unmaintained, unsound, notice) are excluded by design. They do not constitute vulnerabilities and their presence is controlled by invocation flags.
- `affected.arch` is excluded; two runs on different CPU architectures targeting the same OS may appear identical.
