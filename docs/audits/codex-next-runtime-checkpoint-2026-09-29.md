# Runtime follow-up checkpoint, 2026-09-29

This is a partial WP-B3 checkpoint from approved main `80dd5190`, in the isolated
`codex/next-runtime-20260929` branch. B3 is still open: implemented checkpoints
below need combined acceptance. Startup image emission and the text follow-ups
are integrated; count-layout performance and the final frozen gate remain open.
Nothing from this lane has been merged into main.

## Equality allocations

Source `bd11421e` removes scratch allocation for scalar, text and bytes leaves.
Small structural comparisons use 32 pending and 64 visited pairs on the stack;
large values retain growable, nonrecursive worklists and cycle/DAG memoization.
Leaves compare immediately, so a large list or array of scalars does not fill
the worklist. Bytes compare their current storage range, including views.
Floats keep IEEE equality: a NaN remains unequal inside a box or collection,
even against itself, and signed zeros compare equal. Growth failure releases
all earlier scratch allocations. No guest allocation or safepoint is added.
The rules are EQUALITY-SCRATCH-1 and the existing RECURSIVE-VALUES-3.

A counted native probe compares the same text 6,000 times: the original source
uses 12,000 scratch allocations (2,304 peak bytes), the candidate uses zero.
Both return the same results and finish with zero live scratch bytes.
The dedicated allocation suite covers primitive values, text and byte views,
small lists, cycles, shared DAGs, a 1,024-node cycle and wide composites. It
injects failure at every actual growth allocation and checks cleanup.

The original and allocation suites pass ASan/UBSan. The complete native memory
and heap checks pass 31/31 build steps. The new recursive NaN/signed-zero guest
regression passes default RC, counting RC, GC stress and LLVM release, each
with one fresh executed test and no failures, cached results or skips. These
are focused checks; a final full B3 lane/integration gate is still required.

## Frozen performance evidence

The equality compiler SHA-256 is
`7a09405dac9d7f11352987331000c9b1f9c29c6cd3319b5136e121cc039bcf19`.
A later alias-proof install replaced the initial corpus builder's compiler
while it ran. That first `b3-equality` build is explicitly superseded and has
no accepted measurement. The original equality artifact was recovered by hash
and copied to `.tmp/equality-compiler/bin/mylang`; all 58 unique corpus builds
were then regenerated as `b3-equality-frozen` from that fixed binary.

Control binaries are copied from the final Phase A `m17-codex` gate and every
copied file is hash-verified. Control and candidate runs use CPUs 2, 3, 10 and 11,
with four workers and one instruction observation per row. The accepted GC
binaries and manifest are unchanged, and control/candidate per-row GC counts
are identical within each size. These are not median-of-three measurements.

| Size | QBE RC/GC geomean | LLVM RC/GC geomean | Output matches | Largest increase vs control |
|---|---:|---:|---:|---:|
| Dev | 1.059629 | 1.057831 | 86/86 | 0.134325% |
| Full | 1.057975 | 1.054226 | 86/86 | 0.148681% |
| Smoke | 1.098255 | 1.126671 | 86/86 | 0.002870% |

All 43 rows per backend at dev/full remain below 1.3x accepted GC. No row
regresses more than 1% against the fresh control, A1 or final A5. Smoke retains
the known short Lox startup cap misses and checks correctness/change limits.
The strict verifier records every row and movement in
`evidence/codex-next-runtime-20260929/equality-performance.json`.

Dev Lox `strings` improves 17.379% on QBE and 33.343% on LLVM; `string_equality`
improves 0.523% and 3.277%. Removing leaf scratch allocations directly explains
the main string savings, supported by the isolated allocation probe. Smaller
movements elsewhere can include generic comparison branches, generated binary
layout and startup/instruction observation variation; that attribution is an
inference, not a separate profile. The receipt retains all movements rather
than hiding small increases in the geomean.

## Mutable-argument exclusivity

MUT-EXCLUSIVE-PROOFS-1 removes the four callee-type alias refusals under value
semantics. RC's aliasability/type-containment scan is removed outright:
`runtime_mode.lowered` always selects GC for legacy sharing, so those RC
anchors cannot run in that mode. Plain-record move aliases, record-field
return and mut-list element-field return retain their conservative guard
outside value semantics. Root writes, observations, exits, pending references,
surviving temporaries and argument-overlap diagnostics still govern the proofs.
RC-INTERVAL-ANCHOR-3/4, QBE-MOVE-ELIDE-1 and COW-INDEX-RETURN-1 are updated to
state the resulting contract.

