# S2 Wave A implementation and validation

Wave A contains S2-0, S2-La and S2-Lb. The controlling specification is
`docs/design/new-core-s2.md`, particularly its accepted decisions in §12, and
`docs/audits/new-core-s2-implementation-plan-2026-10-05.md`.

The integration branch is `codex/new-core-s2-integration`, based on `9ee2a484`.
The three implementation agents use GPT-6.1-sol at xhigh in separate locked
worktrees. The pre-existing checkout and its unrelated edits are untouched.

## Baseline

- `test-core`: 147/147 passed; 85.38 seconds wall time.
- New-core compiler build: 2.34 seconds wall time; 1 second compile step.
- Initial old-core installation: 16.55 seconds, including 12 seconds producing
  the bundled runtime. This is initial setup, not a new-core rebuild measurement.
- Coverage: 2,269/3,509 functions accepted; 2,601 proven and 1,841 exact checks
  across 2,167 accepted functions with reported check counts.
- All fourteen S1 rows match reference checksums at both sizes and are below
  Zig ReleaseSafe (CPU 10, seven interleaved rounds).
- Baseline LLVM and binaries for all fourteen S1 rows and six S0 kernels are
  retained in this worktree's `.mylang-cache/wave-a/baseline/`; their hashes
  and build times are in `integration/baseline-code.txt`.
- The six S0 kernels match Rust and Zig checksums. The interleaved baseline
  timing self-check is in `integration/kernels-before.txt`: the two new-core
  entries use the same executable, demonstrating timing variation even with
  identical code. Code identity is the plan's alternative nonregression proof.
- All fourteen S1 rows have zero count updates in their innermost loops,
  according to the existing optimized-assembly counter. Cold allocation/copy
  calls remain in some loops; the complete baseline counts are in
  `integration/rc-counts-before.txt`.

The supporting baseline logs are in `integration/`. Package commits,
integration checks, and remaining refusals are recorded below.

## Preliminary iteration candidate

The staged `f831003c` candidate passed 147 core tests in 92.01 seconds and full
conformance at debug/release (747 matching, zero mismatching, 745 unsupported).
All twenty S0/S1 function-definition comparisons were identical. The fourteen
S1 rows matched their reference checksums. Logs have the `preview-lb-` prefix.

A subsequent read-only audit found omitted comprehension paths and immutable
text/bytes places beneath mutable ancestors. The staged merge was withdrawn
before committing, and the final package corrected those paths. These
preview results do not qualify the final package head.

## Accepted iteration merge

S2-Lb's final head is `5dbfdd80` (including its preliminary `f831003c`). It is
merged as `48140989`. The package's final full old-core gate passed 115/115
steps; RC and GC-stress each passed 1,616 fresh cases across 240 programs.
QBE passed 518/518 tests. QBE build, formatting, Guardian's 88 checks and the
isolated 147-test core checkpoint passed. The package README distinguishes
the preliminary and final evidence, and cached/skipped results from fresh ones.

The staged integration tree passed these checks before the merge commit:

| Check | Result | Command time |
| --- | --- | --- |
| Core build | compiler compile step 1 second | 2.31 s |
| Old-core install | 19/19 steps; compiler 6 seconds, runtime generation 15 seconds | 27.56 s |
| Core suite | 147/147 | 91.85 s |
| S0/S1 definitions | all 20 identical to baseline | 1.10 s |
| Full conformance | each mode: 747 matching, 0 mismatching, 760 unsupported | 332.97 s |
| S1 rows | all 14 at both sizes; checksums equal; each within 1.10 times Zig | 179.11 s |

Conformance and row building overlapped the language package's full gate;
the core checkpoint was isolated. Logs have the `after-lb-` prefix. The
combined mut-callee/iteration fixture passed after the language merge, as recorded below.

## Language discovery gate

The first complete language gate exposed fixtures that still depended on
receiver/mut overlap, native optimization assertions for the retired pending
receiver form, and unstable metadata for generated callback adapters. This
failed run is discovery evidence, not a package qualification.

