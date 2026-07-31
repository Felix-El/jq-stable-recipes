# cargo-mutants

Two filters for [`cargo-mutants`](https://github.com/sourcefrog/cargo-mutants) `outcomes.json` output, at different levels of projection.

## stable.jq

Full normalization: generates stable, order-independent output from mutation test output by sorting the variable parts of the JSON — outcome order, phase result order, and object keys. Strips absolute paths on demand, preserves all other fields.

```
jq -f filters/cargo-mutants/stable.jq target/mutants/outcomes.json
```

### Stripping machine-specific paths

Set `STRIP_PATHS=1` to erase all absolute paths to just the filename:

```
STRIP_PATHS=1 jq -f filters/cargo-mutants/stable.jq target/mutants/outcomes.json
```

### Limitations

- **Machine-specific paths are preserved** without `STRIP_PATHS=1`. The output is stable across rebuilds on the same machine, not across different CI runners.
- **All fields are preserved** — including runtime data like `duration`, `start_time`, and `end_time`. For deterministic output, use `deterministic.jq`.

## deterministic.jq

Deterministic projection. Does what `stable.jq` does, and additionally drops undeterministic data (runtime timing, timestamps, paths, tool version): only the fields needed to determine if two mutation test runs are semantically identical remain — mutation counts, scenario names, per-scenario summaries, and phase-level pass/fail. Suitable as a stable test key or piped to `sha256sum`.

```
jq -f filters/cargo-mutants/deterministic.jq target/mutants/outcomes.json
```

With path stripping (no-op for identity — no path fields in the projection):

```
STRIP_PATHS=1 jq -f filters/cargo-mutants/deterministic.jq target/mutants/outcomes.json
```

### Projected Fields

| Category | Kept fields |
|---|---|
| Summary | `total_mutants`, `missed`, `caught`, `timeout`, `unviable`, `success` |
| Per outcome | `scenario`, `summary`, `phase_results` (with `phase`, `process_status` only) |

### Limitations

- **No path information** — paths are excluded by design. STRIP_PATHS has no effect.
- **No timing or version** — `duration`, `start_time`, `end_time`, `cargo_mutants_version` are dropped.
- **No argv** — command-line arguments reflect environment, not mutation results.

## What stable.jq Does

| Variation | Treatment |
|---|---|
| Outcome order | Sort by `scenario` |
| Phase result order | Sort by `phase` |
| Object key ordering | Recursively sort keys alphabetically |
| Absolute paths | Strip to basename when `STRIP_PATHS=1` |

## What deterministic.jq Drops

| Field | Reason |
|---|---|
| `log_path`, `diff_path` | Machine-specific paths |
| `argv` | Toolchain paths and flags |
| `duration` | Runtime timing, machine-dependent |
| `start_time`, `end_time` | Timestamps, vary per run |
| `cargo_mutants_version` | Tool version, changes independently |
