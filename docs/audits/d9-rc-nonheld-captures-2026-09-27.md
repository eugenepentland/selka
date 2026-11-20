# Exact nonheld list captures

This slice removes terminal-H role handling only for a proved empty compiler
capture of a canonically owned scalar list. It implements the
[reviewed design](d9-rc-nonheld-capture-design-2026-09-27.md); it does not change
runtime counts, semantic sharing history, iterator identity, runtime selection
or the canonical call ABI. Stage 4 acceptance remains open.

The baseline is the fully gated joined source
`468bd8e536b0e088ff71291cb9a3c92db8ebf448`, Debug compiler
`082edf36c3b1370debeccb4bdcbf3069fbf7829ad1852e8a7d0d5d7f2a34c67e`.
The candidate's frozen Debug compiler is
`6418ad2dc5a15540288a783c9222c141055e0ea36af38fa75e94d6ecd825f9a9`.
Both paths, source-file hashes, native manifests, executed commands and full
outputs are in the [evidence archive](../../experiments/d9-rc-nonheld-captures-20260927/README.md).
No compiler production source changed during measurement. A later test-only
correction replaces an obsolete refusal expectation with the newly proved
admission while retaining assertions for the real iterator hold/drop path.

## Proof and emission

`qbe_rc_nonheld_capture.proven` proves an input role, not a lifetime. Its exact
producer is adjacent `LOAD_LOCAL source; STORE_LOCAL target`, with empty input
stack, matching types, no branch into the store and no planned SHARE, read
capture or closed-field transfer at either instruction. Both values must have
independent canonical storage. The target is a compiler temporary; the source
has one ordinary named-local store. The canonical store normalizes an incoming
O, H, LOAN or raw borrow into O. A source name alone is never an ownership fact.

The proof refuses parameters, by-reference/caller storage, receiver aliases and
places, temporary sources, pattern bindings, source/target references or moves,
repeated definitions and every backward edge enclosing the source definition.
Readonly and borrowed-entry emission refuse explicitly. Only unboxed lists of
plain scalar elements of width 1, 2, 4 or 8 qualify. Dictionaries, boxes, views,
aggregate elements and projected producers retain their existing paths.

Independently, the target must pass the existing whole-local inert receiver or
anchored-read empty-token proof. All clone/alias/place/box-owner writers remain
vetoes. Thus the target begins empty, receives only raw borrowed bits, and can
never publish a live O, H or LOAN token. Finalized journal omission and strict
unexpected-publication/scope errors remain authoritative. The two view-lowering
hooks consume this finalized fact; they do not independently omit storage.
Actual iterator sources continue to acquire, propagate and drop H tokens.

Functions above 4096 instructions refuse. Finalization has a 262144
**candidate-code allowance**: ordinary candidates charge one code length and
maybe-H candidates charge three. Definition and role writer/backedge scans are
accounted for conservatively; short-circuiting the anchored versus inert proof
avoids duplicate role analysis for one candidate. This is not a claim that all
primitive visits in the separately bounded existing lifetime, plan and path
proofs total 262144. The two view-emission hooks consume cached layout facts rather than rerunning
the role proof. Existing inert/edge proof query sites remain independently
bounded per query; the candidate allowance applies to finalization, not their
combined call count.

## Measurement

The four programs use their unchanged repository input sizes, CPU 10 and three
retired-instruction observations per side. QBE uses ReleaseFast; LLVM uses
ReleaseFast, O3 and full LTO, authenticated by every native manifest. Counted
executions are separate from timing. No source-size reduction or profiling
sample is used as an acceptance result.

| Program | QBE after/before | LLVM after/before | QBE / accepted GC | LLVM / accepted GC |
|---|---:|---:|---:|---:|
| alloc_churn | 1.000461 | 1.000000 | 2.836862 | 2.966675 |
| sieve | 0.687615 | 0.683907 | 5.327463 | 10.498796 |
| list_append_sum | 1.000000 | 1.000000 | 4.522380 | 5.484581 |
| fannkuch_redux | 1.000000 | 1.000000 | 1.744179 | 1.016339 |

All 16 counted executions agree exactly before/after and between backends.
All outputs match their unchanged expected files. The accepted-GC binaries were
hash-verified and measured freshly without rebuilding or overwriting them.

Sieve's main IL shrinks from 95355 to 80942 bytes. Four exact captures receive the
new certificate; static hold-acquire alternatives fall from seven to three.
The single executed iterator H pair remains. Allocation/retirement stays 2/2,
O stays 1/3, uniqueness checks stay six, and no clones occur. The owning source
journal, earlier/later iteration journals and frame admission remain in place.
The other three programs have byte-identical emitted IL and native `.text`
before/after; their small instruction variation is measurement/layout noise.

## Validation and limits

The final focused RC suite passes 165/165 tests, including the new exact-writer,
borrowed-entry and repeated-definition structural refusals. The new guest
fixture and thirteen surrounding suites pass 468/468 uncached assertions across
GC stress/RC and both actual backends. Whole-tree Guardian passes all 88 checks;
formatting and the Debug compiler build pass.

The paired standalone controls cover seven positive assertions, snapshot and
callback behavior, real iterator visibility, heap/arena bounds failure, checked
overflow, logical step exhaustion and structural iterator mutation. Their 48
executions compare both frozen compilers, both runtimes and both backends.
Every RC normal/trap execution preserves all before/after counters and balanced
heap ownership/holds. Logical-step controls use Debug guest checks (LLVM still
O3/full-LTO); other standalone controls use ReleaseFast. No trap code or output
is weakened to accommodate code-size differences.

The first broader RC unit run found the old `held` loop test still expected no
fast loop after any same-type iteration. The proof now safely admits the later
separate write loop. The corrected test requires the exact nonheld marker and
fast arm while retaining real H acquire, slot-drop and frame behavior. The
failed run is archived rather than counted as a pass.

The initial standalone driver incorrectly added arena allocations to heap
retirements. The runtime intentionally bulk-closes arenas without adding heap
retire events; the driver was corrected to check the existing heap and hold
balance equations. The raw failed accounting receipt is retained. Initial
illegal pattern-write test source was also corrected to a legal read-only
pattern refusal; the frontend rejection remains in the archive.

This proof deliberately leaves repeated user loop bindings, uncertain role
publishers, actual iterator holds and callback/ref/pattern paths on their
existing implementations. Repeated descriptor lookup in the scalar append
room path is a separate runtime proposal and is not changed here.
