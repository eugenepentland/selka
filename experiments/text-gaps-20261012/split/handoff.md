# Explicit split scalar readers

C0: `78b4bb5934748d5942389b12dfe66cb0031cafdc`.
Worktree: `mylang-text-gaps-20261012-split`.

The unchanged `split_job` observes both `len(parts)` and every part through a
scalar helper. Existing `split_views` already stores private offset pairs, but
an internal call prevents its token view from remaining borrowed. Core CFG
inlining previously rejected non-owning loops, so only later LLVM inlining
could see the scalar reader, after token ownership had already been emitted.

`inline_reader.zig` recognizes checked scalar readers with at most eight
parameters, sixteen blocks, eighty instruction slots and two loops. It admits
scalar arithmetic/control flow and local scalar/octet reads; stores, aggregate
construction, managed returns, printing and opaque calls fail the predicate.
Its sole admitted call is the exact runtime-authorized
`myl_core_span_bytes_index_offset(str, int) -> u64` with views=1,
owned=consumes=0. The existing CFG cloner preserves the checks and inline source
ancestry. Readers and destination constructors share the existing per-caller
256-instruction clone budget.

After cloning, cleanup removes a `str_from_view` only when every resolved use
is the source of `str_len` or `str_view_of`, and the existing source-stability
check accepts its parent owner. Forwarding copies become views. Cleanup creates
no instruction, declaration or ABI; cache catalogs and provenance remain intact.
Owned escaping returns and mutation/transfer cases remain materialized.

Coordinator-owned shared edits, kept uncommitted in this worker tree:

- `inline.zig`: dispatch bounded readers through existing CFG cloning; share
  constructor budget; run local cleanup before cached transformed caller capture.
- `inline_cfg.zig`: preserve a direct call's module function reference while
  remapping its local arguments. Previously no eligible CFG contained calls.
- `root_test.zig`: register `textgap_split_test.zig`.

The first candidate additionally fused an observed split count into an eager
count plus lazy cursor. It removed all `split_job` allocations, but scanned
separators twice. `candidate01/observed-count-cursor.patch` preserves that
investigation; the final candidate retains C0 `fuse_text_split.zig` selection and
existing private offset lists to avoid the second scan. Benchmark fixtures,
ports, oracles and historical evidence are unchanged.

## Validation

`textgap_split_test.zig` checks offset/count preservation, strict reader refusal,
uncached/cold/warm optimizer equality with an actual `inline_cfg` hit, no token
materialization in the scalar fold, exact-helper authority/signature refusal,
and native preservation of direct module call targets after CFG cloning.

The executable fixtures run under five checked native modes: default,
unoptimized, release, verified default and verified release. They cover empty,
leading/adjacent/trailing pieces, multibyte separators, Unicode octets, independent
escaping list/token values, source/separator mutation refusal, empty-separator
trap ordering, and an inlined reader's bounds trap with its source frame.

Builds use the pinned development environment and shared build admission.
Default seed provisioning is not used: the complete frozen C0 installation's
components/tools are copied, with hashes in `component-inputs.json`; only the
host is rebuilt using `seed-compiler`. No seed/pin or shared-cache edits occur.

`build.py` records exact unchanged guest commands and source/binary/host hashes.
`qualify.py` validates every text-group edge/default probe against the independent
oracle and records raw protocol/counters. Counted results require zero RC events,
uniqueness tests and managed exit-live bytes. Protocol elapsed fields are not
used as timing samples.

The immutable first-round host/guest files are in `.tmp/text-gaps/split/candidate01`,
with `build-receipt01.json`. BENCH owns exclusive paired timing admission.
Candidate01 passes all 100 runtime/counted probes and removes token allocations,
but misses Rust: large47.605us vs baseline65.222us/ZigFast57.583us/Rust27.288us;
small0.756us vs baseline1.132us/ZigFast0.953us/Rust0.540us. These are intermediate
medians; BENCH retains paired samples and confidence intervals. It is not the
final implementation performance claim.


