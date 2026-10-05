# S2-La: receiver overlap and caller rebinding

Base: `9ee2a484`. Branch: `codex/new-core-s2-language`.
Scope: Wave A's `MUT-OVERLAP-RECEIVER-1` and `MUT-REBIND-CALLER-1`.
Integration conformance, pins, row timing, and final Wave A grading belong to
S2-X's coordinator after both language packages are present.

The shared checker rejects a statement when an update's receiver and an
explicit evaluated `mut` argument share a prefix path. Constant-disjoint
siblings and other roots remain legal; readonly overlapping arguments retain
snapshots. Diagnostics locate the mut argument, relate the receiver, and say
to make the call in its own statement first. A certain one-line migration
carries structured edits consumed by `mylang fix`; conditional or effectful
surroundings receive the diagnostic without an uncertain edit.

The old backend selects caller storage for each mut collection parameter that
can rebind its whole variable, including loops, conditional paths and recursive
forwarding. Child replacement does not force its outer collection parameter
onto that ABI. Never-whole-rebound direct calls keep mutable payloads and
`RC-MUT-UNIQUE-1`. Callback adapters present a uniform caller-storage surface
while calling each canonical target through its original per-parameter ABI.
This preserves append-only producer ABIs, including separately compiled
imports. Interior mut arguments capture detached leaf storage with owners protected
across later evaluation and allocation. At call entry, unchanged leaf headers
use the actual slot; a replaced header uses the held selected value in an owning
fallback slot. Whole-local arguments read the current caller variable after
all arguments, in both RC and GC.

Storage masks survive bytecode archives, physical signature comparison,
module interfaces, semantic stand-ins, and native test facts. Format versions
advance when the representation changes. Producer authority is restored
before adaptation. Selective emitters reserve callback IDs before fixing
catalog tables and retain those IDs when cached bodies are expanded.
Synthetic adapter spans are zero, so independently synthesized consumers
publish the same archive identity. Their QBE metadata names the fixed
`@mut_callback:1:1` location and a versioned synthetic source digest, with no
real-source dependency. Whole-program and module emission therefore publish
the same metadata, while canonical functions retain their source positions.

The new core returns each mut parameter's final SSA value and stores it back
on every return. It no longer tracks detachment at collection rebinding or
refuses rebindings in conditional arms and loops. Fixed-array whole rebinding
remains a checker error. An interior mut path whose ancestor version changes
during argument evaluation receives a located `E_CORE_UNSUPPORTED`; the IR
cannot preserve an orphaned selected value yet. Whole-root rereads and stable
interior writeback remain supported. The exact base already returned the wrong
selected-list result; the admission guard reports that limitation precisely
without adding an IR shape.

## Focused evidence

| Check | Current result | Evidence |
| --- | --- | --- |
| Receiver diagnostic/acceptance tests | 43/43 combined final units | `focused-discovery-migrations-final.log` |
| ABI, adapter, archive, snapshot and metadata units | 43/43 combined final units | `focused-discovery-migrations-final.log` |
| Warm imported direct/callback producer ABI change | 4/4 CLI tests plus 12/12 RC, GC-stress and release runs before/after edit | `focused-warm-cli-third.log`, `warm-abi-modes-final.json` |
| Warm emission fragments and stable callback catalog | 13/13; actual reuse, manifests equal fresh emission; append/rebind/append edits | `focused-fragment-abi.log` |
| Mut collection guests, RC | 27/27 | `capture-rebind-final-rc.log` |
| Mut collection guests, GC stress | 27/27 | `capture-rebind-final-gc.log` |
| Mut collection guests, release | 27/27 | `capture-rebind-final-release.log` |
| Cold imported direct/callback module guests, RC | 2/2 | `modules-cold-rc-project-adapter.log` |
| Cold imported direct/callback module guests, GC stress | 2/2 | `modules-cold-gc-stress.log` |
| Migrated receiver native outcomes and balanced indirect scopes | 17/17 | `focused-native-migrations-final.log` |
| Structured migration, historical Lox and warm imported ABI CLI | 6/6 | `focused-discovery-cli.log` |
| Whole/module compiler and build parity, RC and GC | 4/4 for each of four oracles; 124 units compared per compiler oracle | `metadata-module-{compile,build}-{rc,gc}.{log,json}` |
| Value-semantics corpus, RC and GC stress | 145/145 each | `value-guests-final-{rc,gc}.log` |
| Guardian, whole tree | 88/88 | `guardian-reference-selection-final.log` |
| Original interior argument guests | 15/15 each RC, GC stress, release | `mut-places-final-{rc,gc,release}.log` |
| Selected-value fallback ownership | 785/785 allocations retired, 343/343 holds, no limits | `capture-rebind-counting.log` |
| Final ABI/adapter/metadata/fragment units | 29/29 | `focused-reference-units-final.log` |
| Core changed-interior refusal, stable interior and whole-current root | 3/3 focused; build 2.26s | `core-admission-focused.log`, `core-admission-build-time.txt` |

Doc coverage passes with zero failures (`doc-coverage-final.log`). Migrated
byte-buffer guests pass 5/5 under RC and GC stress (`buffer-guests-final-rc.log`
and `buffer-guests-final-gc.log`).

The final pre-freeze core checkpoint passes 150/150 in 90.79 seconds, preserving
all 121 baseline pinned contracts (`core-admission-full-final.log`). Its first
run passed 149/150: v_snapshot still described detached whole-mut rebinding.
The migrated output retains captured read 1 and now expects caller 7; exact old
RC, GC-stress and release output checks pass (`v-snapshot-final.log`).
The isolated pre-commit checkpoint again passes 150/150, all five build steps,
in 114.56 seconds (`gate-core-precommit-final.log`), below the five-minute
budget. Compiler and test compilation were cached. Expected missing-fixture
diagnostics in that log are passing error-path tests.

