# Native trig module-interface qualification repair

Source checkpoint: `e88fcf3c98d6f0e0090e0719472e1081fb81f119`, following the
initial native trig implementation `0289edb6`. The four standard broad
compiler targets now pass on this source, and the committed application pin
is installed. The focused and broad receipts below retain their separate
provenance. The requested remaining common-lane checks also pass, with the
two previously recorded GC-stress-only fuzz findings retained. This report
does not claim the full 27-step integration or performance matrix.

Importing `math`, even without calling trig, exposed a module-interface
failure. The new one-operation `sin` and `cos` wrappers were eligible for
inlining, so their stored interfaces retained `__float_sin` and
`__float_cos`. Their reconstructed text had the `@stdlib/math.my` path but
did not match the exact embedded source required by the private-intrinsic
parser gate. The module child rejected it with `E_INTERNAL_NAME` and the
coordinator fell back to whole-program checking. The program's saved module
state stayed empty; subsequent checks rewrote that partial state. This
explains the module-build differential, unchanged-state oracle, and shared
standard-module compilation failures in the original broad gate. Its raw
logs remain separate and untouched. The integrator recorded seven failed
build steps and two actual CLI test failures; cold LLVM `libunwind.a`
archive-command stderr was a separate failure.

An owned absolute-cache reproduction established child status 1 for the
stored interface, status 0 for exact embedded `math` and whole-program
checking, and unchanged state bytes/inodes/mtimes for a no-import program.
The failure therefore did not depend on the gate's relative cache paths or
demonstrate a defect in the unchanged-state guard itself.

The repair gives both wrappers meaningful IEEE guards: sine returns the
same signed zero, cosine returns one at either zero, and nonfinite inputs
return `math.nan()`. Finite values still reach the native intrinsic. These
guards naturally keep the larger wrappers out of the inline-body interface
projection, matching the existing `sqrt` wrapper. Parsing trust, the
inliner's policy, module scheduling, and native range reduction are unchanged.
All five final focused standard interfaces omit the private trig bodies.

The added generic-caller regression then exposed a separate symbolic-checker
bug. Its unary branch expected raw `u64` operands for every intrinsic. A
whole-program generic trig caller failed with `E_GENERIC_TYPE` while the
module check using declared stand-ins accepted it. The approved `2c05c41e`
pin reproduced the same issue for generic `math.sqrt`, establishing that it
predated native trig. Symbolic checking now uses the existing shared
`float_intrinsics.floatwise` predicate and float domain for these operands;
the bool and raw-u64 paths keep their previous rules. The unary arm was
extracted into a private helper after Guardian rejected complexity 26/25.
A distinct primary specification/test link was added after Guardian rejected
behavioral lines linked only through `spec-case` comments. No exemptions or
test weakening were used. The initial guards-only rejection is retained.

Focused results on the final source:

| Check | Result |
| --- | --- |
| Debug installation | 12/12 build steps; Guardian 88, diff-scoped |
| Source commit Guardian | 88/88, whole tree |
| Generic/module/no-op CLI regression | 1 named + 2 unnamed tests passed |
| Native bits/private-name rejection unit | 1 named + 12 unnamed tests passed |
| QBE trig guests | 4 fresh passes, zero failures/cached/skipped |
| LLVM trig guests | 4 fresh passes, zero failures/cached/skipped |
| Previously failing module-check entries | 5/5 equal, zero reference failures, all per module; 11 own modules |
| Incremental build differential | Pristine + one comment edit: two executable byte/run comparisons, six compilations, four reuses, zero mismatches |
| Original generic `sqrt` reproduction | Corrected whole-program check exits 0 |

The module-check oracle also confirms unchanged own and shared standard-state
identities. The CLI regression requires actual own-module result files before
deleting them and checking again; a silent fallback cannot satisfy it. All
heavy invocations used the absolute build-slot wrapper with absolute temp and
Zig cache directories. No hardware timings or broad performance claims were
made. Zig and guest formatting checks passed.

The precommit focused Debug binary has SHA256
`c743ded197fac25bd23f042dfe725e5c34ee9d192a3105639a2d0ef95157dcbe`.
Its five changed source files match the committed checkpoint exactly; it is
kept distinct from the integrator's committed final pin.

