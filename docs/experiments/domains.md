# A2: nominal scalar domains and private construction

Status: domain types, qualified functions, private helpers, and representation
access checks are implemented. [Closed enums, tagged unions, and exhaustive
matching](variants.md) and [complete enum-indexed tables](tables.md) are also
implemented, completing A2.

## Syntax and access

```text
domain Millimeters: i64 {
    private fn raw(n: i64) -> Millimeters {
        return wrap[Millimeters](n);
    }

    fn from(n: i64) -> Millimeters {
        if n < 0 { return Millimeters.raw(0); }
        return Millimeters.raw(n);
    }

    fn number(n: Millimeters) -> i64 {
        return unwrap(n);
    }
}
```

A `domain Name: Scalar { functions... }` declaration introduces a nominal type
with a built-in integer or boolean backing type. Two domains with the same
backing type are distinct; neither is implicitly convertible to the scalar.
Domains may occur in parameters, results, locals, record fields, and fixed arrays.
Record and array copies preserve their nominal element identities.

Functions declared in the domain are called with `Name.function(arguments)`.
They are ordinary statically resolved functions, with explicit parameters and
results, forward calls, recursion, and the usual return/discard rules. There
is no implicit receiver or method lookup on a value. Calls inside the domain
also use qualified names; unqualified calls refer to top-level functions. The
same member name may occur in different domains and at top level. Whitespace
around the dot does not affect resolution. A domain's `main` does not satisfy
the required top-level `fn main() -> i64`.

Functions are callable from outside by default. `private fn` makes a function
callable only by functions lexically declared in the same domain. It can hide a
raw constructor or an implementation helper. Private functions are still fully
checked, even if uncalled. `private` is currently permitted only inside domains;
module visibility remains a separate experiment.

`wrap[Domain](expression)` requires the exact backing scalar type and constructs
a value of that domain. `unwrap(expression)` extracts the backing scalar. Both
operations are permitted only inside functions declared in the value's own
domain. Access does not propagate to free helpers called by a factory, or to
functions of another domain. Source diagnostics identify both the forbidden
access/call and the owning declaration. `domain`, `private`, `wrap`, and `unwrap`
are reserved keywords.

## Invariant boundary

There is no implicit public constructor, numeric cast to/from a domain, exposed
backing field, record construction, record update, or indexed access on a domain
value. Other code obtains new values through public factories and can preserve
or pass existing values. A domain may deliberately expose a public raw factory
or accessor; the compiler enforces who can construct/access the representation,
not whether a factory's mathematical policy is sensible.

In the example, only the domain implementation can call `raw`, so outside code
cannot bypass `from` and construct negative Millimeters. The implementation is
responsible for applying its rules on every construction path. An accessor
returning an integer does not grant the caller permission to wrap it again.
Explicit calls to another domain's public factory are intentional conversions;
a Seconds value cannot be passed directly where Millimeters is required.

Scalar domains now support [same-domain equality](domain-equality.md): `==` and
`!=` compare backing values without exposing them. Arithmetic and ordering are
not inherited. Expose those operations as domain functions when meaningful;
identifiers do not gain arithmetic merely because their representation is numeric.
Factory failures can trap through checked scalar operations or use typed results.

Domain functions may use ordinary record conversions, but `conversion fn`
continues to require record parameters/results and named source-field accounting.
Transform scalar domains through ordinary domain factories/accessors.

## Runtime and tooling

This VM stores domain values as immutable retained values with one scalar payload.
Loads, calls, returns, aggregate storage, and overwrites use the established value
ownership paths. Wrapping currently allocates host storage; this is not an
allocation-free ABI promise or a guest resource/effect model. Bytecode retains
function owner/visibility and has explicit `WRAP_DOMAIN`/`UNWRAP_DOMAIN` operations.
Emission validation rejects mismatched owners, private cross-domain calls, and
ordinary record construction/update of domain schemas. Ordinary field projection
cannot expose a domain payload. Source privacy is not a sandbox for an untrusted
bytecode loader; there is no such loader.

Dumps and guest traces show qualified names. Exact duplicate discovery `exact-v5`
retains domain ownership, visibility, nominal types, wrapping/unwrapping, and
resolved qualified callees. Renamed functions in the same domain can match;
functions with different access contracts remain separate candidates.

## Evidence

- `src/domains_test.zig`: rejection of Seconds as Millimeters, all integer backing
  widths and bool, explicit checked conversions and overflow, private factory/accessor enforcement, bypass attempts, qualified
  names, forward calls/recursion, namespace conflicts, nested records/arrays,
  conversions, duplicate identity, and bytecode access validation.
- Allocation-failure sweeps cover compilation, factories, accessors, aggregates,
  dumps, and discovery. A 10,000-construction loop fits a 4 KiB live runtime budget
  and releases all storage. Budget and narrowing-cast traps also release storage.
- Actual CLI fixtures run `examples/domains.selka` (1003), check qualified dumps,
  reject private calls across all four commands, and name both mismatched units.
- The complete suite passes 100/100 tests in Debug and ReleaseFast (83 core,
  17 actual CLI) on Guardian's `0.17.0-dev.1683+5ceec001b` snapshot.