Five initial focused regressions pass. Broader checks pass all selected cases:
21 readonly-anchor, 29 value-semantics, 22 collector COW and 6 move-elision named
tests (each runner also executes 11 existing anonymous import blocks). Three
new guest cases start from shared inputs and mutate two disjoint arguments;
all 3 pass default RC, GC, GC stress, RC stats and LLVM release, with zero
failed, cached or skipped tests. A first proof test incorrectly expected every
plain-record copy to disappear under RC; selecting GC explicitly tests the
GC move pass, while other RC copies remain governed by their separate proofs.
Legacy RC token assertions were replaced by checking the actual collector
selection and absence of RC anchors. Both failed and corrected focused logs
remain under `.tmp/exclusive-*`.

Alias changes still need the final frozen lane gate and corpus comparison.
The equality performance receipt above predates those changes and claims only
the equality compiler. Raw logs and full JSON remain in this owned worktree's
`.tmp/` and `.tmp-rc-quick/` directories. Guardian passed all 88 checks on the
equality source commit; subsequent source verification remains part of the
ongoing lane work.

## Scope journal emission

RC-SCOPE-IL-1 emits the production begin/link operation and the spare-node
pin/single-entry unwind paths directly in IL. Exact native list descriptor
identity gates the backed-list path. Missing spares, metadata limits, count
limits, arenas, multiple entries and possible final releases use the existing
native helpers. Stats/sites builds retain the native attribution path. Native
offsetof/sizeof assertions pin every emitted heap/state/journal field.

LLVM marks runtime state accesses in a scope separate from frame, payload,
elements and prefix accesses. Four new named tests plus the existing marked
prefix regression pass (16 runner entries including 11 import blocks). Three
guest tests cover nested pins, backing growth, spare reuse and arenas; all
pass RC, GC, GC stress, RC stats and LLVM release, with zero cached, skipped
or failed tests. The initial guest build exposed dropUnusedRoots deleting all
heap field addresses. It now removes only the root-chain field at offset 16,
with a regression checking other heap/state addresses survive. Initial failed
logs remain as `.tmp/scope-guest-first-rc.*`; corrected receipts are
`.tmp/scope-guest-summary.json` and `.tmp/scope-focused-final.log`.

These checks do not replace the final frozen B3 gate or performance comparison.
The narrowed checkpoint used shared ABI4 prefix offsets and unsigned word
loads/stores, refusing capture at UINT32_MAX before changing state and sending
zero/final holds to native unwind. Its first compile caught a local name shadowing
the count helper; renaming it corrected that failure. The separate header tranche's
LLVM load-opcode correction was integrated before guest checks. The later ABI5
checkpoint described below restores wide counts and checks full-width conditions.

## Owning text dictionary keys

RC-DICTIONARY-TEXT-LOOP-1 extends the late fresh scalar-dictionary proof to
ordinary owning text keys. Only immutable text and scalar work is admitted;
those physical types cannot contain the root or run a destructor. The bounded
scan checks CFG entry, the original tail, COW effects and scheduled releases.
It preserves key journals and write/growth/refusal behavior and grants neither
cached-storage nor empty-drop authority. Publication, callbacks, references,
arena transitions and unknown shapes retain the existing check.

The actual knucleotide frequencies function now has one loop-entry uniqueness
check. Five named proof tests pass, plus 11 existing import blocks. New guests
cover owning slice keys, growth, empty loops, non-ASCII text, arenas and snapshots;
all 3 pass RC, GC, GC stress, stats and LLVM release without cached/skipped
tests. The first proof assertion expected a hold marker where the owning key
uses retain instead; the corrected test checks its retain and drop corridor.
Receipts remain under `.tmp/dictionary-text-*`. Performance acceptance remains
part of the final frozen B3 comparison.

## Primitive list images

