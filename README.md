# jq-stable-recipes

Tested jq recipes that produce stable JSON from non-deterministic tool output.

## Problem

Tools like `cargo build --message-format json` emit JSON that varies between runs: parallel execution reorders messages, build artifacts carry fresh hashes, arrays come in arbitrary order. These filters normalize such output into a stable fingerprint — use it for caching, change detection, or reproducible builds.

## Usage

```
cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/normalize.jq

# Or for a minimal fingerprint:
cargo build --message-format json 2>/dev/null | jq -s -f filters/cargo-build/identity.jq
```

## Filters

- [**cargo-build**](filters/cargo-build/) — Two filters for `cargo build --message-format json`:
  - [`normalize.jq`](filters/cargo-build/) — Full normalization: stable JSON, all fields preserved
  - [`identity.jq`](filters/cargo-build/) — Minimal fingerprint: only fields needed to identify if two builds are the same

Each filter directory has its own README with detailed documentation and known limitations.

## Header Format

Every `.jq` file starts with a comment block structured as follows:

```jq
# Free-form description of what this filter does.
# Can span multiple lines — this is the inline documentation.
#
# @env:VAR_NAME:value          Required var, must be set
# @env:OTHER?:val1|val2|val3   Optional var, null/unset also valid
```

- **Free-form text** — describes the purpose and behavior of the filter.
- **Blank `#` line** separates the description from the `@env:` declarations.
- **`@env:NAME:VALUE`** — declares a required environment variable the filter reads. The golden file must contain at least one entry where this var is set to a non-null value.
- **`@env:NAME?:VALUE`** — declares an optional variable. The `?` signals that the filter handles the unset/null state. The golden file must contain entries covering both a set and a null value for this var.
- **`VALUE`** is either a literal string (e.g., `1`) or a set of possible values separated by `|` (e.g., `true|false`).

## Design Rules

- **Self-contained.** Each `.jq` file must work independently. Never reference other recipes — not even in comments or READMEs. Users should be able to grab a single `.jq` file, understand it in isolation, and use it without reading anything else.
- **Header format enforced.** The header conventions above are mandatory for machine parsing.
- **Golden dispatcher.** Filters with `@env:` declarations need a `<name>.golden.json` in their fixture directory that maps env configurations to expected output files. The runner validates that every `@env:` declaration is covered by at least one golden entry. Without a golden file, only mutation tests run.

## Adding a Filter

## Adding a Filter

Create a subdirectory in `filters/<name>/` with:
- one or more `.jq` filter files (each self-contained, with env var headers)
- `README.md` — documentation and limitations

Add test fixtures in `tests/fixtures/<name>/`, then generate goldens:

```bash
# Generate expected output for default env
jq -s -f filters/<name>/<filter>.jq tests/fixtures/<name>/input.json \
  > tests/fixtures/<name>/<filter>.default.expected.json

# For each @env: variant, generate with that env set
env STRIP_PATHS=1 jq -s -f filters/<name>/<filter>.jq \
  tests/fixtures/<name>/input.json \
  > tests/fixtures/<name>/<filter>.strip_paths.expected.json
```

Write a `<filter>.golden.json` dispatcher referencing these files, run `cd tests && bash run-tests.sh`, then add a link to `filters/<name>/` in the filter list above.

## License

MIT
