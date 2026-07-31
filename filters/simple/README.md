# simple

This is a teaching showcase, not a real-tool recipe. It demonstrates what the
`normalize` and `identity` filters do using one tiny JSON object, so you can
see exactly how each filter transforms its input before applying the same
patterns to a real tool's output.

## The input

```json
{"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}
```

## normalize.jq

```
$ jq -f filters/simple/normalize.jq
# before
{"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}
# after
{"name":"demo","score":42,"tags":["a","m","z"],"version":3}
```

Full normalization: all fields are preserved, but key order is sorted
alphabetically (at every nesting level) and every array is sorted. Two inputs
that represent the same data will always produce the same output.

## identity.jq

```
$ jq -f filters/simple/identity.jq
# before
{"name": "demo", "version": 3, "tags": ["z", "a", "m"], "score": 42}
# after
{"name":"demo","tags":["a","m","z"],"version":3}
```

Minimal stable projection: volatile fields (`score`) are dropped. Only the fields
that identify the object (`name`, `version`, `tags`) are kept, with key order
sorted and `tags` sorted. Two objects that are semantically the same identity
will produce bit-for-bit identical output.

## What Each Does

| Aspect                      | normalize.jq          | identity.jq            |
|-----------------------------|-----------------------|------------------------|
| Object key order            | Sorted alphabetically | Sorted alphabetically  |
| Array order (`tags`)        | Sorted                | Sorted                 |
| Volatile fields (`score`)   | Preserved             | Dropped                |

### Notes

The filters are self-contained jq programs with no external dependencies.
See the repo's [CONTRIBUTING.md](../../CONTRIBUTING.md) for the conventions
they follow (SPDX headers, `@env:` declarations, fixture layout, and the
golden/mutation test protocol).
