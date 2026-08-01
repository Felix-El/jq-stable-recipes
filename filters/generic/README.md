# generic

The catch-all family: a schema-agnostic `stable` filter for JSON you know
nothing about. Use it when no other filter family matches the tool you are
piping — it canonicalizes the only thing that is safe to canonicalize without
a schema and leaves everything else alone.

## stable.jq

```
$ echo '{"name": "demo", "result": {"meta": {"z": 1, "a": 2}}, "tags": ["b", "a"]}' \
    | jq -c -f filters/generic/stable.jq
# before: {"name":"demo","result":{"meta":{"z":1,"a":2}},"tags":["b","a"]}
# after:  {"name":"demo","result":{"meta":{"a":2,"z":1}},"tags":["b","a"]}
```

Stable output: object keys are sorted recursively — the one canonicalization
that is safe for every possible schema. JSON objects are unordered by
definition, so two inputs carrying the same data in a different key order
always produce identical output.

**Array order and every value are preserved.** Arrays are ordered by
definition, and without a schema there is no way to tell a meaningful sequence
(a build log, a diff) from a run-to-run permutation — so this filter sorts
nothing inside arrays and drops nothing. The mutation-test fixtures under
`tests/fixtures/generic/mutants/` deliberately vary *only* key order for
exactly this reason: changing an array would change the output by design.

**Slurp (`jq -s`) handling.** Pipe plain input with `jq -f` (no `-s`), as in
the example above — a single object stays a single object. If you do pipe with
`-s`, only a *slurped array* — input that was itself a JSON array, which `-s`
wraps as `[[...]]` — gets its outer wrapper removed, restoring the bare array.
A genuine single-element array (`[{"id":1}]`) is **never** unwrapped: without a
schema there is no way to tell a one-element array from a slurped object, and
unwrapping would corrupt real data. A slurped single object therefore stays
wrapped as `[{...}]` — pipe it without `-s` if you want the bare object.

## What is not possible

- **No `deterministic.jq`.** A deterministic filter drops undeterministic
  fields, but without a schema you cannot know which fields are run-to-run
  noise. There is no stable projection to reduce to, so `generic` ships a
  single stable filter.
- **No array sorting, no value masking.** Sorting arrays of objects would
  require knowing the semantic key; masking timestamps or GUIDs would require
  knowing which strings contain them. Both would corrupt the data as often as
  they would fix it.

## jq wins

Canonical number serialization (`1.0` → `1`, `1e2` → `100`) and duplicate-key
collapse come from jq reserializing any JSON that passes through it — this
filter included. Those are properties of jq itself, not of `generic`, and are
documented repo-wide in [Why jq](../../README.md#why-jq).

## Notes

The filter is a self-contained jq program with no external dependencies and no
`@env:` switches. The `default` golden entry locks the exact output
byte-for-byte. See [CONTRIBUTING.md](../../CONTRIBUTING.md) for the
conventions it follows.
