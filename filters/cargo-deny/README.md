# cargo-deny

Two filters for `cargo deny --format json check` output, at different levels of projection.

**Note:** `cargo deny` writes its JSON event stream to **stderr**; stdout is empty. Capture with `2>` redirection.

## normalize.jq

Full normalization: generates stable output from non-deterministic deny output by sorting the variable parts of the JSON — diagnostics, internal arrays (graphs, labels, notes), and object keys. Drops `log` events (timestamps vary every run). Keeps all `diagnostic` fields (code, severity, message, graphs, labels, notes) and the `summary` event. Sorts diagnostics deterministically by `(code, message, primary-crate name, version)`.

```
cargo deny --format json check all 2>deny.ndjson
jq -s -f filters/cargo-deny/normalize.jq deny.ndjson
```

### Limitations

- **No path stripping** — `cargo deny` output does not contain machine-specific absolute filesystem paths; registry URLs (e.g. `registry+https://github.com/rust-lang/crates.io-index`) are stable across machines.
- **Advisory prose is preserved** — the full advisory description and references are kept verbatim. The advisory ID and content are stable across runs for a given advisory database snapshot.
- **Log events dropped** — `log` events carry nanosecond-resolution timestamps and provide no semantic information; they are silently discarded.

## identity.jq

Deterministic projection. Does what `normalize.jq` does, and additionally drops undeterministic data (log events, dependency graph chains, source spans, advisory prose): only the fields needed to determine if two deny runs are semantically identical remain — `code`, `severity`, `message`, `crate` (primary crate as `name@version`), and `advisory_id` when present. Summary is projected to check-category error/warning counts. Suitable as a stable cache key or piped to `sha256sum`.

```
cargo deny --format json check all 2>deny.ndjson
jq -s -f filters/cargo-deny/identity.jq deny.ndjson
```

### Projected Fields

| Event type | Kept fields |
|---|---|
| `diagnostic` | `code`, `severity`, `message`, `crate` (name@version), `advisory_id` (advisory diagnostics only) |
| `summary` | `advisories`, `bans`, `licenses`, `sources` (error/warning counts per category) |

### Limitations

- **Graph parent chains dropped** — the dependency path leading to the flagged crate is excluded by design; only the primary crate identity is kept.
- **Label details dropped** — source file line/column spans and span text are excluded.
- **Advisory prose dropped** — the full advisory description, references, CVE aliases, and CVSS score are excluded; only the advisory ID is kept.

## What Both Normalize

| Variation | Treatment |
|---|---|
| Event line order (graph traversal order) | Sort diagnostics by `(code, message, primary-crate name, version)` |
| `log` events (nanosecond timestamps) | Drop entirely |
| `graphs` array order within a diagnostic | Sort by `(Krate.name, Krate.version)` recursively |
| `labels` array order within a diagnostic | Sort by `(line, column, message)` |
| `notes` array order | Sort lexicographically |
| `summary` position | Always last element |
| Object key ordering | Recursively sort keys alphabetically |