The fixtures now split each mut call from its receiver update. Native tests
assert the resulting pin scope and caller-storage behavior. Callback adapter
locations and their metadata digest use a stable synthetic identity; ordinary
functions retain source-dependent metadata. Focused metadata tests pass 43/43,
CLI tests 6/6, value-semantics guests 145/145 in both RC and GC-stress, and the
native follow-up 17/17. The affected compiler rebuild took 6.21 seconds.

The second frozen full-gate run began at 14:59:06 UTC. Source hashes and
the full-gate logs are retained in `s2-la/`; failed runs are discovery evidence.

That rerun exposed one genuine callback ABI regression in the pre-existing
`mut_argument_places::test_indirect_later_callback_keeps_the_selected_place`.
A later argument replaces a previously selected dictionary entry; the direct
payload ABI keeps the selected old value, while the new callback storage ABI
addresses the overwritten entry. The required answer remains `1321`, with the
parent's replacement still `21`. This fixture's contract is preserved; a
compiler correction was required before acceptance.
Final inspection also found a GC-stress-only abort in
`rc_site_eliminations::test_managed_elements_and_nested_record_fields_relocate_whole_values`,
which passes under RC. The rerun completed in 935.97 seconds of command time:
110/115 steps succeeded, RC passed 1,598/1,599 and GC-stress 1,597/1,599 guest
cases. All 2,983 selected Zig tests passed; 30,399 were skipped by sharding.
The two guest failures and their module-oracle propagation disqualified that run.

Focused follow-up also reproduced a pre-existing S1 new-core bug with an
interior list mut argument whose later argument replaces its parent entry.
The frozen baseline native compiler prints `721 1 21 1 7`; its new core prints
`2121 2 21 1 7`. Current new-core debug and fact-verified release reproduce the
same wrong answer. The source, exact commands and baseline compiler hashes are
in `integration/core-selected-place.my` and
`integration/core-selected-place-diagnosis.txt`. A captured nonempty mut place
whose root version changed during later argument evaluation must be refused
precisely until its selected-place semantics can be represented. Whole-root
arguments keep their existing current-binding reread. This does not change the
IR shapes or the native language contract.


The callback correction compares the current selected entry with the captured
entry before publishing call roots. If a later argument replaced that entry,
the callee receives an owned fallback for the original selected value. An
unchanged entry receives writes through its actual caller storage. Focused
cases retain the original `1321`/`21` contract and cover direct and indirect
calls, replacement, forwarding and snapshot lifetimes.

The GC abort came from treating a returned collection payload as a raw
`ref_local` address. GC roots now classify only a whole reference operand as
an address; borrowed call results retain element provenance and are rooted as
values. A further focused test found GC's direct payload path reading the
pre-argument whole-local binding after a later argument had rebound it. That
path now reloads the caller variable, matching RC, callback calls and the new
core's accepted whole-variable rule.

The pre-existing new-core interior-place bug now has the precise refusal
`interior mut argument ancestor changed during later argument evaluation`.
Changed indexed and field paths are tested; stable interior paths and current
whole-root reads remain supported. This conservative check may refuse a
conditional or disjoint sibling write under the same root. It does not alter
`ir.zig` or assert a new optimization fact.

The corrected language compiler passed focused guests 27/27 under RC,
GC-stress and release; counted RC execution retired all 785 allocations and
balanced all 343 journal holds. Callback/ABI unit selections passed 29/29,
warm ABI-edit guests passed 12/12, and the original mut-argument file passed
15/15 fresh cases in each of those three modes. The isolated core checkpoint
passed 150/150 in 90.79 seconds, retaining all 121 baseline pinned contracts.
Its stale `v_snapshot` expectation was migrated to `1 7`: the captured readonly
value remains `1`, while a pure whole mut rebinding reaches the caller as `7`.
Old RC, GC-stress and release agree on that output.