LIST-LITERAL-PAYLOAD-1 packs inert literals of at least 64 primitive elements
before append desugaring. All ten native scalar widths and primitive-backed
domain chains preserve their exact little-endian bits. One bytecode payload
becomes one immortal, shared native list image. Its actual list-header
descriptor forces detachment before mutation, and its storage is immortal.
The lazy builtin list module is admitted before the first image clone; an
allocation refusal returns before publishing a copy. Legacy sharing performs
one fresh regional clone per evaluation. Static images grant no ordinary
sole-owner proof. Small, managed-element and nonconstant lists retain their
ordinary constructors.

A 1,000-element integer fixture emits fewer than 20 bytecode instructions and
30,000 IL bytes and builds/runs natively. The focused runner passes 17 entries
(5 named tests and 12 anonymous import blocks), including exact scalar bits,
malformed stride/bool rejection, legacy independent evaluations and physical
fresh-root conservatism. Four guest cases pass in each of RC, GC, GC stress,
stats and LLVM release: mutation/growth, snapshot pins, arena escape and
single ordered evaluation of nonconstant elements. There are no failed,
cached or skipped guest tests.

The first attempted packing point missed frontend append desugaring; moving
admission into collection lowering fixed it. Initial guest runs exposed the
lazy list-module registration requirement before the first image mutation;
the failed receipt is retained as
`.tmp/list-image-guest-registration-failure.json`. Two earlier guest syntax
failures and all focused logs are retained under `.tmp/list-image-*`.
This is focused correctness evidence. Compile-time measurements, full runtime
checks and combined corpus acceptance remain pending.

## Immortal list elements and creation regions

The next checkpoint also packs literal str/bytes elements, including empty,
non-ASCII and arbitrary-octet values. A checked count/length framing carries
their contents without runtime addresses. IL names canonical child literals
and symbolic parent relocations; both pools sort independently of physical
unit order. Module compilation retains the parent markers with the literal
and RC-site facts. There is no per-element allocation or token glue.

One native image evaluation shares on an ordinary heap and clones into the
current region inside an arena. This preserves the lifetime of creation even
when the first write happens later. The first owning-text arena regression
exposed an older immortal header receiving a younger text; regional evaluation
corrected it. An older image still refuses a younger value through a mut call,
under RC and GC stress. A direct store is rejected even earlier by E_ARENA_ESCAPE;
the runtime refusal fixture therefore uses the actual indirect call boundary.

The focused runner passes 20 entries (8 named, 12 anonymous), including
1,000-element str/bytes native executions, corrupted framing and UTF-8,
nonvacuous reversed physical units, and the older-root runtime refusal.
The failed module marker receipt is `.tmp/list-immortal-missing-marker.*`;
the failed region receipt is `.tmp/list-immortal-first-mutation-failure.json`.
All corrected receipts remain under `.tmp/list-immortal-*`. Full native,
guest-mode and module-oracle acceptance is recorded in the subsequent evidence.

## List-image receipts and compile observations

The frozen static-list source is `8f67ab8a`, compiler SHA-256
`4f37d5a8e78c8c064e88249e6f95ebd929b78c222aa17bd1697be09f5bea82af`.
The full native targets pass 31/31 steps (30 C families). The eight named list
checks plus 12 imported blocks pass 20/20. All six guest cases execute freshly
in each of RC, GC, GC stress, stats and LLVM release, with no failure, skip or
cached result. Four strict whole/module oracles (RC, GC, stats, sites) each
compare two modules, all 12 units and metadata, and byte-identical executables
that invoke the six cases and print `list-image-ok`. Reference failures are zero.
The source projection adds one explicit module header to the guest library on
both sides; it does not alter the test bodies. Earlier header/Stream driver
mistakes remain failed logs, excluded from acceptance.

After merging frozen text `458b9dfc` and image emission `2dbeecae`, an additional
integration test stores a 160-scalar indexed non-ASCII literal in a static list,
detaches its parent, and reads across the sample boundary and through a tail.
The combined focused run passes 21/21. A test-fixture Zig syntax mistake was
corrected before this run; the commit gate's structural checks alone did not
validate that syntax.

Compile observations use the approved-main Debug compiler and the frozen
static-list compiler on identical sources. Each role/backend uses its own
runtime cache, warmed by its first eight-element row; source objects are cold.
Admission waits are excluded. These are single observations on a shared
machine, not medians or corpus performance acceptance.

| Elements | Integer QBE control/candidate | Text QBE control/candidate | Bytes QBE control/candidate |
|---|---:|---:|---:|
| 250 | 4.001 / 0.391 s | 5.038 / 0.441 s | 4.973 / 0.550 s |
| 1,000 | refused / 0.397 s | refused / 0.546 s | refused / 0.586 s |

