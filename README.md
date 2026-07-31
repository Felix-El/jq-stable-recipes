# jq-stable-recipes

Tested jq recipes that produce stable JSON from non-deterministic tool output.

## Problem

Tools like `cargo build --message-format json` and `cargo-mutants outcomes.json` emit JSON that varies between runs: parallel execution reorders messages, build artifacts carry fresh hashes, arrays come in arbitrary order, runtime timing shifts. These filters normalize such output into a stable fingerprint — use it for caching, change detection, or reproducible builds.

## Usage

```
cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/normalize.jq

# Or for a minimal fingerprint:
cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/identity.jq

# For cargo-mutants outcomes (single JSON object, not NDJSON):
jq -f filters/cargo-mutants/normalize.jq target/mutants/outcomes.json
```

## Filters

- [**cargo-build**](filters/cargo-build/) — Two filters for `cargo build --message-format json`:
  - [`normalize.jq`](filters/cargo-build/) — Full normalization: stable JSON, all fields preserved
  - [`identity.jq`](filters/cargo-build/) — Minimal fingerprint: only fields needed to identify if two builds are the same
- [**cargo-mutants**](filters/cargo-mutants/) — Two filters for `cargo-mutants outcomes.json`:
  - [`normalize.jq`](filters/cargo-mutants/) — Full normalization: stable JSON, all meaningful fields preserved
  - [`identity.jq`](filters/cargo-mutants/) — Minimal fingerprint: mutation counts, scenario names, phase pass/fail

Each filter directory has its own README with detailed documentation and known limitations.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for filter header conventions, design rules, and how to add a new filter. Commit messages follow the [Conventional Commits](https://www.conventionalcommits.org/) specification.

## License

MIT