The third frozen full old-core gate began at 15:48 UTC. The preceding isolated
old compiler source rebuild took 5.50 seconds. Plain installation took 16.95
seconds with the compiler cached and bundled runtime archives accounted for
separately. That frozen test run passed 115/115 steps in 905.14 seconds: all 2,983
selected Zig tests passed, with 30,399 sharding skips reported separately.
RC and GC-stress each passed 1,608 fresh cases across 241 programs; the
whole/module executable oracle matched all 340. Both value-semantics runtime
runs passed 145/145. QBE passed 51/51 steps and 519/519 tests in 78.31 seconds; QBE build
passed 29/29 cached steps in 0.25 seconds. Focused mut conformance across
47 tests has 16 matching and zero mismatching in each mode, with leakcheck
and fact verification. The 31 refusals are dictionary (19), callback (5),
changed interior ancestor (4), set (2) and fixed array (1). Package
Formatting passed 2/2 steps in 0.21 seconds; executable docs passed
26/26 steps in 0.95 seconds and doc coverage is clean. The final isolated
pre-commit core checkpoint passed 150/150 and 5/5 steps in 114.56 seconds,
with compiler and test compilation cached. The production source, tests and
documentation still match the frozen hashes. The clean package head is `36b8d5dd`. The staged La/Lb merge passed
150/150 core tests in 92.33 seconds, a 2.19-second core build, and a
23.50-second old install (compiler step five seconds). All twenty benchmark
function-definition comparisons are identical (2.73 seconds). A read-only
merge audit confirmed both checker resets, caller-binding semantics, test
imports and fixed-array migrations. The first full staged comparison stopped on a single file-level setup error:
`mut_rebind_modules` lacked an explicit module header. The old test runner
synthesizes one, while the new runner applies the normal frontend import rule.
Both modes reported 765 matching, one file error and 769 unsupported across
1,536 tests. This is not accepted qualification; its five logs are preserved
under `integration/after-la-initial/`. The imported-mut fixture received
its explicit header, followed by fresh focused runtime checks and a complete
staged qualification rerun. Fresh RC, GC-stress and release each pass
both imported tests; debug and verified-release reports preserve both names
and precisely refuse dictionary/function-value source lowering. Those checks
are in `integration/module-header-fix/`.

The corrected staged tree passed 150/150 core tests in 92.08 seconds and
all twenty unchanged benchmark definitions in 1.06 seconds. Full conformance
passed in 33.23 seconds: each mode has 765 matching, zero mismatching and
771 unsupported out of 1,536 tests. The six combined mut-callee/iteration
cases pass fresh in RC, GC-stress, release and GC-stress release, with empty
stderr and no cached/skipped/unsupported cases. New-core debug and verified
release precisely refuse all six until Wave B's live-place/function-value
lowering; there are zero mismatches and no leak/fact failures. All fourteen rows matched reference checksums at both sizes and passed
the 1.10-times-Zig bound in 69.87 seconds. The accepted language merge is
`84716fb0`; its normal whole-tree commit hook passed all 88 Guardian checks.

## Corpus audit disposition

The initial external Lox audit on `bench/lox-mylang` found three receiver/mut
overlaps in `resolver.my` (lines 195, 251 and 259). Its older `class` syntax prevents a
checker audit against this base; the source audit identifies exact prefix
overlaps through `r`. The user authorized continuing Wave A with documented
two-statement migrations and no edits to that external checkout. The package
audit includes the original statements and proposed replacements.

The full language gate later exposed another occurrence in the pinned
pre-marker Lox test fixture. Its canonical external counterpart is `heap.my:300`,
`blacken(mut rt, rt.marker.gray.pop())`. The documented migration first saves
the popped value, then calls `blacken(mut rt, gray)`. The internal historical
fixture is migrated while preserving its 91 marker edits. The same authorized
documentation-only disposition applies to this fourth external occurrence;
the external checkout remains unchanged.

The package audit found no receiver-overlap diagnostic or whole mut collection
parameter rebinding in the in-repository example/benchmark sources it scanned.

