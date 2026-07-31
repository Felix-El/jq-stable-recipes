# cargo-build

Two filters for `cargo build --message-format json` output, at different levels of projection.

## normalize.jq

Full normalization: generates stable output from non-deterministic build output by sorting the variable parts of the JSON — message order, array order, and object keys. Keeps all fields, and additionally normalizes hashes and removes caching noise.

```
cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/normalize.jq
```

### Stripping machine-specific paths

Set `STRIP_PATHS=1` to erase all absolute paths to just the filename:

```
STRIP_PATHS=1 cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/normalize.jq
```

### Limitations

- **Machine-specific paths are preserved** without `STRIP_PATHS=1`. The output is stable across rebuilds on the same machine, not across different machines or CI runners.
- **Procedural macro / build script stdout** outside cargo's JSON framework is silently skipped.
- **Compiler diagnostics** are normalized for key order only — content is preserved verbatim.

## identity.jq

Deterministic projection. Does what `normalize.jq` does, and additionally drops undeterministic data: each message is projected down to only the fields needed to determine if two builds are semantically identical. Suitable as a stable build key or piped to `sha256sum`.

```
cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/identity.jq
```

With path stripping:

```
STRIP_PATHS=1 cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/identity.jq
```

### Projected Fields

| Message type | Kept fields |
|---|---|
| `compiler-artifact` | `package`, `target`, `kind`, `features` |
| `compiler-message` | `package`, `target`, `level`, `code` |
| `build-script-executed` | `package`, `cfgs`, `linked_libs`, `linked_paths` |
| `build-finished` | `success` |

### Limitations

- **No path information** — paths are excluded by design.
- **No diagnostic details** — only the error/warning code is kept, not the message text or source location.
- **Profile metadata is dropped** — `opt_level`, `debuginfo`, etc. reflect project config, not build output.

## What Both Normalize

| Variation | Treatment |
|---|---|
| Message line order (parallel compilation) | Sort by `(package_id, reason)` |
| Artifact hash suffixes (`-be9f3faac0a26ef0`) | Replace with `-HASH` in filenames, `out_dir`, and `env` values |
| Array element order (`features`, `filenames`, `cfgs`, `env`, etc.) | Sort each array deterministically |
| `fresh` / `executable` fields | Remove (vary with caching state) |
| Object key ordering | Recursively sort keys alphabetically |
