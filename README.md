# jq-stable-recipes

Tested jq recipes that produce stable JSON from non-deterministic tool output.

## Problem

Tools like `cargo build --message-format json` and `cargo-mutants outcomes.json` emit JSON that varies between runs: parallel execution reorders messages, build artifacts carry fresh hashes, arrays come in arbitrary order, runtime timing shifts. These filters normalize such output into stable, canonicalized JSON — the raw material a fingerprint is made of. Nothing in this repository does fingerprinting itself: the filters only canonicalize, and turning the result into a fingerprint or cache key (e.g. `| sha256sum`) is a step you add in your own pipeline. Use the stable output for caching, change detection, or reproducible builds.

## Usage

```
cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/normalize.jq

# Or for a minimal stable projection:
cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/identity.jq

# For cargo-mutants outcomes (single JSON object, not NDJSON):
jq -f filters/cargo-mutants/normalize.jq target/mutants/outcomes.json
```

## What the filters do

Every filter family ships a `normalize.jq` (stable JSON, all fields preserved)
and an `identity.jq` (minimal stable projection, volatile fields dropped). See
[`filters/simple/`](filters/simple/) for a tiny teaching example:

```
$ echo '{"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}' \
    | jq -c -f filters/simple/normalize.jq
# before: {"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}
# after:  {"name":"demo","score":42,"tags":["a","m","z"],"version":3}

$ echo '{"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}' \
    | jq -c -f filters/simple/identity.jq
# before: {"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}
# after:  {"name":"demo","tags":["a","m","z"],"version":3}
```

`normalize.jq` sorts object keys and arrays — inputs that represent the same
data always produce identical output. `identity.jq` also drops volatile fields
(`score`), keeping only what identifies the object. Neither filter hashes
anything: the output is canonical JSON, and fingerprinting it (e.g. with
`sha256sum`) is up to the caller.

## Filters

- [**cargo-build**](filters/cargo-build/) — Two filters for `cargo build --message-format json`:
  - [`normalize.jq`](filters/cargo-build/) — Full normalization: stable JSON, all fields preserved
  - [`identity.jq`](filters/cargo-build/) — Minimal stable projection: only fields needed to identify if two builds are the same
- [**cargo-mutants**](filters/cargo-mutants/) — Two filters for `cargo-mutants outcomes.json`:
  - [`normalize.jq`](filters/cargo-mutants/) — Full normalization: stable JSON, all meaningful fields preserved
  - [`identity.jq`](filters/cargo-mutants/) — Minimal stable projection: mutation counts, scenario names, phase pass/fail
- [**cargo-audit**](filters/cargo-audit/) — Two filters for `cargo audit --json`:
  - [`normalize.jq`](filters/cargo-audit/) — Full normalization: stable JSON, all fields preserved
  - [`identity.jq`](filters/cargo-audit/) — Minimal stable projection: vulnerability list, crate + advisory IDs
- [**cargo-clippy**](filters/cargo-clippy/) — Two filters for `cargo clippy --message-format json`:
  - [`normalize.jq`](filters/cargo-clippy/) — Full normalization: stable JSON, all fields preserved
  - [`identity.jq`](filters/cargo-clippy/) — Minimal stable projection: lints by package, code, and location
- [**cargo-deny**](filters/cargo-deny/) — Two filters for `cargo deny check --format json` (diagnostic events on stderr):
  - [`normalize.jq`](filters/cargo-deny/) — Full normalization: stable JSON, all fields preserved
  - [`identity.jq`](filters/cargo-deny/) — Minimal stable projection: advisories/bans/licenses by crate
- [**cargo-geiger**](filters/cargo-geiger/) — Two filters for `cargo geiger --output-format Json`:
  - [`normalize.jq`](filters/cargo-geiger/) — Full normalization: stable JSON, all unsafety metrics preserved
  - [`identity.jq`](filters/cargo-geiger/) — Minimal stable projection: per-crate unsafe counts, forbids_unsafe flag
- [**simple**](filters/simple/) — Teaching showcase, not a real tool: demonstrates `normalize` vs `identity` on one tiny JSON object:
  - [`normalize.jq`](filters/simple/) — Sorts object keys and arrays; all fields preserved
  - [`identity.jq`](filters/simple/) — Drops volatile fields (`score`); keeps only identifying fields

Each filter directory has its own README with detailed documentation and known limitations.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for filter header conventions, design rules, the env combination coverage check, and how to add a new filter. Commit messages follow the [Conventional Commits](https://www.conventionalcommits.org/) specification.

## License

MIT