The exact-base compiler already panics when its sixteen-bit mutation/origin
analysis needs the seventeenth parameter of a mut or retained-value signature.
The language package records reproductions for a mut list, a readonly list,
and a readonly string. Per plan §6 this existing old-core bug is reported
without widening or replacing that analysis in Wave A.

## Timing protocol

Running two core suites alongside the full old-core gate made the unchanged
147-test baseline take about four minutes and the new 183-test suite take
316.82 seconds. The latter exceeded the five-minute stop threshold and was not
accepted as an exit gate. With the gate slot held to exclude the full old-core
gate, the final 183-test suite passed in 109.55 seconds, excluding admission
waits. The language compiler's source rebuild likewise fell from an observed
11 seconds under contention to 3.29 seconds in an isolated run. Core timings were isolated by explicit coordinator scheduling. During the
third language gate, a read-only check found that direct nesting of the slot
wrappers reused descriptor 9 and dropped the outer gate lock. The active gate
received a separate gate lease; subsequent nested commands use a waiting bash
parent to retain the gate descriptor while the build child acquires its own.
The integration runner uses that corrected wrapper for `test-core` and records
command time separately from admission waits. Existing explicit serialization
prevented concurrent package gates; no result relies on the dropped lock.

The final fast checkpoint preserves its original 31 file sections and 121
passing contracts byte-for-byte, then appends four Wave A files with 16 new
passing contracts. The temporary pin candidate passed old/debug/release
comparison before admission. The expanded 35-file checkpoint passed all
186 tests in 112.78 seconds, within the five-minute limit. The original
11,194-byte prefix has SHA-256
`068957b374bc3cd306fa23e33a7aa248984806f7915a7a4e2ae081e4489cb3d9`;
`integration/pins-final.txt` records the preservation proof. Full-corpus
conformance remains a separate gate.

A later language install attempted during the iteration package's full gate
again exceeded the source rebuild limit (19 seconds compiling `mylang`).
Dependent builds were stopped. The final language compiler subsequently passed
its isolated source rebuild in 5.50 seconds before its accepted package gate;
the contention measurement does not waive the ten-second limit.

## Runtime-levers handoff

S2-Lb owns C4's front-end and old-core semantic half: live-place desugaring,
per-path iteration guards, and the D1 language tests. S2-I's new-core half and
the remaining C4 reference-counting removal work belong to later work.
This is the coordinator handoff record; the available chat tools do not expose
a cross-chat send operation, so no delivery to another chat is claimed.

## Scope boundary

This report is for Wave A. Dictionary/text implementation, function-value
source lowering, sorting and fixed-array source lowering remain Wave B work.
It is not the full S2 exit report or the S3–S5 go/stop checkpoint.

## Staged IR foundation qualification

The foundation package is `6fff0fe6`. It adds 36 core tests: valid LLVM for all
25 operations, operand/result/probe/view/signature rejections, and executable
array, indirect-call and character cases. Managed arrays cover register and
`sret` results, ownership, leak checks and fact-verified release. Source features
whose builders remain stubs refuse precisely; runtime placeholders stop before
an answer is observable. The package evidence is in [s2-0/README.md](s2-0/README.md).

The frozen staged compiler passed:

| Check | Result | Command time |
| --- | --- | --- |
| Core build | compiler step one second | 1.90 s |
| Old install | compiler five seconds; runtime generation thirteen seconds | 25.57 s |
| Initial staged core | 186/186 | 119.05 s |
| S0/S1 definitions | all twenty identical to baseline | 2.46 s |
| Full conformance | debug/release each 765 matching, zero mismatching, 771 unsupported | 123.33 s |
| Six combined cases, new core | precise live-place/function-value refusals; zero mismatches | 1.11 s |
| Fourteen S1 rows | equal checksums, both sizes, each within 1.10 times Zig | 64.22 s |
| Four-file pin candidate | sixteen passing contracts, zero mismatches | 7.67 s |
| Expanded 35-file core checkpoint | 186/186 | 112.78 s |
| Full leak/fact sweep | debug/release each 765 matching, zero mismatching, 771 unsupported | 51.95 s |
| Coverage, four checked children | 2,321/3,619 accepted functions | 4.24 s |
| Six S0 kernels | all reference checksums equal at both sizes | 28.41 s |

