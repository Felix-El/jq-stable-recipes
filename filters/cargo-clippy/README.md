# cargo-clippy

Two filters for `cargo clippy --message-format json` output, at different levels of projection.

## Determinism

Both filters are deterministic under filter-specific conditions: two runs produce byte-identical output iff they were built with the same toolchain (rustc/clippy version, target), the same feature set, profile, and RUSTFLAGS, and the same dependency graph. Artifact hash suffixes (e.g. `-be9f3faac0a26ef0` in `libserde-…rlib`) are not random: they are a deterministic hash of exactly that build configuration (crate name/version/source, features, profile, target, rustc version, RUSTFLAGS, dependency graph), so they are **preserved**. Two builds that differ in any of those inputs legitimately produce different output — that difference is the point of a build fingerprint. A change in the rustc/clippy version or target triple is visible as a change in these suffixes.

## stable.jq

Full normalization: generates stable output from non-deterministic clippy output by sorting the variable parts of the JSON — message order, span order, array order, and object keys. Keeps all fields (except `message.rendered`), and additionally normalizes byte offsets and caching noise.

```
cargo clippy --message-format json 2>/dev/null | jq -s -f filters/cargo-clippy/stable.jq
```

### Stripping machine-specific paths

Set `STRIP_PATHS=1` to erase all absolute paths to just the filename:

```
STRIP_PATHS=1 cargo clippy --message-format json 2>/dev/null | jq -s -f filters/cargo-clippy/stable.jq
```

### What stable.jq does

- **Drops** `message.rendered`: contains ANSI color codes and machine-specific absolute paths that resist normalization.
- **Drops** `fresh` and `executable` fields: vary with caching state.
- **Drops** `byte_start` / `byte_end` from spans: byte offsets shift whenever preceding source changes.
- **Sorts** messages by `(package_id, reason, target.name, target.kind, lint code, file, line)`.
- **Sorts** spans by `(file_name, line_start, column_start)` and children by `(level, message)`.
- **Preserves** artifact hash suffixes (`-be9f3faac0a26ef0`) in `filenames`, `out_dir`, and `env` — they are a deterministic hash of the build configuration, see the Determinism section.
- **Sorts** all arrays: `features`, `kind`, `crate_types`, `cfgs`, `filenames`, span `text`, etc.
- **Sorts** all object keys recursively.

### Limitations

- **`message.rendered` is dropped** — the human-readable diagnostic text is lost; use the structured fields (`message.message`, `message.spans`, `message.children`) for diagnostic detail.
- **Machine-specific paths are preserved** without `STRIP_PATHS=1`. The output is stable across rebuilds on the same machine, not across different machines or CI runners.
- **Lint count depends on rustc/clippy version** — the set of lints fired may differ between toolchain versions even on the same code.

## deterministic.jq

Deterministic projection. Does what `stable.jq` does, and additionally drops undeterministic data (rendered diagnostics, byte offsets, paths): only the fields needed to determine if two clippy runs are semantically identical remain. Suitable as a stable cache key or piped to `sha256sum`.

```
cargo clippy --message-format json 2>/dev/null | jq -s -f filters/cargo-clippy/deterministic.jq
```

With path stripping:

```
STRIP_PATHS=1 cargo clippy --message-format json 2>/dev/null | jq -s -f filters/cargo-clippy/deterministic.jq
```

### Projected Fields

| Message type | Kept fields |
|---|---|
| `compiler-message` | `package`, `target`, `level`, `code`, `file` (primary span), `line` (primary span) |
| `compiler-artifact` | `package`, `target`, `kind`, `features` |
| `build-script-executed` | `package`, `cfgs`, `linked_libs`, `linked_paths` |
| `build-finished` | `success` |

### Limitations

- **No diagnostic detail** — only the lint code and primary source location are kept, not the message text, suggestions, or fix spans.
- **No path information beyond primary span** — secondary spans and expansion info are excluded by design.
- **Profile metadata is dropped** — `opt_level`, `debuginfo`, etc. reflect project config, not lint output.

## What Both Normalize

| Variation | Treatment |
|---|---|
| Message line order (parallel compilation) | Sort by `(package_id, reason, target.name, kind, code, file, line)` |
| Artifact hash suffixes (`-be9f3faac0a26ef0`) | Preserved (deterministic hash of build configuration, see Determinism) |
| `byte_start` / `byte_end` in spans | Dropped (depend on source layout; semantically irrelevant) |
| `message.rendered` | Dropped (color codes + absolute path rendering) |
| Array element order (`features`, `filenames`, `kind`, `cfgs`, spans, children, etc.) | Sort each array deterministically |
| `fresh` / `executable` fields | Remove (vary with caching state) |
| Object key ordering | Recursively sort keys alphabetically |
