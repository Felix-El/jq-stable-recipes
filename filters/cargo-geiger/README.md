# cargo-geiger

Two filters for [`cargo-geiger`](https://github.com/rust-secure-code/cargo-geiger) `--output-format Json` output, at different levels of projection.

## stable.jq

Full normalization: generates stable, order-independent output from unsafe-code audit output by sorting the variable parts of the JSON — packages by name then version, dependency arrays within each package, and object keys. All unsafety metrics and the `forbids_unsafe` flag are preserved unchanged.

```
cargo geiger --output-format Json | jq -f filters/cargo-geiger/stable.jq
```

The filter also accepts slurped input (e.g. from a saved file):

```
jq -s -f filters/cargo-geiger/stable.jq geiger.json
```

### Stripping machine-specific paths

The workspace-root package (the one you ran `cargo geiger` on) has a `source.Path` of the form `file:///absolute/path/to/your-crate%23version`. This path is machine-specific and breaks cross-machine reproducibility. Set `STRIP_PATHS=1` to reduce all `file://` and absolute-path strings to their basename:

```
STRIP_PATHS=1 cargo geiger --output-format Json | jq -f filters/cargo-geiger/stable.jq
```

Without `STRIP_PATHS=1` the raw `file://` URL is preserved — the output is stable for repeated runs on the **same** machine but not portable across different CI runners or developer machines.

### Limitations

- **`packages_without_metrics` and `used_but_not_scanned_files`** — both arrays are sorted by string representation as a safe fallback; in practice they are empty for fully-scannable workspaces.
- **All fields preserved** — including dependency edges and source registry metadata. For a minimal stable projection, use `deterministic.jq`.

## deterministic.jq

Deterministic projection. Does what `stable.jq` does, and additionally drops undeterministic data (dependency edges, source registry metadata, exact unscanned-file lists): per package, only name, version, `forbids_unsafe`, and the complete unsafety counts (used and unused, all five categories: functions, exprs, item_impls, item_traits, methods) remain. Unscanned-file detail is collapsed to counts. Suitable as a stable cache key or piped to `sha256sum`.

```
cargo geiger --output-format Json | jq -f filters/cargo-geiger/deterministic.jq
```

With slurped input:

```
jq -s -f filters/cargo-geiger/deterministic.jq geiger.json
```

### Projected Fields

| Category | Kept fields |
|---|---|
| Per package | `name`, `version`, `forbids_unsafe`, `used` (all counters), `unused` (all counters) |
| Scan coverage | `packages_without_metrics_count`, `used_but_not_scanned_files_count` |

### Limitations

- **No dependency edges** — `dependencies`, `dev_dependencies`, `build_dependencies` are dropped by design.
- **No source registry metadata** — registry name and URL are dropped; identity depends on name+version only.
- **Unscanned detail collapsed** — exact lists of unscanned packages/files are replaced by counts.

## What stable.jq Does

| Variation | Treatment |
|---|---|
| Package order | Sort by `[name, version]` |
| Dependency order | Sort by `[name, version]` within each package |
| Object key ordering | Recursively sort keys alphabetically |
| `packages_without_metrics` order | Sort by string representation |
| `used_but_not_scanned_files` order | Sort by string representation |
| `source.Path` file URLs / absolute paths | Strip to basename when `STRIP_PATHS=1`; preserved otherwise |

## What deterministic.jq Drops

| Field | Reason |
|---|---|
| `package.dependencies` / `dev_dependencies` / `build_dependencies` | Structural metadata, not unsafe-code signal |
| `package.id.source` | Registry URL, not part of package identity |
| Exact `packages_without_metrics` entries | Replaced by count |
| Exact `used_but_not_scanned_files` entries | Replaced by count |