The frozen third full old gate passes 115/115 steps in 905.14 seconds, with
2,983 fresh Zig tests passed and 30,399 cached/skipped (`gate-test-final-third.log`).
Both RC and GC-stress language sweeps pass 1,608/1,608; both value-semantics
sweeps pass 145/145. Whole/module compile and build compare 340 byte-identical
executables. Source/tests and changed docs remained frozen
(`source-test-freeze-final-third.sha256`, `docs-freeze-final-third.sha256`).
The remaining old exit gates also pass: QBE 51/51 steps and 519/519 tests in
78.31 seconds (`gate-qbe-final.log`), QBE-build 29/29 cached steps in 0.25
seconds (`gate-qbe-build-final.log`), and formatting 2/2 steps in 0.21 seconds
(`gate-fmt-final.log`). Explicit documentation and coverage gates pass 26/26
steps in 0.95 seconds (`gate-docs-final.log`): 230 documented features across
57 pages, 14 standard modules and 178 exports, with zero coverage failures.

Focused new-core conformance runs 47 mut tests with leak checking and fact
verification. All 16 admitted tests match the old compiler in debug and
release; there are zero mismatches (`mut-conformance-final.log`). The 31
precise refusals cover dictionaries (19), callbacks (5), changed interior
ancestors (4), sets (2), and a fixed array (1). This package does not claim
Wave B support for those types or callbacks.

`validation-final.json` records the completed exit gates and confirms that
all 1,771 frozen source/test files and the changed specification/docs still
match their pre-gate hashes. Only evidence and this report changed afterward.

## Development timing and retained failures

The first isolated source rebuild took 3.29 seconds, excluding admission wait
(`isolated-source-rebuild-time.txt`). A later final install attempted during
Lb's full gate took 20.36 seconds, with the compiler itself reported at 19
seconds (`install-final-second.log`). That crossed the plan's warm rebuild
threshold and was reported immediately; dependent builds stopped pending a
quiet timing retry. The final isolated source rebuild passed in 3.56 seconds
(`isolated-source-rebuild-final-time.txt`). Final install passed 19/19 in
18.77 seconds: the compiler was cached, auxiliary executables each took four
seconds, and bundled runtime generation took sixteen seconds
(`install-final-third.log`). Bundled runtime archive generation is separately recorded
from compiler rebuilds. No test budget or timing threshold was waived.

The discovery full gate (`gate-test-final.log`) took 1016.96 seconds and
reported 11 stale Zig expectations plus required guest migrations and four
callback metadata identity mismatches. All were repaired before the frozen
rerun. The actual metadata diff is retained in `adapter-meta-mismatch.json`.
An isolated source rebuild after the metadata correction took 6.21 seconds
(compiler step four seconds, `isolated-metadata-source-time.txt`). A contended
new-core rebuild during the discovery old gate took 11.99 seconds and was
reported immediately (`core-build-final.log`); no compiler/core rebuilds run
during the frozen old gate. Its isolated retry is recorded with the final core
checkpoint.

The second frozen gate took 935.97 seconds and exposed an indirect interior
argument retargeting a later replacement plus a GC-only returned-string root
classification error (`gate-test-final-second.log`). Invocation-time identity
selection and owning fallback publication repaired the former. Raw-reference
rooting now requires whole operand provenance; borrowed managed returns are
values. Whole-local GC payload preparation also reloads current caller storage,
as RC and the new core already do. All focused guests and counted ownership
checks above pass after these repairs. The final isolated source rebuild took
5.35 seconds (`isolated-reference-source-final-time.txt`). After the final
core admission change, the old source rebuild took 5.50 seconds
(`isolated-last-source-time.txt`) and install took 16.95 seconds with compiler
cached (`install-last-final.log`). The earlier plain install took
15.09 seconds with compiler cached and bundled assets separately reported.

Slot monitoring found that directly nesting gate/build wrappers replaces fd9
and releases the outer gate lock. All package gates had remained serial by
explicit coordinator scheduling. A gate-only lease watcher protects the active
third gate (`gate-lease-final-third.log`), and later invocations keep a waiting
shell parent alive between the wrappers. The existing slot script is unchanged.

Earlier failing logs are retained to show diagnosis, not counted as final
passes. Retained logs remove trailing whitespace and extra EOF lines for
patch hygiene; diagnostic content and measured results are unchanged.
The first interior ABI guest failures exposed storage/ownership
lowering omissions, repaired before fresh RC and GC runs. The initial callback
RC-counting test actually succeeded with 40 allocations/40 retirements and
14 holds/14 releases, but the `native_execute` harness treated its stderr
`MYLANG_RC_COUNTS` line as a trap (`callback-adapter-diagnostic.log`). Ordinary
RC and GC-stress executions then passed; the harness limitation was reported
without broadening this package into an unrelated fix.

## Corpus audit and remaining limits

See `corpus-audit.md`. Examples and benchmark diagnostics contain no new
receiver overlap errors. Source scanning found no whole mut collection
rebind dependencies. Four exact prefix overlaps were found in the external
Lox resolver and heap. Work stopped and the findings were reported; the user approved
continuing with documented two-statement migrations. The external checkout
was left unchanged.

The exact base old compiler already aborts when a mut/retained managed-value
origin reaches parameter position 16. The list, readonly list-return, and
readonly string-return proofs are retained in `wide17-*-exact-base.log`.
Per plan §6 the pre-existing origin-width bug is reported, not changed in Wave
A. A wide scalar-only readonly signature remains supported and tested. The
new ABI's conservative high-position fallback does not widen frontend support.
Dictionary, set, and function-value support in the new core remains Wave B
work; this package changes its already-admitted mut writeback semantics only.
