# Scalar domains (removed)

Scalar domains, their type-owned functions, `wrap`, `unwrap`, explicit domain
codecs, `op(...)` requirements and named constraints were removed on
2026-10-14. They report `E_DOMAIN_REMOVED`. Run `selka fix` to migrate certain
sites to ordinary records, free functions and callback parameters.

## Declaring a replacement record

A one-field record keeps nominal identity. An invariant checks its validity at
construction and at each write. Two records remain different types even when
their fields have identical types.

```selka
# doc: expect 7
@invariant(self.value >= 0)
record Count:
    value: int

func make_count(n: int) -> Count:
    return Count(value=n)

func main(out: Stream) -> int:
    const count = make_count(7)
    print(out, count.value)
    return 0
```

The fix changes `domain X: int:` into `record X:` with `value: int`,
`wrap[X](n)` into `X(value=n)`, and `unwrap(x)` into `(x).value`. It lifts
members into module functions and preserves module qualification. If lifted
members would collide with another declaration or local, it uses `X_name`
and a numeric suffix when needed. Private members become module-private
functions; members of a public domain become public functions.

## Private members and identity

Operations are free functions; there are no type-owned namespaces. Use a
module to group related functions. Validity belongs in an `@invariant`, which
continues to guard an ordinary record even when callers construct it directly.

## Persisted shapes and explicit codecs

A record serializes as an ordinary JSON object, including a one-field record:
`Count(value=7)` has the typed JSON value shape `{"value":"7"}`; integers
keep their canonical decimal-string representation. The former bare scalar
shape changes wherever that domain appeared, including nested fields and
array elements. There is no special one-field shortcut. The outer `typed-json-v1` envelope
and its `version`, `type` and `value` fields are unchanged.

Record invariants run on direct construction, field writes and typed JSON
construction before a decoded value reaches guest code. A negative `Cents`
value such as `{"value":"-5"}` therefore traps `R_INVARIANT`, just as
`Cents(value=-5)` does. Numeric JSON such as `{"value":-5}` is not the
integer representation accepted by the typed boundary.

A domain's explicit `codec` clause disappears. Its encoder and decoder become
ordinary functions, and `codec_encode[X](v)` / `codec_decode[X](wire)` become
calls to those functions. Calling an encoder explicitly preserves the chosen
wire representation; ordinary record JSON uses the record's fields.

## Structural operations

Generic functions receive operations as callback parameters. Structural field
requirements and built-in requirements remain available; named constraint
bundles are expanded into those surviving requirements.

```selka
# doc: expect 9
record Counter:
    value: int

func score(item: Counter) -> int:
    return item.value

func evaluate[T: copy](item: T, operation: func(T) -> int) -> int:
    return operation(item)

func main(out: Stream) -> int:
    print(out, evaluate[Counter](Counter(value=9), score))
    return 0
```

## Removed syntax

```selka
# doc: expect-error E_DOMAIN_REMOVED
domain OldCount: int:
    pass
```