The source, fixtures, SPEC and pins were frozen at 16:44:58 UTC. Their manifest
is [integration/frozen-tree.json](integration/frozen-tree.json); its aggregate
SHA-256 is `56f2d5d0480fe754f6e97bebd965f8fefb3e8edfea30978f9e2257f721ec2bac`.
The exact inherited fuzz generators, extension, wrapper and six-case fixture
have separate qualification input hashes. Compiler binary hashes are recorded.
The IR hash is `07939955320061b4bec0fd3441dc1decb763fc1ba20b8f59fcbf1b50c13d5e33`.
The final fuzz matrix and full old compiler gate are in progress; the staged
IR merge is not accepted until those exit checks pass.

The first aggregate old-gate attempt was stopped after two incremental-project
drivers failed before completing a comparison. Its TMPDIR was beneath
`.mylang-cache`, which those drivers exclude by absolute path component; their
copied source lists were empty. The corrected run uses `.tmp/final-old-qualification`
on disk. No compiler or fixture changed. The failed attempt is retained as
[setup discovery evidence](integration/final-old-tmpdir-discovery.json), with its
aborted log, and supplies no accepted qualification.

## Performance and coverage evidence

[Fourteen-row ratios](integration/rows-summary.md) summarize the complete
[old/new/Rust/Zig cycle tables](integration/wave-a-rows.txt). Every inner loop
has zero reference-count updates; [the assembly counter](integration/rc-counts-final.txt)
also records cold allocation/copy calls. All six S0 kernels have identical
emitted function definitions, satisfying the plan's code-identity alternative.
The [complete LLVM module comparison](integration/llvm-module-identity.txt)
also confirms that the only differences are three unused declarations; their
symbols appear nowhere else in any of the twenty modules.
[Interleaved timings](integration/kernels-final.txt) still show variation with
identical definitions, including the documented binary-search layout noise.

Coverage grew from 2,269/3,509 to 2,321/3,619 accepted functions as the corpus
also gained tests. Proven/exact check counts grew from 2,601/1,841 to
2,651/1,925 across 2,219 accepted functions with reported counts. These are
per-function checks from the inherited sweep.
[All 66 remaining refusal reasons](integration/coverage-refusals.md)
cover 1,298 refused functions; complete raw child reports and exit codes are
in [coverage-final](integration/coverage-final/summary.json). The full conformance
report separately lists every unsupported-test reason and its file. Dictionary,
bytes, fixed arrays, function values and live-place lowering still require Wave B.

[The selected-interior reproducer](integration/core-selected-place-final.txt)
is precisely refused at debug and verified release, with no binary produced.

## Completion and acceptance (Claude integrator, 2026-10-05)

Codex stopped with S2-0's merge staged but not committed. The S1 fuzz job had failed
(attempt 1), the S0 and RC fuzz jobs had been interrupted, and `test-qbe`, `test-qbe-build`,
`fmt-check` and the six-case combined fixture were still pending. All of it is finished
here. Wave A is accepted at the head that adds this section.

**Commits on `codex/new-core-s2-integration`:**
- **`5ed9f18d`:** the staged S2-0 merge, committed as qualified, apart from the fuzz failure below.
- **`44831afb`:** `own: never empty a record phi`.
  - **The crash.** Attempt 1's S1 fuzz failed at case 67 with a release build crashing at exit (SIGSEGV), but only under `MYL_CORE_LEAKCHECK=1`. Debug builds, `--verify-facts` builds, `--no-facts` builds and the old core all print the right output. The pre-Wave-A baseline compiler crashes too, so this is an S1 bug, not a Wave A regression.
  - **The repro.** Reduced to 18 lines, now `test/core/rc_phi_fields.my`.
  - **The cause.** Release unswitching duplicates a loop that appends to `b.items` (`b` is a record whose list field is shared). The two versions' exits join `b` in a phi whose only use is the read of `b.items` for the next loop.
    - `takeFields` marked that phi *emptied*, which gives it class `.none`. For a phi, that also drops the consumption of its operands on their edges.
    - So `b` was released on both exits while the field read still used it, and the field was released again after the second loop.
    - The second release decremented the "count" of a freed block. That word is the free list's link, so the leak check's free-list walk crashed. Without the leak check, the program exited before walking the list.
  - **The fix.** A phi is never emptied; it stays an ordinary owned record.
  - **Regression test.** `NEW-CORE-RC-12` checks the exit status and stdout as well as stderr, because a crash leaves stderr empty. It fails on the unfixed compiler (exit 139) and passes with the fix.
