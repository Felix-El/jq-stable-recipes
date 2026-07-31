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
- [**cargo-audit**](filters/cargo-audit/) — Two filters for `cargo audit --json`:
  - [`normalize.jq`](filters/cargo-audit/) — Full normalization: stable JSON, all fields preserved
  - [`identity.jq`](filters/cargo-audit/) — Minimal fingerprint: vulnerability list, crate + advisory IDs
- [**cargo-clippy**](filters/cargo-clippy/) — Two filters for `cargo clippy --message-format json`:
  - [`normalize.jq`](filters/cargo-clippy/) — Full normalization: stable JSON, all fields preserved
  - [`identity.jq`](filters/cargo-clippy/) — Minimal fingerprint: lints by package, code, and location
- [**cargo-deny**](filters/cargo-deny/) — Two filters for `cargo deny check --format json` (diagnostic events on stderr):
  - [`normalize.jq`](filters/cargo-deny/) — Full normalization: stable JSON, all fields preserved
  - [`identity.jq`](filters/cargo-deny/) — Minimal fingerprint: advisories/bans/licenses by crate
- [**cargo-geiger**](filters/cargo-geiger/) — Two filters for `cargo geiger --output-format Json`:
  - [`normalize.jq`](filters/cargo-geiger/) — Full normalization: stable JSON, all unsafety metrics preserved
  - [`identity.jq`](filters/cargo-geiger/) — Minimal fingerprint: per-crate unsafe counts, forbids_unsafe flag

Each filter directory has its own README with detailed documentation and known limitations.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for filter header conventions, design rules, the env combination coverage check, and how to add a new filter. Commit messages follow the [Conventional Commits](https://www.conventionalcommits.org/) specification.

## License

MIT
