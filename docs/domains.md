# Nominal scalar domains

A `domain` declaration introduces a nominal type over a built-in scalar backing
type (`int`, `u32`, `bool`, …). Two domains with the same backing type are
distinct, and neither converts implicitly to the scalar or to the other. The
domain is also the language's encapsulation mechanism: a `private def` member
can only be called from another member of the same domain.

## Declaring a domain

```mylang
# doc: expect 1003
domain Millimeters: u32:
    private def raw(value: u32) -> Millimeters:
        return wrap[Millimeters](value)

    def from(value: u32) -> Millimeters:
        # Clamp to the range this domain promises to represent.
        if value > 1000u32:
            return Millimeters.raw(1000u32)
        return Millimeters.raw(value)

    def number(value: Millimeters) -> u32:
        return unwrap(value)

    def add(a: Millimeters, b: Millimeters) -> Millimeters:
        return Millimeters.from(unwrap(a) + unwrap(b))


domain Seconds: u32:
    def from(value: u32) -> Seconds:
        return wrap[Seconds](value)

    def number(value: Seconds) -> u32:
        return unwrap(value)


record Measurement:
    distance: Millimeters
    elapsed: Seconds


def main(out: Stream) -> int:
    sample = Measurement(
        distance=Millimeters.add(Millimeters.from(700u32), Millimeters.from(500u32)),
        elapsed=Seconds.from(3u32),
    )
    out.print(int(Millimeters.number(sample.distance)) + int(Seconds.number(sample.elapsed)))
    return 0
```

`wrap[Domain](scalar)` constructs a domain value from its backing scalar and
`unwrap(value)` reads the scalar back; both are ordinary statically checked
operations, and `wrap` is how a private constructor is exposed through a public
factory. There is no implicit receiver and no method lookup on a value: members
are called with a qualified name, `Domain.member(arguments)`, and an unqualified
call always means a top-level function. The same member name may appear in
several domains and at top level, and whitespace around the dot does not affect
resolution.

## Private members and identity

A `private def` is visible only to other members of its domain. Calling it from
outside reports `E_PRIVATE_FUNCTION`, naming both the call site and the
declaring domain. A private member may still be reached through a public member,
which is how the clamping factory above keeps its invariant. To have the
compiler check that invariant instead of trusting every member, write it as
`@invariant(unwrap(self) <= 1000u32)` above the domain: it is checked at every
`wrap[Millimeters](...)` ([contracts](contracts.md#invariants)).

Domain values are nominal: `Millimeters` and `Seconds` have the same `u32`
backing type but are not interchangeable, a `Measurement` field keeps its
declared domain, and equality compares backing values only when both sides carry
the same domain identity. Domains may appear in parameters, results, locals,
record fields and fixed arrays, and a record or array copy preserves its nominal
element identity.
