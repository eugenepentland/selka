# Generic identity and length helpers — 2026-10-11

This isolated producer slice adds `generic_instances.my` and `generic_lengths.my`.
It does not activate generic body checking, change a wire schema, loosen native
validation, or provide a native body fallback. Engine dispatch and symbolic
checking remain unchanged.

## Identity and worklist contract

The donor is `src/generic_instances.zig`, with executable ID allocation from
`src/sema.zig` and `src/sema_specialize.zig`.

`make(parameter_counts)` seeds nongeneric functions in raw declaration order,
skipping generic templates. `ordinary_function(registry, declaration)` returns
that executable ID or -1. Callers must use this map before specializing a call.
`intern(mut registry, pool, span, Key)` returns the executable specialization ID:
ordinary count plus first-demand registry ordinal. `get(registry, function)` reads
the resulting append-only worklist, including ordinary declarations.

A key is the resolved raw declaration ordinal, ordered concrete type IDs, and
parallel nullable constant lengths. An empty length array is equivalent to all
None; zero is distinct from None. No names, layouts, hashes, or discovery-local
pointers are identity authorities. Constant slots use u64 type identity at the
caller's substitution layer; this low-level interner preserves the supplied key.
Registration must precede checking the body, so recursive demands reuse its ID.
The registry owns its retained key values under language copy-on-write semantics.

The native bounds are 16 arguments and 4096 instances per declaration. Existing
keys remain reusable at the bound; another declaration retains its own budget.
Argument/parallel-length shape checks precede lookup; lookup precedes instance
budget checks. The indexed table grows at half occupancy and probes at most its
capacity. Source declaration privacy, semantic arity, requirements, and known
type authority remain caller responsibilities. Malformed internal identities
are transport failures; specialization budget failures retain the native
E_GENERIC_LIMIT message and supplied call span.

## Length contract

The donors are `src/generic_lengths.zig` and `src/number_literal.zig::count`.
`literal(Context{pool,source}, span)` accepts an unsuffixed unsigned integer
spelling with native radix/underscore rules and a maximum value of 1048576.
It reuses the existing bounded u128 magnitude/digit parser through
`integer_literals.decimal`, translating its suffix rejection to the exact
length message. Lexical validation precedes suffix rejection, which precedes
magnitude overflow and the specialization length bound.

`resolve(context, span, Parameter{name,constant_length}[], int?[] values)` first
matches parameter spelling in declared order. A type parameter or a missing
parallel slot reports native E_GENERIC_LENGTH without literal fallback. A
matched const parameter returns its previously validated value. None in a
matched const slot is malformed internal specialization state and refuses as a
transport error. An unmatched spelling goes through literal parsing. These are
literal/forwarded generic lengths, not general constexpr expressions.

## Qualification

Unchanged source-qualified seed SHA256:
`c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`.

Six instance tests and six length tests pass each Debug and Release with
`--verify-facts`, `MYL_CORE_LEAKCHECK=1`, `--force --no-cache`, and 100M steps.
All four files pass individual formatter checks. Evidence is retained in
`.body-check-tmp/generic-identity/check-final.log`; the initial test-only local
name shadowing failure remains in `check.log` and is not counted as qualification.

Tests cover ordinary/template ordering, recursive reuse, nominal and declaration
identity, argument order, absent/zero lengths, retained-key copy behavior,
4096/4097 boundaries across declarations, 16/17 arguments, malformed parallel
lengths, radix/underscore spellings, u128 overflow, suffix/error precedence,
located 1048576/1048577 diagnostics, and forwarded zero/maximum values.

Installed generic admission is still pending. The native validator currently
requires one output function per raw function and rejects generic functions and
nonempty specialization metadata. A future coordinated contract must validate
resolved declarations, instance uniqueness, substituted signatures, names,
function/range ownership, and call references before this helper is connected.