Every successful binary prints the expected count and returns zero. Integer IL
at 1,000 elements shrinks from 6,354,963 bytes / 225,024 lines to 26,163 bytes /
431 lines; immutable children add linear symbolic data, preserving bounded
instruction lowering. Eight-element lists retain ordinary constructors.
All nine candidate LLVM LTO configurations with retained debugging fail to
link `myl_rc_generated_image`; the assembly scanner dropped weak directives
after its final probe-data section. This pre-emitter result is explicitly
rejected for LLVM acceptance, and the scanner correction plus a combined rerun
remain required. LLVM `--release` guest tests above use different flags.

The exact observations, generated experiment sources, failure logs and verified
receipts are under `evidence/codex-next-runtime-20260929/list-images/`.
Guardian source-checkpoint feedback is committed as `db487e44` in its own repo.
Final combined broad tests and corpus acceptance remain pending.

A subsequent combined checkpoint `264e1c3c` (text, static image emitter, and
incremental-build source) uses frozen compiler
`607bade9fae178dc6725bc347ac1e7863e43f6448a6d3feaec7e7c0415b4466c`.
All nine sources now build on both backends, with all 18 outputs/statuses
verified. At 1,000 elements QBE takes 0.337 / 0.467 / 0.551 s for integer /
text / bytes; LLVM takes 1.525 / 1.480 / 1.770 s, against the control's
23.929 / 27.382 / 29.091 s. These remain single shared-machine observations.
New strong image definitions make this combination link; the separately
committed assembly-filter fix `354d9ddd` verifies image-free and GC full/ThinLTO
boundaries, so an emitted image cannot hide the original weak-directive bug.
The combined scale receipt retains the prior rejected results unchanged.

## Imported artifacts and constructor authority

Independent review at `91bb0769` reproduced three malformed-input defects:
a packed list could also carry an embedded blob, contradictory signature-only
dependencies were accepted in interface order, and a decoded physical body could
carry another function's identity. The wrong identity could grant a false
readonly certificate by treating a printing-helper call as self recursion;
the same body with its correct ID receives no certificate. No well-formed
guest miscompile was reproduced. The four original failing rejection tests,
minimal source and review are retained in
`evidence/codex-next-runtime-20260929/artifact-admission-review/`.

Root `4fce2270` rejects simultaneous packed and embedded constructor authority.
The focused runner passes 22/22 entries, including valid integer/text/bytes
payload controls followed by rejected blob additions. Module checkpoint
`96b05480`, integrated at `0801373b`, binds decoded IDs to semantic names and
compares normalized signatures against both duplicate and original declarations.
The independent reviewer confirms the original four regressions are corrected,
but reproduced one additional conflict: normalization discarded an explicit
`declared_mutates` qualifier. Module follow-up `9789436d`, integrated at
`18c173dc`, retains that declaration while projecting out inferred/body-local
facts. The final independent review passes 8/8 cases with no skipped or cached
verdicts. It verifies both conflicting declarations and matching declarations
with differing local/inferred facts, preserving caller write authority.
Original failures, the intermediate 6-pass/1-fail result and the corrected
fixture/report/pass receipt remain separate. A subsequent inspection reproduced
two explicit-policy conflicts: host effects and callback effect ceilings.
Checkpoint `a3fb19fc`, integrated at `cae9c833`, retains host/C ABI effects and
explicit bound presence/allowed effects while erasing bound source spans and
ordinary inferred effects. The focused physical checks pass 39/39; the independent
review passes all 14 cases, including both conflict orders, original-declaration
checks and equal-declaration controls. The original two failures and corrected
logs, source and review receipt are retained in `fixes-a3-effects-final/`.
The final combined gate and runtime-dependent module comparisons remain open.

At `0801373b`, frozen Debug compiler
`e692c195934c7831937a0d3c95fc756324c0454f25cdab78355309f70c3e8375`
passes the strict list-image whole/module comparison in RC, GC, stats and sites.
Each compares two interfaces and all twelve units, with zero reference failures
and one byte-identical executable pair. All eight binaries execute the six
regressions, print exactly `list-image-ok\n` and return zero. These are narrow
composition checks, not the final combined source gate.

