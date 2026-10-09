# Matching a variant

A `match` statement dispatches on a variant and binds its payload. The scrutinee
evaluates once, exactly one arm runs, and every variant needs an arm unless a
wildcard covers the rest.

## Variant matches

```mylang
# doc: expect 42
result Read:
    ok: i64,
    err: i64


func value(input: Read) -> i64:
    match input:
        case Read.ok(number):
            return number
        case Read.err(code):
            return -code


func main(out: Stream) -> i64:
    out.print(value(Ok(42)))
    return 0
```

Payload patterns use `Variant.case(binding)`, or `Variant.case(_)` to ignore the
payload. An owned payload may move out of its arm or be cleaned up after it. A
result-bearing payload must be handled or transferred; ignoring it does not erase
its obligation, and the ownership state an arm leaves behind must agree with
every other arm's.

`?` propagation inside an arm retains the enclosing statement's pending
obligations, so an earlier fallible argument cannot be abandoned by a later arm
propagating an error. Arena dependencies follow the produced value, so returning
a scratch-backed owned value out of a match still rejects.

Ordinary and generic functions share these rules. Lowering uses exhaustive
variant dispatch, owned payload cleanup included.

## Wildcard arms

A `match` may end with `case _`, which takes every variant no earlier arm named
and discards that variant's payload. It must be the last arm and must cover at
least one variant; an earlier position, or a match whose arms are already
exhaustive, reports `E_WILDCARD_ARM`. A wildcard also refuses to cover a variant
whose payload still carries an unhandled result, reporting `E_RESULT_DISCARD`,
because dropping that payload would drop its obligation; that variant needs its
own arm.

```mylang
# doc: expect-error E_WILDCARD_ARM
enum Event:
    start
    tick(value: int)
    stop(value: int)


func weight(event: Event) -> int:
    match event:
        case Event.tick(value=count):
            return count
        case _:
            return 0


func misplaced(event: Event) -> int:
    match event:
        case _:
            return 0
        case Event.tick(value=count):
            return count


func main() -> int:
    return weight(Event.tick(value=42))
```
