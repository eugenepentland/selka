# Generic provider contracts

Generic functions may use nominal result and record templates around resource and
environment operations. These wrappers retain their parameter identity while their
provider-facing fields satisfy exact contracts before any function is called.

```text
resource File:filesystem;
result Open<Tag:copy> { err:i64, ok:File }
fn open<Tag:copy>(fs:filesystem_cap)->Open<Tag> {
    return acquire_resource<Open<Tag>>(fs,new [1]u8[42u8]);
}
```

## Required layouts

| Operation | Success payload | Error payload |
|---|---|---|
| Acquire resource | A concrete nominal resource | `i64` |
| Complete resource | `bool` | Record with `resource` of the exact input resource type and `code:i64` |
| Environment lookup | Record with `bytes:[N]u8`, `length:u64`, `present:bool` | `i64` |
| Resource read | Record with `bytes:[N]u8`, `length:u64`, `eof:bool` | `i64` |
| Resource slice read | Record with `length:u64`, `eof:bool` | `i64` |
| Resource write or slice write | `u64` | `i64` |

These are named fields, in any declaration order, with no extra fields. The result
and payload record can both be parameterized. Shared field descriptors are used by
the concrete and symbolic checkers so their contracts do not drift. Symbolic shape
resolution retains the generic body's work budget.

Numeric byte arrays whose element has become exactly `u8` through substitution are
accepted, including the result of a generic `singleton::<u8>` helper. `[N]T` under
an integer constraint is insufficient: other integers are not bytes. Resource
leaves remain concrete declarations. General structural and codec constraints on
parameters remain separate work.

## Ownership and execution

The ordinary authority, mutation, borrow, result-handling and effect rules apply
before instantiation, including unused generic functions. Failed completion returns
the owned resource inside the named error record. Retrying completion transfers it
once; an abandoned failure releases it. Reads retain explicit length/EOF, fixed
read arrays zero unspecified bytes, and slice reads modify only the returned
prefix. Environment lookup distinguishes absent, empty, arbitrary binary bytes,
and typed provider failures. Invalid provider output remains a host boundary error.

## Concrete codecs inside generic functions

A generic function can call `codec_decode[Positive](wire)` and
`codec_encode[Positive](value)` when `Positive` is a known domain with a declared
codec. The checker follows the selected factories/accessors and their helper calls,
including imported module contracts. Codec methods must remain effect-free,
including transitive calls, and their typed results remain checked. `wrap` and `unwrap` are permitted only inside the exact declaring
domain, and private factory methods remain private.

`codec_encode[T](value)` still reports `E_GENERIC_BODY_UNSUPPORTED`: a copy or
integer constraint does not promise a codec. This extension introduces no implicit
representation serialization and does not define new codec constraints.

## Acceptance

The tests run both ordinary and slice I/O through generic wrappers, inspect exact
host bytes and callback counts, retry failed completion, and exercise raw
binary/missing/empty/oversize environment values. Allocation-failure sweeps cover
compiler specialization and VM ownership. Instruction-budget sweeps stop at every
instruction through completion retry and require each acquired owner to be
completed or released exactly once. Malformed named layouts reject through both
the ordinary and generic checkers. Concrete codecs execute success/error paths and
imported methods under allocation failure; unused invalid callers reject privacy,
arity, type and result errors.

No guest-native backend work is included. Board `Slot<T>` consolidation is now
implemented. Public generic tooling, codec/structural constraints, source
serialization, finer incremental checking and measured agent repair outcomes
remain open.

Validation on 2026-09-07: `zig build test-interpreter --summary all` passes all
35 steps, 853 Zig tests (776 core, 73 CLI, 4 board), and 21 Python drivers.
The focused provider/generic/resource/codec suite passes 299 tests; nominal and
generic-codec ReleaseFast acceptance passes 95. Formatting, the gated install,
and all 88 Guardian checks pass with baselines disabled. Existing report-only
size and line findings remain. The board trial retains 147 oracle comparisons,
18 malformed-input rejections and three seeded static errors; actual agent repair
attempts remain pending.