- **`1f41e718`:** the unit-shard memory ceiling goes from 2G to 2.5G.
  - Shard 11/12 peaked at 2.30G under load and **2.18G alone** (`final-old-shard11-isolated-rss.log`), against its 2G declaration.
  - Zig's runner reports the overrun but keeps the step green.
  - `docs/tooling/runtime-budgets.md` still said 1 GiB; it is corrected.

**Final qualification on the fixed head:**

| Check | Result |
|---|---|
| `zig build test` | 115/115 steps; 2,993 selected tests passed; exit 0; 1,004 s; the largest step about 2G, inside the 2.5G ceiling, with no overrun message (`final-gate-test.log`) |
| `zig build test-qbe` | 51/51 steps, 519/519 tests |
| `zig build test-qbe-build` | 29/29 steps |
| `zig build fmt-check` | exit 0 |
| Six combined mut-callee/iteration cases, old core | 6/6 passed in RC, GC-stress, release and GC-stress release; all fresh (0 cached); empty stderr (`final-six-*.json`) |
| Fuzz S0 (200 cases, seed 31) | qualified: 3,000 comparisons, 0 mismatches, 0 fact failures |
| Fuzz S1 (200 cases, seed 42; case 67 included) | qualified: 3,000 comparisons, 0 mismatches, 0 fact failures |
| Fuzz RC (200 cases) | qualified: 1,800 comparisons, 0 mismatches |
| Fuzz rebinding (200 cases) | qualified: 3,000 comparisons, 0 mismatches |
| `test-core` (gate slot held) | 187/187, 115 s |
| S0/S1 benchmark definitions | all 20 identical to the baseline |
| Full conformance | debug and release each: 765 matching, 0 mismatching, 771 unsupported (1,536 tests) |
| Leak and verify sweep | 765 matching, 0 mismatching, no leaks, no `R_CORE_FACT` |
| Combined fixture, new core | 6/6 precisely refused (Wave B lowering), 0 mismatches |
| 14 S1 rows | equal checksums at both sizes, each within 1.10× Zig ReleaseSafe (`final-rows.txt`) |

**Attempt-1 evidence** is kept under `fuzz-*-attempt1*`. It was not used for acceptance.

**Review notes for the user and for Wave B:**
- **D1 now covers fixed arrays too.** S2-Lb applies live-place iteration to `[N]T` (PY-ARRAY-ITER-1/2), which used to iterate a copy taken at loop entry. This follows decision 8's rule (a loop over a place re-reads the place), but it is a behaviour change the user did not discuss explicitly.
- **The interior-mut refusal is conservative.** The new core now refuses an interior `mut` argument whose ancestor a later argument changes (a pre-existing S1 wrong answer, found here). The check may also refuse a disjoint sibling write under the same root. S2-I or later can narrow it.
- **The Lox port needs four two-statement migrations,** documented but not applied, because that checkout is outside this repo: `resolver.my` lines 195, 251 and 259, and `heap.my:300`.
- **One old-core bug was reported and not fixed:** a panic when the mutation/origin analysis meets a 17th parameter. Reproductions are in the S2-La evidence.
- **The fuzz harness was blind to crashes.** `own_test.zig`'s leak sweep only compares stderr, so a crash that prints nothing passes it. `NEW-CORE-RC-12` closes this for the new fixture. A follow-up could make the sweep check exit status for every fixture.
