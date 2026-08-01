# jq-stable-recipes

Tested jq recipes that produce stable JSON from non-deterministic tool output.

## Problem

Tools like `cargo build --message-format json` and `cargo-mutants outcomes.json` emit JSON that varies between runs: parallel execution reorders messages, arrays come in arbitrary order, runtime timing shifts. (Artifact hash suffixes like `-be9f3faac0a26ef0` are *not* run-to-run noise — they are deterministic hashes of the build configuration and are preserved, see the Determinism section in each cargo filter family's README.) These filters normalize such output into stable, canonicalized JSON — the raw material a fingerprint is made of. Nothing in this repository does fingerprinting itself: the filters only canonicalize, and turning the result into a fingerprint or cache key (e.g. `| sha256sum`) is a step you add in your own pipeline. For caching, change detection, or reproducible builds, use the `deterministic.jq` filters — they drop the volatile fields (timestamps, timing, machine-specific paths) that would otherwise make the fingerprint change on every run. `stable.jq` only guarantees identical output for identical input, so it is the wrong choice when a cache key must survive reruns.

## Usage

```
cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/stable.jq

# Or for a deterministic projection (volatile fields dropped):
cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/deterministic.jq

# For cargo-mutants outcomes (single JSON object, not NDJSON):
jq -f filters/cargo-mutants.outcomes/stable.jq target/mutants/outcomes.json

# For cargo-mutants mutants list (JSON array, not NDJSON):
jq -s -f filters/cargo-mutants.mutants/stable.jq target/mutants/mutants.json

# For unknown JSON schemas (schema-agnostic catch-all, stable only):
some-tool --output-format json | jq -s -f filters/generic/stable.jq
```

## What the filters do

Every filter family ships a `stable.jq` (stable output, all fields preserved)
and a `deterministic.jq` (deterministic output, undeterministic fields dropped) —
except [`generic`](filters/generic/), which has no schema to tell volatile
fields from meaningful ones and therefore ships only the stable filter. See
[`filters/simple/`](filters/simple/) for a tiny teaching example:

```
$ echo '{"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}' \
    | jq -c -f filters/simple/stable.jq
# before: {"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}
# after:  {"name":"demo","score":42,"tags":["a","m","z"],"version":3}

$ echo '{"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}' \
    | jq -c -f filters/simple/deterministic.jq
# before: {"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}
# after:  {"name":"demo","tags":["a","m","z"],"version":3}
```

**What "stable" means.** *Stable* output is a pure canonicalization: given
the *same input*, the output is byte-for-byte identical — key order, array
order, and message order are sorted so the same data always serializes the
same way. It is **not** a reproducibility guarantee: if the input itself
carries volatile data (timestamps, timing, machine-specific paths), stable
output preserves it, so two runs of the underlying tool at different times can
produce different stable output. The `deterministic.jq` filters exist for
exactly that case: they additionally drop the volatile fields, so two runs
that differ only in noise collapse to the same output. Use `deterministic.jq`
for cache keys, change detection, and reproducible builds; use `stable.jq`
when you want a faithful, order-canonicalized snapshot of a specific run's
output.

`stable.jq` generates *stable* output: it sorts the variable parts of a
JSON fragment — object keys and array order — so inputs that represent the
same data always produce identical output. `deterministic.jq` generates
*deterministic* output: it additionally removes undeterministic data (volatile
fields like `score`), keeping only what identifies the object. Neither filter
hashes anything: the output is canonical JSON, and fingerprinting it (e.g.
with `sha256sum`) is up to the caller.

## Why jq

Every recipe here is a jq program, and that choice buys canonicalization for
free. Any JSON that passes through jq — a recipe in this repo or a bare
`jq .` — is reserialized with jq's canonical rules:

- **Numbers** are reparsed and reprinted in their shortest round-trip form:
  `1.0` → `1`, `1e2` → `100`, `1.2300` → `1.23`.
- **Duplicate keys** collapse to the last occurrence, so an ambiguous
  `{"a": 1, "a": 2}` can never survive into a fingerprint.
- **Formatting** is uniform — two-space indentation from jq's pretty-printer.

These are properties of the jq runtime, not of any individual filter, so every
recipe inherits them — a core reason this repository is built on jq rather
than hand-rolled canonicalizers. The filters themselves add only the
schema-aware work: sorting the parts that vary between runs.

## Filters

- [**cargo-build**](filters/cargo-build/) — Two filters for `cargo build --message-format json`:
  - [`stable.jq`](filters/cargo-build/) — Stable output: sorts variable parts of the JSON; all fields preserved
  - [`deterministic.jq`](filters/cargo-build/) — Deterministic output: drops undeterministic data; keeps only what decides if two builds are the same
- [**cargo-mutants.outcomes**](filters/cargo-mutants.outcomes/) — Two filters for `cargo-mutants outcomes.json`:
  - [`stable.jq`](filters/cargo-mutants.outcomes/) — Stable output: sorts variable parts of the JSON; all meaningful fields preserved
  - [`deterministic.jq`](filters/cargo-mutants.outcomes/) — Deterministic output: drops undeterministic data; keeps mutation counts, scenario names, phase pass/fail
- [**cargo-mutants.mutants**](filters/cargo-mutants.mutants/) — Two filters for `cargo-mutants mutants.json` (the pre-test mutant list, also `cargo mutants --list --json`):
  - [`stable.jq`](filters/cargo-mutants.mutants/) — Stable output: sorts the mutant array by name, object keys recursively; all fields preserved
  - [`deterministic.jq`](filters/cargo-mutants.mutants/) — Deterministic output: drops the regenerable per-mutant `diff`; keeps every identifying field
- [**cargo-audit**](filters/cargo-audit/) — Two filters for `cargo audit --json`:
  - [`stable.jq`](filters/cargo-audit/) — Stable output: sorts variable parts of the JSON; all fields preserved
  - [`deterministic.jq`](filters/cargo-audit/) — Deterministic output: drops undeterministic data; keeps vulnerability list, crate + advisory IDs
- [**cargo-clippy**](filters/cargo-clippy/) — Two filters for `cargo clippy --message-format json`:
  - [`stable.jq`](filters/cargo-clippy/) — Stable output: sorts variable parts of the JSON; all fields preserved
  - [`deterministic.jq`](filters/cargo-clippy/) — Deterministic output: drops undeterministic data; keeps lints by package, code, and location
- [**cargo-deny**](filters/cargo-deny/) — Two filters for `cargo deny check --format json` (diagnostic events on stderr):
  - [`stable.jq`](filters/cargo-deny/) — Stable output: sorts variable parts of the JSON; all fields preserved
  - [`deterministic.jq`](filters/cargo-deny/) — Deterministic output: drops undeterministic data; keeps advisories/bans/licenses by crate
- [**cargo-geiger**](filters/cargo-geiger/) — Two filters for `cargo geiger --output-format Json`:
  - [`stable.jq`](filters/cargo-geiger/) — Stable output: sorts variable parts of the JSON; all unsafety metrics preserved
  - [`deterministic.jq`](filters/cargo-geiger/) — Deterministic output: drops undeterministic data; keeps per-crate unsafe counts, forbids_unsafe flag
- [**generic**](filters/generic/) — Schema-agnostic catch-all for unknown JSON shapes (stable only, no schema to know which fields are noise):
  - [`stable.jq`](filters/generic/) — Stable output: sorts object keys recursively; array order and every value preserved
- [**simple**](filters/simple/) — Teaching showcase, not a real tool: demonstrates `stable` vs `deterministic` on one tiny JSON object:
  - [`stable.jq`](filters/simple/) — Stable output: sorts variable parts (object keys, arrays); all fields preserved
  - [`deterministic.jq`](filters/simple/) — Deterministic output: drops undeterministic fields (`score`); keeps only identifying fields

Each filter directory has its own README with detailed documentation and known limitations.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for filter header conventions, design rules, the env combination coverage check, and how to add a new filter. Commit messages follow the [Conventional Commits](https://www.conventionalcommits.org/) specification.

## License

MIT
