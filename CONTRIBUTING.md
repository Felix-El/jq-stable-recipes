# Contributing to jq-stable-recipes

Thanks for contributing! This document covers the conventions every filter and commit must follow.

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

Create a subdirectory in `filters/<name>/` with:
- one or more `.jq` filter files (each self-contained, with env var headers)
- `README.md` — documentation and limitations

Add test fixtures under `tests/fixtures/<name>/mutants/`, then generate goldens:

```bash
# Generate expected output for default env
jq -s -f filters/<name>/<filter>.jq tests/fixtures/<name>/mutants/input.json \
  > tests/fixtures/<name>/output-<filter>/output.default.json

# For each @env: variant, generate with that env set
env STRIP_PATHS=1 jq -s -f filters/<name>/<filter>.jq \
  tests/fixtures/<name>/mutants/input.json \
  > tests/fixtures/<name>/output-<filter>/output.strip_paths.json
```

Write a `<filter>.test.json` dispatcher referencing these files, run `cd tests && bash run-tests.sh`, then add a link to `filters/<name>/` in the filter list of the README.

### Fixture file layout

```
tests/fixtures/<name>/
  mutants/
    input.json          # base input fixture
    mutated-1.json      # shuffled variant (mutation test)
    mutated-2.json      # another shuffled variant
  output-<filter>/
    output.<variant>.json   # expected output per variant
  <filter>.test.json        # golden dispatcher
```

## Commit Guidelines

Commit messages must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification. Use a type prefix from the [standard types](https://www.conventionalcommits.org/en/v1.0.0/#summary) (`feat`, `fix`, `docs`, `test`, `refactor`, `chore`, …) and scope it to the affected recipe or area when meaningful, e.g. `feat(cargo-build): add strip-paths normalization` or `test: cover null env state for cargo-mutants`.

- Use the imperative mood and keep the summary under 72 characters.
- Add a body explaining the *why* when the change isn't self-explanatory.
- One logical change per commit.
