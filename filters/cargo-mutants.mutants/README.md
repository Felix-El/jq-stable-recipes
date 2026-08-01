# cargo-mutants.mutants

Two filters for [`cargo-mutants`](https://github.com/sourcefrog/cargo-mutants) `mutants.json` output — the pre-test list of generated mutants (also emitted to stdout by `cargo mutants --list --json`) — at different levels of projection. Unlike `outcomes.json` (see [`../cargo-mutants.outcomes/`](../cargo-mutants.outcomes/)), `mutants.json` is a single JSON **array** of mutant definitions.

## stable.jq

Full normalization: generates stable, order-independent output from the mutant list by sorting the array by `name` and sorting object keys recursively. Preserves all fields, including the per-mutant unified `diff`.

```
jq -s -f filters/cargo-mutants.mutants/stable.jq target/mutants/mutants.json
```

### Stripping machine-specific paths

Set `STRIP_PATHS=1` to erase any absolute paths to just the filename:

```
STRIP_PATHS=1 jq -s -f filters/cargo-mutants.mutants/stable.jq target/mutants/mutants.json
```

In practice `mutants.json` paths are tree-relative, so this is a defensive no-op for current versions.

### Limitations

- **All fields are preserved** — including the regenerable `diff`. For a minimal projection, use `deterministic.jq`.

## deterministic.jq

Deterministic projection. Does what `stable.jq` does, and additionally drops the per-mutant unified `diff`, which is regenerable from `file` + `span` + `replacement`. Everything that identifies a mutant remains — `name`, `package`, `file`, `span`, `replacement`, `genre`, `function`. Suitable as a stable test key or piped to `sha256sum`.

```
jq -s -f filters/cargo-mutants.mutants/deterministic.jq target/mutants/mutants.json
```

With path stripping (no-op — mutants.json paths are tree-relative):

```
STRIP_PATHS=1 jq -s -f filters/cargo-mutants.mutants/deterministic.jq target/mutants/mutants.json
```

### Projected Fields

| Category | Kept fields |
|---|---|
| Identity | `name`, `package`, `file` |
| Location | `span` (`start`/`end` line + column) |
| Mutation | `replacement`, `genre` |
| Enclosing function | `function` (`function_name`, `return_type`, `span`) |

### Limitations

- **No diff** — `diff` is dropped; it is regenerable from the kept fields.
- **No path information beyond `file`** — `file` is tree-relative by design.

## What stable.jq Does

| Variation | Treatment |
|---|---|
| Mutant order | Sort by `name` |
| Object key ordering | Recursively sort keys alphabetically |
| Absolute paths | Strip to basename when `STRIP_PATHS=1` |

## What deterministic.jq Drops

| Field | Reason |
|---|---|
| `diff` | Regenerable from `file` + `span` + `replacement`; large |

## Related

[`cargo-mutants.outcomes`](../cargo-mutants.outcomes/) filters the post-test `outcomes.json` (counts, per-scenario results).