## Count layout and combined performance remain open

The private ABI4 prefix uses two 32-bit counts and a retired-link union while
preserving the existing common header. The single-count census found a live
hold with zero owners, so the two counts remain necessary. Native overflow,
alias rollback, region and descriptor tests pass, but the standalone narrowed
layout fails the quantitative performance gate; its rejected rows are retained
in `experiments/wp-b3-layout-20260929/prefix/`.

The combined pre-acquisition-order source `91bb0769` was sampled using frozen
QBE/LLVM binaries, a fresh A5 control, unchanged accepted GC binaries and four
workers on CPUs 2, 3, 10 and 11. All 26 Lox output pairs match at dev and smoke;
GC instruction counts match between control and candidate. Dev has nineteen
rows above the 1% change limit, and QBE instantiation is 1.304219x GC, above
the 1.3x cap. Its QBE/LLVM instruction geomean changes are +0.449074% /
-1.011325%; these averages do not accept the failing rows. Smoke has twenty-two
rows above the change limit and retains known tiny-program cap misses.
The complete preliminary row receipts are in
`evidence/codex-next-runtime-20260929/pre-ordering-lox/`.

Checkpoint `cb4336cf`, integrated at `3fe434c9`, acquires admitted source edges
before copying generated values. It removes the second destination variant
dispatch and passes focused generated-C and guest checks. Its isolated timing
still has failing rows, so further bounded count-acquisition work is underway.
Final acceptance requires the complete combined source and all corpus rows;
no count-layout or combined B3 performance acceptance is claimed here.


## Wide-count correctness checkpoint

The replacement `1390e0c7` keeps two separate 64-bit owner/hold counts under
module/runtime ABI5. Prefix32 has owner/hold fields at -32/-24 and the common
mark/descriptor at -16/-8; immutable generated images retain their separate
ABI1. Narrowed ABI4 modules are rejected before registration. Checked count
acquisition still refuses before stores, and alias, arena and final-release
boundaries keep their transactional/native paths.

Its frozen Lox sample has all 26 output pairs matching and all dev rows at or
below 1.3x GC. Sixteen rows still exceed the 1% regression limit against approved
A5; the worst is LLVM invocation at +4.298989%. Wide counts alone do not resolve
the performance blocker. The failed rows, frozen compiler and unchanged GC
denominators are retained in `experiments/wp-b3-layout-20260929/wide-counts/`.

Correctness follow-up `790cdfb1` normalizes every l-valued scope pointer/count
condition to a w boolean before QBE jnz. A high-bit-only input otherwise appeared
zero to that branch. Independent review first reproduced this in an extracted
production predicate without a memory dereference; no native pointer-corruption
reproduction is claimed. The observed count crossing at 2^32 had safely taken
the native unwind path. The fix leaves w flags and heap/journal offsets intact.

The corrected source passes all 30 native C families, 16 focused scope entries
and 18 fresh scope guest executions across six modes. Two stale test-fixture
geometry failures were corrected to prefix32/slab80 and remain separate failed
logs. Its compiler SHA-256 is
`e58b3ba5140999ae7ff33ac9afc922279cdf936d70acf697e7d9104a08b31437`.
Independent corrected review passes all four extracted production-condition
cases (0, 1, 2^32 and 2^48) and all twelve actual QBE scope cases. All seven
wide-count successes take fast pin/end; three MAX refusals preserve counts,
pins, journal, budgets and spares, and final retirement/old-ABI refusal pass.
Every one of 29 emitted branch operands is a w boolean. The original1390
two-failure predicate result, safe native fallback and corrected790 source,
SSA, assembly, drivers, logs and 789-source-file hash receipts are retained in
`evidence/codex-next-runtime-20260929/scope-width-review/`. All 65 archived
files were verified against the independent manifests. A separate pre-store
overflow-check prototype is being evaluated for the remaining performance
rows; no final ABI5 or Phase B performance acceptance is claimed.


## Module-key equality and unchanged state

Module follow-up `a06ed822` hashes parameter-write flags only for allocation-free
callees, where the emitter actually reads them. Allocating calls retain
conservative imported host facts and all explicit mutation/effect authority.
The fragment encoding advances to v3. This removes six schematic key-only
differences without treating an empty host body as readonly. Its focused key
checks pass 12/12.