## Candidate02 and bounded reserve candidate03

Candidate02 restores the exact C0 split lowering, retaining one separator scan
and a private managed offset table. The reader cleanup removes each temporary
owned token. The abbreviated BENCH screen (one warmup, five paired rounds) was
large28.870us/Rust27.690us (1.043), small0.501us/Rust0.541us (0.926).
This screen does not establish the final performance target.

Candidate03 changes only the reserved runtime split-offset subsection: initial
capacity is min(128, floor(input_bytes/separator_bytes)+1), with clamping before
addition. The empty-separator trap still precedes capacity calculation. The
native runtime test isolates UINT64_MAX capacity arithmetic and separately
searches a real8192-byte sparse span; it never searches beyond real storage.
All five focused tests and100 runtime/counted text probes passed; all three
source fixtures pass the compiler formatter. Native modes, trap ancestry and
warm cache equality are covered by the same tests. The exact host and guest
hashes/commands are in build-receipt03.json; raw qualification is preserved in
candidate03/{runtime,counted}. The full frozen installation and guests are in
.tmp/text-gaps/split/candidate03. BENCH owns fresh timing and adoption.

The table is managed storage and appears in text::split_job counters. Candidate02
small uses five allocations, four copies/grows, capacity0→8→16→32→64; candidate03
uses one allocation, capacity 128, no copies. Requested cumulative storage stays
2080bytes, while final small capacity grows from1056 to2080bytes and logical
transient peak from1600 to2080bytes. Large candidate02 adds six reallocations to
reach4096pairs; candidate03 adds five, starting128. Requested cumulative storage
falls from66592 to65568bytes, final capacity remains65568bytes. The counted
three-iteration totals are recorded in candidate03/allocation-accounting.json:
small3allocs/6264bytes, large3allocs/6264bytes plus15reallocs/190464addedbytes.
Both free all managed storage. malloc_usable_size accounts for the difference
between requested and countedbytes. Aligned realloc may transiently hold two
final-size buffers; libc internal peaks and slab raw malloc/free counts are not
inferred from these managed counters. A sparse long input grows requested final
storage from160 to2080bytes, bounded 128pairs regardless of input size.

For warmed split_job, runtime raw allocation API calls can be derived from
core_rt.c: candidate02 small has one aligned_alloc(1056), zero realloc and one
free; large has one aligned_alloc(1056), six realloc and one free in the captured
zero-realloc-moves run. Candidate03 small has one aligned_alloc(2080), zero
realloc and one free; large has one aligned_alloc(2080), five realloc and one
free in the captured zero-moves run. Earlier small blocks come from reused slab
classes; cold shared slab provisioning and thread registration are separate
64KiB aligned_alloc/calloc costs. A moved misaligned realloc can add another
aligned_alloc/free. These counts describe runtime API calls, not libc internals.


## Profile-supported candidate04

The candidate03 screen remained above Rust on large:28.676us versus27.638us
(1.0375); small was0.4969us versus0.5517us (0.9007). BENCH recorded 1420 native
samples without loss: core_span_find26.95% self, split_offsets13.32%, scalar
kernel22.56%, memchr@plt3.55%. The generic search frame was therefore a measured
cost rather than a conjecture.

Candidate04 keeps the bounded 128 reserve and routes single-byte separators to
bounded memchr directly inside offset construction. Empty source/trailing token
avoids the call when remaining length is zero; the original final empty token
is still written. Multibyte separators use the unchanged core_span_find path.
No source/port/lowering/checksum changes occur. Five focused tests passed again
with native fixtures in all five modes and the strict warm-cache miss check.
Guardian passed all 88 checks. All 100 runtime/counted probes passed with zero RC events, uniqueness tests and
exit-live managed bytes. BENCH owns the pending paired timing. Exact candidate04
host/guest hashes and commands are in build-receipt04.json.
