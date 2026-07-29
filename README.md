# jq-stable-recipes

Tested jq recipes that produce stable JSON from non-deterministic tool output.

## Problem

Tools like `cargo build --message-format json` emit JSON that varies between runs: parallel execution reorders messages, build artifacts carry fresh hashes, arrays come in arbitrary order. These filters normalize such output into a stable fingerprint — use it for caching, change detection, or reproducible builds.

## Usage

```
cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/cargo-build.jq
```

## Filters

- [**cargo-build**](filters/cargo-build/) — Normalizes `cargo build --message-format json` output (message order, hash suffixes, array order, `fresh`/`executable`, key order)

Each filter has its own README with detailed documentation and known limitations.

## Adding a Filter

Create a subdirectory in `filters/<name>/` with:
- `<name>.jq` — the filter
- `README.md` — documentation and limitations

Add test fixtures in `tests/fixtures/<name>/`, run `cd tests && bash run-tests.sh`, then add a link to `filters/<name>/` in the filter list above.

## License

MIT
