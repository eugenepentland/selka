# Optional-value ergonomics audit

The current union model can represent absence without nullable pointers or new
syntax. An explicit result can distinguish an absent value from a failed lookup:

```text
union MaybeCoordinate { none, some: i64 }
result Lookup { ok: MaybeCoordinate, err: i64 }

fn score(value: Lookup) -> i64 {
    match value {
        Lookup.err(code) => { return 0 - code; },
        Lookup.ok(option) => {
            match option {
                MaybeCoordinate.none => { return -1; },
                MaybeCoordinate.some(n) => { return n; }
            }
        }
    }
}
```

The numeric result is an observation for this audit. Application interfaces should
retain the tagged `Lookup` value when callers need to distinguish these states;
negative integers are not a proposed representation of absence or failure.

## Observed behavior

The rebuilt VM CLI executed three versions of a main function calling this
helper: a present coordinate of 7 returned 7, successful absence returned -1,
and a lookup error of 3 returned -3. Five malformed alternatives rejected before
execution:

| Mistake | Diagnostic |
| --- | --- |
| Match only the present case | `E_INCOMPLETE_MATCH` |
| Read a union payload with `.some` without matching | `E_TYPE` |
| Use a payload binding after its match arm | `E_UNKNOWN_NAME` |
| Discard a `Lookup` failure | `E_RESULT_DISCARD` |
| Apply `try` directly to the optional union | `E_TRY_TYPE` |

Existing regression coverage in `src/variants_test.zig`, `src/results_test.zig`
and `src/propagation_test.zig` covers exhaustive matching, forbidden payload
projection, arm scope, nested result obligations and `try` requiring a declared
result. This audit combines those rules in a lookup example; it adds no syntax
or runtime behavior and is not a measured agent study.

## Design costs and decision

Construction and extraction are explicit. A lookup that can both fail and return
no value requires two match statements. Matches are statements, so producing a
value for a larger expression usually requires a helper or a mutable local.
Current generic functions can operate on a concrete optional declaration, but
there is no generic `Option<T>` type constructor. Distinct optional payload types
therefore require separate nominal declarations and potentially similar helpers.

An optional union containing only copyable values is ordinary data: it may be
ignored or discarded. It is not a must-handle error. A declared result, including
one carried inside a union or record, keeps its checked handling obligations.
These rules express different obligations and should stay explicit in any
future convenience syntax.

Keep named unions for absence and declared results for errors during the first
application trial. Record how often nested matches, per-type declarations and
helper functions obstruct changes. Use that evidence to decide whether generic
type constructors, expression matching or dedicated optional syntax deserve
priority. Any convenience must preserve exhaustive absence handling at payload
access, exact payload types, ownership and separate error obligations. Do not add
implicit unwrapping or infer absence from arbitrary integer or pointer values.

This completes the initial syntax/rule audit. Usability, repair success and the
cost of repetitive declarations still need the board/constraint-processing trial.
