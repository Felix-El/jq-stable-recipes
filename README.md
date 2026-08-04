# jq-stable-recipes

Tested jq recipes that produce stable JSON from non-deterministic tool output.

## The Problem

For caching, change detection, or reproducible builds we need **unambiguous**
output — syntactically and semantically.

Many tools emit JSON that is machine-readable, but semantically identical
runs of the same tool can emit slightly different JSON — entries in random
order due to parallelism, noise from timestamps, and so on.

That makes it hard to tell if anything *really* changed between runs.

## How We Address It

The `jq` tool is widely used to transform JSON, and even piping it through a
bare `jq .` normalizes output to some degree:

- **Numbers** are reparsed and reprinted in their shortest round-trip form:
  `1.0` → `1`, `1e2` → `100`, `1.2300` → `1.23`.
- **Duplicate keys** collapse to the last occurrence, so an ambiguous
  `{"a": 1, "a": 2}` can never survive into a fingerprint.
- **Formatting** is well-defined, no matter whether you choose minified or
  pretty-printed output.

This repository maintains **and tests** `jq` filter scripts for various
tools/schemas that take additional steps:

- a `stable.jq` filter sorts objects — and, where semantically possible, arrays —
  into a canonical order; schema and data are preserved
- a `deterministic.jq` filter additionally drops sources of non-determinism:
  timestamps, execution times, machine-specific paths

Pipe a tool-generated JSON through `jq` with the `deterministic.jq` script and
you get unambiguous, byte-for-byte repeatable output for semantically equal
tool runs.

You can then use that output as a fingerprint for the tool run, e.g. via `sha256sum`.

## Usage

We provide filters for many different tools. The usage pattern is always the same:
pipe raw JSON through `jq` with one of the scripts and get a result that orders
elements unambiguously (`stable.jq`) — or additionally drops undeterministic data
for reproducibility (`deterministic.jq`).

Here are some examples:

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

## Action at a Glance

Almost every filter family ships a `stable.jq` (stable output, all fields preserved)
and a `deterministic.jq` (deterministic output, undeterministic fields dropped).
Below we use [`filters/simple/`](filters/simple/) as a tiny teaching example
(no schema; it assumes all arrays have *set* semantics — order does not matter).

### Stability

**First run:**

```
$ echo '{"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}' \
    | jq -c -f filters/simple/stable.jq

{"name":"demo","score":42,"tags":["a","m","z"],"version":3}
```

As we can see, both object keys and array elements are in canonical order —
key order in JSON is never semantically meaningful, and the `simple` family
assumes arrays have *set* semantics.

**Second run:**

```
$ echo '{"name": "demo", "score": 42, "tags": ["m", "a", "z"], "version": 3}' \
    | jq -c -f filters/simple/stable.jq

{"name":"demo","score":42,"tags":["a","m","z"],"version":3}
```

The output is insensitive to the ordering of the input JSON.

### Determinism

The `simple` family assumes `score` is an undeterministic outcome, so it is
dropped for the resulting JSON to remain reproducible.

```
$ echo '{"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}' \
    | jq -c -f filters/simple/deterministic.jq

{"name":"demo","tags":["a","m","z"],"version":3}
```

As you can see, the `deterministic` script stabilizes the output and also drops
the undeterministic `score` entry.

## Filter Library

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
