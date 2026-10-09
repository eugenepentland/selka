# Phase 3 cache closeout

Starting compiler: cf7c620dc. This batch owns semantic_key.zig,
sema_specialize.zig, semantic_cache_test.zig and semantic_project_test.zig.

## Source-bound baseline

The baseline executable was measured before rebuilding it; the nominal receipt
records its SHA256. baseline-session.json preserves the callback mismatch
workload: after a source relocation it rechecks main and reuses two ordinary
bodies. The conservative reason is function-value (the function value's exact
contract differs from the declared callback slot). baseline-nominal-session.json
preserves a Box[T]/make[T] workload: both requests check one specialization,
retain none and reuse none, with specialization-interned-record on publication.
The .my sources are preserved beside the receipts. These are shared-machine
observations, not uncontended performance measurements or speedup claims.

The initial baseline-nominal-failure.json records an invalid hyphenated entry
filename rejected by CLI identifier validation; it is a harness correction,
not a compiler crash.

## Implementation

Concrete specialization capture now retains unique resolved catalog identities
and their transitive schema digests even when body checking created those
records. Replay searches the current fresh catalog; absent and ambiguous
identities miss, and a changed transitive schema misses before copying any body.
No retained schema is installed into the fresh catalog. In particular,
resolving a fresh Box[i64] specialization signature materializes its nominal
application before replay, so the previously blanket interned-record miss is
unnecessary. Every global semantic validation still runs.

Resolved aggregate argument descriptors incorporate the provider digest rather
than identifying types solely by display spelling. Builtin and constant-length
descriptors retain their existing encodings. The specialization key domain is
semantic-specialization-v3. Compiler build identity also partitions persisted
entries. Callable labels and mutation positions already participated in provider
identity; new descriptor assertions prove both also distinguish arguments.

## Validation and limits

implementation-tests-03.log passed 30 focused specialization, descriptor and
callback-provider tests. Tests compare cached execution/diagnostics against a
fresh check. The Box workload asserts exactly one extra specialization reuse
and no extra check; inserting an unrelated nominal declaration preserves that
reuse, and editing the provider schema forces exactly one fresh check. The
module workload instantiates identically spelled Item declarations from two
modules and expects two distinct retained bodies, two relocation reuses, and
only one fresh check when one module's schema changes.

cache-suite-04.log passes all 68 selected semantic cache/project tests (61 named and seven standard unnamed), exit 0. The source-bound updated-nominal-session-candidate1.json uses immutable compiler
235875cbc2796d0eda1883b75b55265b268696771b1a45ad95968e6bd5e0ab47.
The identical cold/relocated workload changes from baseline specialization
checked 1→2, stored 0, reused 0 to candidate checked 1→1, stored 1, reused 0→1.
The reduction is actual checked-body work; elapsed observations do not establish
a compiler speedup. measure_session.py reproduces the capture with compiler and
source SHA256 receipts.
The integrated suite first passed 66/68 tests: the two failures were existing
callback native-execution fixtures with allocation-excluding effects ceilings
rejected by an initial phase 4 interpretation. A temporary change to exactly two
fixture ceilings passed in cache-suite-04.log. The coordinator subsequently
restricted the stronger Core allocation check to explicitly written noalloc,
preserving guest-level effects semantics, and those temporary ceiling edits were
fully restored. Original failures remain in cache-suite-02.log and the invalid
abbreviated effect spelling in cache-suite-03.log. Final original-fixture
qualification passes all 68 tests in cache-suite-final.log, exit 0, after the
integrated noalloc-only correction. No fixture ceiling change remains.
First attempts and build-slot waits are retained in the logs; no failed receipt
was overwritten.

Remaining conservative cases: ordinary callers referencing generic
specializations still instantiate afresh; body-only nominal/structural/callable
records absent from the current fresh catalog remain misses. Ordinary function
value bodies whose callable contract is not already declared remain fresh.
Nested specialization references absent from the fresh instance registry remain
misses. This batch does not claim those cases were eliminated.

## Final compiler qualification

updated-nominal-session-final.json repeats the same cold/relocated source on
immutable compiler aca89445a3f2d4f2dddbf68b6441c3473374cd37b2e6cde68929e0690def737f.
The first request checks one specialization and stores one; the relocated
request reuses one, with cumulative checked remaining one. Both requests pass.
The final original-fixture cache suite passes 68/68 as recorded above.

## Qualified compiler recollection

After the narrow cold UTF-8 diagnostic lowering repair and explicit-noalloc
fixture reconciliation, updated-nominal-session-qualified.json repeats the same
source on immutable compiler
21319448ba51241f917c040004d1a3c7123e5516d5f0a766d7cff557294793f2.
Cold checked/stored are one/one; relocated reuse becomes one while cumulative
checked remains one. Both requests pass. Checkpoint final receipts are preserved.
