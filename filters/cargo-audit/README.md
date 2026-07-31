# cargo-audit

Two filters for [`cargo-audit`](https://github.com/rustsec/rustsec/tree/main/cargo-audit) `--json` output, at different levels of projection.

## normalize.jq

Full normalization: produces stable, order-independent JSON from `cargo audit --json` output. Drops non-deterministic database metadata, sorts vulnerability and warning lists, sorts package dependency arrays, sorts advisory sub-arrays, and recursively sorts all object keys. All semantically meaningful fields are preserved.

```
cargo audit --json 2>/dev/null | jq -s -f filters/cargo-audit/normalize.jq

# Or from a saved file:
jq -s -f filters/cargo-audit/normalize.jq cargo-audit.json
```

### What normalize.jq Does

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
- For a minimal stable fingerprint, use `identity.jq`.

## identity.jq

Minimal fingerprint variant. Projects the output down to only the fields needed to determine if two audit runs found the same vulnerabilities: lockfile dependency count, vulnerability found/count flags, and per-vulnerability advisory id, cvss score, package name+version, and affected os list. Suitable as a stable cache key or piped to `sha256sum`.

```
cargo audit --json 2>/dev/null | jq -s -f filters/cargo-audit/identity.jq

# Or from a saved file:
jq -s -f filters/cargo-audit/identity.jq cargo-audit.json
```

### Projected Fields

| Category | Kept fields |
|---|---|
| Lockfile | `dependency-count` |
| Vulnerabilities summary | `found`, `count` |
| Per vulnerability | `advisory.id`, `advisory.cvss`, `package.name`, `package.version`, `affected.os` |

### What identity.jq Drops

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
| `package.source`, `package.checksum`, `package.dependencies` | Registry detail, not identity |
| `package.replace` | Rarely set, not identity |
| `warnings` | Informational only; not security vulnerabilities |

### Limitations

- Warnings (unmaintained, unsound, notice) are excluded by design. They do not constitute vulnerabilities and their presence is controlled by invocation flags.
- `affected.arch` is excluded; two runs on different CPU architectures targeting the same OS may appear identical.