Follow-up `573ce9a4`, integrated at `aa454bc2`, avoids publishing identical
module state. It requires matching saved headers, row sets/order/cardinality
and complete row equality while both own/shared-standard locks remain held.
Fresh source/embed capture and current capability/policy/budget checks run
first; a zero compilation counter alone grants no skip. Removal, reordered
rows, missing state and changed shared headers retain normal publication.

The lane reports 246/246 focused entries, a 16-stage CLI state matrix and five
strict project fixtures with unchanged warm state bytes/inodes/mtimes. Its
strict corpus oracle now matches keys, IL, metadata and binaries for all 29
distinct programs (43 rows, 62 modules, 664 units, 62 interfaces), with zero
reference failures. These lane checks use its approved-base ABI3 runtime;
combined ABI5 corpus/oracle verification remains required. Independent frozen
source inspection found no false-positive state skip; the exact receipt and
reviewed source are in `evidence/codex-next-runtime-20260929/module-state-review/`.
It is source-review evidence, not an independent execution or timing result.
The earlier paired a3 check sample retained a 13 ms no-op regression despite
about 80% edited-check gains. The final seven-pair 200k check sample improves
no-op checks from 0.099882 to 0.091288 seconds (-8.60%), body edits from 0.757658
to 0.138253 seconds (-81.75%) and interface edits from 0.749255 to 0.149342
seconds (-80.07%). Forty-two warm measurements and two cold checks preserve
answers and rebuild counts. Shared-machine load rose from 32.21 to 43.72;
interleaved pinned pairs limit that confound without claiming the historical
0.025-second absolute timing was reproduced. The final module audit and all
926 raw archive members are integrated and independently hash-verified.

## QBE correctness follow-ups

QBE `phicopyref` reused a word branch predicate for a long phi and reused a
previous phi without checking its result class. Under pressure, a word spill
could be read as a long value; cross-class reuse could also lose sign bits.
Checkpoint `d0537d01` permits branch-predicate reuse only for word phis and
previous-phi reuse only for equal classes. The valid-SSA regression improves
from 36/44 to 44/44 passed, and the original reduction improves from 0/2 to
2/2. The composed `test-qbe-build` passes 29/29 steps and 139/139 tests, exit
zero. Input follow-up `e5ed9195` declares both new phi fixtures and two inherited
dictionary-loop fixtures. See the [phi audit](wp-b3-qbe-phi-2026-09-30.md) for
the unchanged raw failures, corrected results and source/artifact identities.

Independent selector review rejected frozen `f4b6647d`. Its arithmetic-zero
fold crossed a later external-address load whose selected `addq $8` overwrote
ZF: UINT64_MAX + 1 produced the correct payload but branch17 instead of23.
The parent selector returned23; both independently built and installed f4
QBE reproduced the error. Corrected `279501d1` permits only nop/debug-location
instructions between comparison and branch. Its independent 140 production
cases, 3,754 assertions across fifteen functions and the original failed case
pass, preserving admitted folds and comparison fallbacks. The separate rejected
and corrected archives retain 69 and 50 hash-verified members. This is scoped
selector approval; release-count review, composition and final performance
acceptance remain separate requirements.

## Preliminary non-Lox composition measurement

The Debug compiler at `e789a32d` has SHA256
`c76f443347eec255873c1fe16a5c17ed8c92da0896b49251c603f82c8d7bfc0a`.
This checkpoint includes wide counts, B1/B2/B4, text and phi fixes; it precedes
the increment/release/selector continuation. All 60 non-Lox dev output pairs
match the unchanged accepted GC binaries; all thirty rows on each backend
meet 1.3x. Four exceed 1% against A5: LLVM raytrace +1.601970%, QBE text_ops
+1.118819%, LLVM text_ops +1.140108% and LLVM alloc_churn +3.229847%.
QBE/LLVM geomeans are 1.045887x / 1.043466x. No performance acceptance is
claimed. Frozen compiler, 56 guest binaries, logs and full comparison are in
the integrator's `.tmp/phase-b-preliminary/` and `.tmp-rc-quick/` directories.


## Corrected release and publication reviews