[Receipt](evidence/eda-trig-interface-20260930/receipt.json) and
[raw archive](evidence/eda-trig-interface-20260930/raw.tar.gz) retain the
original reduced failure, absolute-cache controls, rejected guards-only
generic run, old approved `sqrt` reproduction, Guardian rejection, corrected
logs/commands, and final source snapshots. All 49 members were checked against
their recorded lengths and SHA256 hashes; payload total is 1,730,600 bytes.
Archive SHA256 is
`e7be66307710ccbdf901ed55e05c2131a65d727d13eef27487409e7eb11affa2`;
receipt SHA256 is
`37cd9dbb35c6761131e6559af180b3e3afc9cb6a35796cc4f6e3234f4fb44a67`.

The general private-intrinsic/interface-projection limitation is not repaired
by trusting cached text. Current constant evaluation rejects float-returning
source calls: direct float constants, integer conversions of trig calls,
and integer helper calls reaching trig or `sqrt` all reject with
`E_CONSTANT_TYPE`. These controls establish why evaluated-body retention is
not a remaining accepted-program route for the present wrappers. Future
standard templates or accepted evaluated bodies containing private
intrinsics need authenticated projection support. That limitation, the
misleading symbolic type diagnostic, and the hidden module fallback belong
in the EDA compiler-friction/GAPS handback, separately from the original
missing native `sin`/`cos` APIs.

The integrator's committed Debug pin is
`/home/epentland/ai/canopy/eda-bench-wt/mylang-e88fcf3c/bin/mylang`, SHA256
`6259edca26ea90f93b85037a17b5fc2692505a4e6f4cdd05cca23554b1bb0bcc`.
The source checkpoint remains `e88fcf3c`; the later `c7d66ee0` checkpoint
changes only audit/evidence files. The production source, build scripts,
declared test inputs, and toolchain pin compare equal between them.

The four standard broad targets completed with absolute temp/cache paths:

| Target | Result | Elapsed |
| --- | --- | --- |
| `test` | 115/115 steps; 2,806 observed Zig-runner passes, zero runner failures | 1,235.334 s |
| `test-qbe` | 51/51 steps; 505/505 tests | 119.287 s |
| `test-qbe-build` | 29/29 steps; its test runner was cached, with no fresh test count | 3.117 s |
| `fmt-check` | 2/2 steps | 0.267 s |

Each target's recorded process status is zero and its log hash matches the
integrator's receipt. Installation also reports 12/12 successful steps.
The `test` Build Summary prints 28,542 sparse registration skips alongside
2,806 passes; its 31,348 total is not a count of freshly executed tests.
The 22 observed Guardian test-runner results sum to 2,806 passes and zero
failures/skips. Default RC and stressed GC guest runs each independently
report 1,490 fresh passes across 228 programs, with zero cached, failed,
skipped, or dropped tests. The native-memory script executed successfully;
the native heap, COW, and arena executables were cached successes.

The previously failing module paths now pass broadly: the check oracle is
326/326 equal with all 326 using per-module checking and 606 own modules.
QBE compile comparison is 326/326 equal, 3,795 compared units, 638
interfaces, and 326 byte-identical executables. The separate release
comparison covers five fixtures and 185 units; it reports zero identical
executable files and must not be read as LLVM executable byte equivalence.
Build and test oracles are also 326/326 equal with zero reference failures;
the test oracle accounts for 1,505 tests and 97 entries without tests.

Guardian reports 88 successful checks during installation and the broad
targets that invoke it. These invocations are diff-scoped against approved
`2c05c41e`: nine of 719 source files for 50 per-file checks, while 38 checks
read the whole tree. They are distinct from the whole-tree source-commit
Guardian result above. The retained Guardian ROI summary covers the repair
session, including two rejected invocations: six known subjects are labeled
`useful-review`, while remaining advisory subjects stay pending. Central
feedback is committed at
`guardian-zig` `9faf6b82a07bf61615161bae27dd794363408c25`.

[Broad receipt](evidence/eda-trig-qualified-20260930/receipt.json) and
[broad raw archive](evidence/eda-trig-qualified-20260930/raw.tar.gz) retain
the exact four-target receipt/logs, installation log, launcher, Guardian ROI
summary, frozen source snapshots, and the read-only merge preview. All 32
members were verified against lengths and SHA256 hashes; payload total is
3,124,346 bytes. Archive SHA256 is
`0d6d81989cdb67f0324053f59a628ce514727b1ac1c567387a4701af0eb52f76`;
receipt SHA256 is
`733a06f2a6ba681d2aa8277c6e3108702220c5712a0a46f07e7afae3c5a475a5`.
The original rejected/focused archive above remains unchanged.

The four broad targets do not invoke the opt-in 100-seed fuzz target, Lox
project build/tests/driver under default and GC, or full release/stats guest
sweeps. The additive common-lane receipt below records those requirements
separately rather than inferring them from the four-target success. The existing default and
GC-stress sweeps were fresh despite lacking the explicit `--force` flag.

