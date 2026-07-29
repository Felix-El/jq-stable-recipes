# cargo-build

Normalizes `cargo build --message-format json` output into a stable fingerprint, invariant under non-deterministic build variation.

## Usage

```
cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/cargo-build.jq
```

## What It Normalizes

| Variation | Treatment |
|---|---|
| Message line order (parallel compilation) | Sort by `(package_id, reason)` |
| Artifact hash suffixes (`-be9f3faac0a26ef0`) | Replace with `-HASH` in filenames, `out_dir`, and `env` values |
| Array element order (`features`, `filenames`, `cfgs`, `env`, etc.) | Sort each array deterministically |
| `fresh` / `executable` fields | Remove (vary with caching state) |
| Object key ordering | Recursively sort keys alphabetically |

## Limitations

- **Machine-specific paths are preserved.** Absolute paths like `manifest_path`, `src_path`, and the directory portions of `filenames` remain as-is. The fingerprint is stable across rebuilds on the **same machine**, not across different machines or CI runners.
- **Procedural macro / build script output** that writes to stdout outside cargo's JSON framework is silently skipped (lines not starting with `{}` are filtered out).
- **Compiler diagnostics** (`compiler-message`) are normalized for key order only — the diagnostic content (`message`, `spans`, `rendered`) is preserved verbatim.