The corrected selector and release continuation are composed at `7f5068a5`.
The independent release review passes 342 actual emitted cases in both candidate
and control, 22 checked/unchecked native cases and three repeated-alias cases.
Its 48-member raw archive is verified under
`evidence/codex-next-runtime-20260929/release-count-review/`. This is scoped
correctness evidence, with no independent LLVM, broad-gate or timing claim.
The earlier composed ABI5 module check at `e789a32d` passes the strict 29-program,
43-row byte oracle and four runtime fixture modes. Its 44-member archive is in
`preliminary-abi5-module-review/`; the final source must still repeat that matrix.

The frozen `7f5068a5` comparison matches all 258 dev/smoke/full outputs but is
rejected: 18 dev, 19 full and 24 smoke rows exceed 1%, and three smoke rows
introduce cap misses. All raw rows, unchanged GC identity and baseline controls
are preserved in `zero-combined-rejected-performance/`.

Private ordinary COPY publication at `ed48ecc8` reuses its admitted owner count.
The 64-bit overflow refusal precedes acquisition, and all later reachable work
consists of infallible stores and tests of loaded values. Independent candidate
list, dictionary and exact composed control each pass 774 emitted cases; native
checked/unchecked probes pass 20 each, aliases pass six, and both production CFGs
pass dominance and post-acquisition checks. The 89-member verified archive,
receipt and boundary report are under `publication-review/`.

Composed source `3226f1d6` builds all 58 corpus binaries and matches all 258 outputs.
Publication reduces the failing performance rows, but the checkpoint is rejected:
13 dev, 14 full and 19 smoke rows exceed 1%; the same three smoke cap misses remain.
Dev/full meet every 1.3x cap. Per-row approved and fresh A5 comparisons, compiler
and binary hashes, measurements and logs are in
`publication-combined-rejected-performance/`. These observations use the reserved
CPUs 2, 3, 10, 11 with one observation per row; averages do not waive failures.

Read-only allocation-churn profiling explains the primary LLVM cost. The frozen
A5 and `7f5068a5` symbol-preserving counterparts have identical allocated ELF
sections to their original binaries. Hardware adds 64,998,196 instructions and
Callgrind adds 64,996,984. Three million newly out-of-line list-readiness calls
contribute 60,000,016 self instructions; scope routines execute zero calls.
The precise LLVM inlining trigger and the smaller retirement alias explanation
remain unproved. The 80-member verified attribution archive and report are in
`allocation-churn-attribution/`. The minimal `79fd7e25` continuation preserves
the exact helper body and callable ABI while requiring LTO inlining. Its focused
native checks pass. The independent two-translation-unit ABI review passes
15 cases each in four C build modes, preserving external definitions without
LTO and valid callable addresses with LTO. Its 41-member verified archive is
under `plain-ready-review/`; the body and public declaration are unchanged.

Composed source `255cf730` matches all 258 outputs. Allocation churn improves
from +2.999% to +0.415% on LLVM, but a new +3.726% LLVM fannkuch regression
makes this checkpoint rejected. Twelve dev, thirteen full and eighteen smoke
rows remain above 1%, with two new smoke cap misses. Every dev/full cap still
passes. Exact rows and frozen identities are under
`plain-combined-rejected-performance/`. The agents are profiling the remaining
costs; final combined performance, module matrix and integration gate remain
required before the explicit approval to land Phase B.


## Frozen raytrace and text attribution

The read-only `7f5068a5` versus approved A5 study verifies identical allocated
ELF code/data for all four symbol-preserving binaries. Hardware and Callgrind
agree on the instruction deltas: about 13.47 million for LLVM raytrace and
17.90 million for QBE text operations. The complete 143-member archive,
source/command receipts, exact instruction histograms and scope limits are in
`evidence/codex-next-runtime-20260929/raytrace-text-attribution/`.

Raytrace's two hold-acquisition sites perform 3,368,136 acquisitions. Their
required overflow checks add three instructions each; an additional floating
zero initialization executes on every normal continuation. Eliminating only
that extra initialization would arithmetically reduce the observed increase
from about 1.068% to 0.801%, but no implementation gain is claimed.

Text's unchanged native view helper now runs out of line 190,000 times. The
combined view/long-piece cost rises by exactly 3,230,000 instructions. Other
costs include checked owner admission, retirement reloads and extra hash
probes. The precise inlining and alias-analysis triggers remain unproved;
all MAX guards and transaction ordering must remain. The isolated view-inlining
continuation is being tested separately; these profiles do not waive any row
or replace the final integration gate.