A read-only three-argument `git merge-tree` preview compares this source with
concurrent main `5041d690693587825015ca0a37e6a533ac605343`, using common base
`2c05c41e`. Only `SPEC.md` and `test/integration.zig` overlap; their additions
combine without conflict markers. The branches have diverged, so landing is
not a fast-forward. The preview changes no branch, index, or worktree and
does not qualify the combined source; the integrator owns that decision and
its required verification.

The remaining requested common-lane checks completed on the same frozen
source and committed Debug pin. All ten recorded process statuses are zero:

| Check | Result | Elapsed |
| --- | --- | --- |
| Explicit native-heap target | 10/10 steps; heap/COW/arena executables cached success, Guardian 88 diff-scoped | 292.884 s, including 290 s waiting for admission |
| Lox default project build / full suite / driver | Build success; 65 fresh tests across ten programs; 13 fresh driver cases | 54.483 / 61.192 / 30.287 s |
| Lox GC project build / full suite / driver | Build success; 65 fresh tests across ten programs; 13 fresh driver cases | 7.739 / 10.395 / 6.469 s |
| Full release guest sweep | 1,490 fresh passes across 228 programs | 729.305 s |
| Full stats guest sweep | 1,490 fresh passes across 228 programs | 244.252 s |
| 100-seed RC fuzz | 21/21 build steps; 98 ok, zero invalid, two GC-stress-only findings, zero RC divergences | 815.779 s |

All guest and Lox results have zero cached, failed, or skipped cases; the
full suites also report zero dropped tests. The Lox port is an owned copy
of the approved setup inputs: 37 files, 241,062 bytes, copied without caches.
Both driver runs use the actual `driver_cases.json` and 100,000,000-step
limit. Release and stats sweeps use `--force --jobs 4`; fuzz runs seeds
1–100 with two workers, both generators, the report-only GC-stress lane,
and its default every-eight-seeds LLVM-release comparisons. The Zig fuzz
target's explicit compiler override binds the same committed application
pin; its summary confirms that path. All 100 stats comparisons balance and
all RC comparisons match the ordinary GC baseline.

The two collector findings exactly match the earlier Phase B final receipt,
including generated-source hashes and reported symptoms: seed 19 differs
in stdout under GC stress; seed 87 exits 139 instead of zero and differs
in stdout. Their source hashes are respectively
`7b4625131d1cece836792c3ef374848bd33f9c8ed1a7a9bd4e7a1d0881214155`
and `c1658f510f5c94327f1cc98ec37a1766c7a507737d6b1e24742207e9cfbf9657`.
They remain open collector findings; no compiler source repair or waiver
was introduced in this addendum.

Every heavy invocation has a separate absolute build-slot admission,
absolute temp/cache paths, and recorded CPU affinity
`0,1,4,5,6,7,8,9,12,13,14,15,16,17,18,19`, excluding reserved CPUs
`2,3,10,11`. A brief supervisor-only pause allowed the integrator's waiting
EDA timing job to admit; the current release sweep kept running. Release
ran 13:30:32–13:42:41 UTC, stats 13:42:41–13:46:46, and fuzz
13:46:46–14:00:21. Shared package/memory load during that interval is
available to the EDA measurement report; this addendum makes no hardware
timing or corpus-performance claim.

This witness was selected before the user requested ReleaseFast for future
compiler builds. The frozen Debug compiler was retained throughout; guest
`--release` changes the guest backend rather than that compiler's mode.
The preference is recorded separately by documentation checkpoint
`ccff6992`; no replacement compiler or additional mode replay was needed.

[Common-lane receipt](evidence/eda-trig-common-lane-20260930/receipt.json)
and [common-lane raw archive](evidence/eda-trig-common-lane-20260930/raw.tar.gz)
retain all ten commands, admission identities, logs/statuses, source/pin
binding, copied Lox inputs, fuzz drivers and findings, and the comparison
with the prior collector receipt. All 61 members were verified against
lengths and SHA256 hashes; payload total is 617,229 bytes. Archive SHA256 is
`fe3beae023bfcfe78586ebee7c805724ee815aefb1c696e924ea47d635fc7d72`;
receipt SHA256 is
`70525af56f9781456f18031f08678004546313a98ce6cf973627bb6fcf4e6055`.
The earlier focused and broad archives are unchanged. Combining these
receipts closes the requested standard broad and common-lane compiler
checks, with cached native-heap coverage and known GC-only findings
explicitly disclosed. It does not establish a new full 27-step integration,
performance matrix, or acceptance of a merge with concurrent main.
