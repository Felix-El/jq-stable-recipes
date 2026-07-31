# FAQ

## What is this project?

A collection of tested `jq` filters that turn non-deterministic tool output (like `cargo build --message-format json`) into stable, canonicalized JSON. Feed the same logical input to the same filter and you always get byte-for-byte identical output — regardless of machine, run order, or timing. Nothing in this repository does fingerprinting: the filters only canonicalize. Fingerprinting the output (hashing it, e.g. `| sha256sum`) is a step you add in your own pipeline — the stable output is exactly what makes that fingerprint reliable.

## Why do I want stable output?

Caching and change detection need a stable key. If the key changes on every run, the cache misses every time:

- **CI caching** — only rebuild/re-test when the fingerprint of the build actually changed.
- **Change detection** — decide if an outcome is "the same" as a previous one without storing the full output.
- **Reproducible builds** — pin down what a build actually depends on, independent of machine-specific noise.

The filters produce the stable key material: canonical JSON that is byte-for-byte identical for identical logical input. Hashing that JSON into an actual fingerprint (a cache key) is the final step you add yourself, e.g. `| sha256sum`.

## Why jq? Why not a compiled tool?

`jq` is everywhere, auditable, and dependency-free. A filter is just a file you can read, review, and paste into a pipeline. There is no compiled binary to install, no version skew between the filter and the tool it processes, and no third-party trust boundary — the recipe is plain text under MIT.

## What does "stable" mean exactly?

Stable means: **given the same logical input, the output is byte-for-byte identical**. The filters remove the sources of run-to-run variance:

| Variation | Treatment |
|---|---|
| Message/line order (parallel execution) | Deterministic sort |
| Hash suffixes in paths (`-be9f3faac0a26ef0`) | Replaced with a fixed `-HASH` marker |
| Array element order | Sorted |
| Object key order | Recursively sorted alphabetically |
| Machine-specific absolute paths | Optionally stripped via `STRIP_PATHS=1` |
| Caching-state fields (`fresh`, `executable`, timing) | Removed |

## What's the difference between `stable.jq` and `deterministic.jq`?

Every filter directory ships two variants that aim at two different guarantees:

- **`stable.jq`** — *stable* output. Sorts the variable parts of a JSON fragment (object key order, array order) so the same logical input always yields byte-for-byte identical output. All meaningful fields are preserved. Good when you want to compare complete results or store a faithful snapshot.
- **`deterministic.jq`** — *deterministic* output. Does what `stable.jq` does, and additionally removes undeterministic data (timestamps, timing, hashes, machine-specific paths, volatile fields). Only the fields needed to decide "is this the same build/outcome as before?" remain. Smaller, faster, and ideal as a cache key.

Use `deterministic.jq` when the input contains data that can never be reproduced and you only care about *sameness*; use `stable.jq` when you care about the *content*.

## Why does the command use `-s` (slurp)?

Tools like `cargo build --message-format json` emit **NDJSON** — one JSON object per line, streamed. `jq` by default processes line by line, which can't reorder or deduplicate across lines. `-s` reads the whole stream into an array first, letting the filter sort and project the entire set.

For tools that emit a **single JSON object** (like `cargo-mutants outcomes.json`), no slurp is needed — the filter handles a single object directly.

## What are the `# @env:` header lines for?

Environment variables used by a filter must be declared at the top of the file:

```
# SPDX-License-Identifier: MIT
#
# Normalize cargo build JSON output.
#
# @env:STRIP_PATHS?:1
```

The `@env:` declaration tells the test runner which environment variables the filter reads, and the optional `?default` marks the default value. This matters for two reasons:

1. **Coverage check** — `just coverage` verifies every `@env:` combination is tested (both set and unset, plus non-default values).
2. **Determinism contract** — an undeclared environment variable that silently changes output would break the "same input → same output" guarantee.

## How do I use a filter in CI?

```
cargo build --message-format json 2>/dev/null \
  | jq -s -f filters/cargo-build/deterministic.jq \
  | sha256sum
```

The filter output is stable JSON; the `sha256sum` step is what turns it into the fingerprint. Pipe the filter output to `sha256sum` to get a single cache key:

```
cache_key=$(cargo build --message-format json 2>/dev/null \
  | jq -s -f filters/cargo-build/deterministic.jq | sha256sum | cut -d' ' -f1)
```

## Which jq version do I need?

`jq` 1.7 or later. The test suite and CI run against jq 1.7+; constructs that behave differently in jq 1.8 (e.g. `reduce` with a single-element iterator) are written to work identically in both.

## How are the filters tested?

Deterministically — no real tool invocations in the tests. Each filter directory has:

- **Mutation fixtures** — hand-crafted perturbations of real tool output (reordered lines, fresh hash suffixes, shuffled arrays) that a filter must normalize away.
- **Golden tests** — a dispatcher file mapping each mutation to its expected normalized output; the filter result must match byte-for-byte.
- **Coverage** — every `@env:` combination is exercised, and each filter must hit 100% of its declared env combinations.

The SPDX header is enforced by `just lint` in CI, so every filter file is guaranteed to carry its license.

## Can I add my own filter?

Yes — see [CONTRIBUTING.md](CONTRIBUTING.md) for the header format, design rules, fixture layout, and the coverage requirement. The short version: real tool output captured into fixtures, ≥2 mutation variants, a golden dispatcher, `@env:` declarations, and a passing test suite.

## License

MIT — see [LICENSE](LICENSE).
