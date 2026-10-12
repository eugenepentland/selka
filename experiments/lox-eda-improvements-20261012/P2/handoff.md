# P2 — borrow the tree interpreter's resolved program

Implementation complete in `6174c448f78af97809be3485897ff8333a8a7a36` (base seed
`094d2555bf68c04f563db4cc1b11d87d522b28e7`). Its normal commit hook
passed all 88 Guardian checks through shared build admission.

The interpreter's mutable control record now holds only depth and the returned
scalar Value. Each execution helper borrows the resolved Program separately from
mutable Runtime, Output and control. Expression/statement pattern matches, call
arguments, block statements and function bodies use the original immutable
storage. Function declaration construction selects name/slot scalars. No AST
view is stored in a runtime object; tree functions still carry declaration IDs.
Parser/resolver mutation finishes before these borrows begin.

Printing borrows Runtime independently of mutable Output. Runtime and output
also stay in their caller-provided storage at the interpret boundary, removing
startup/exit snapshots. Function/block error paths restore environments before
propagating errors and function depth decreases on both success and error.

Interpreter reads use P3's initial helper APIs for environment ancestors/slots,
class methods, instance class/fields, text and scalar tree/native metadata.
Call dispatch first extracts a scalar discriminator, then ends the object-table
borrow before allocating or calling guest code. The inherited-method table owner
and current instance mutation snapshots remain intentional independent owners.
The original instance is re-read after RHS execution so its intervening writes
are preserved. P3's temporary heap dependency was installed by the coordinator
and is excluded from this owner's commit.

Six focused tests cover repeated recursive function bodies, short circuiting,
return out of nested blocks/loops, nested runtime error unwind, stack overflow,
closures and printable kinds, inheritance/super and receiver RHS mutation.
Normal/stress runs are paired where meaningful; recursion overflow is bounded.
The fixture uses the existing native-clock provider because the test runner
cannot provide a Clock capability.

`first-build-source.json` pins the compiler and source bytes. Baseline counted
binary/receipt/source identity is in `baseline-identity.json`. Allocation probes
are separately labelled equality loops of 20/100/300 iterations plus repeated
fib(8), each normal and GC-stress, with a 20-second per-run bound. They are not
full performance cells and establish no runtime/RSS comparison. The candidate
includes P2 plus its initial P3 heap-query dependency; changes cannot all be
attributed to AST traversal alone. No full benchmark or cutoff adjustment is
performed by this owner.

Read-only peer review: P1 found program/AST heap handles protected by parser
permanent roots, restoration and call rooting preserved, and no new defect.
P2 reviewed P3 heap/query/string/output changes: selected scalar/owned-text
contracts and existing snapshots are preserved; string probes retain weak-key
and tombstone semantics; concatenation creates the independent bytes owner
before runtime allocation; output never mutates Runtime. No static defect found.

Checked release and counted builds passed with the pinned compiler; source bytes
remained unchanged after admission/build/tests. All six verified release tests
passed, with failed/skipped/unsupported all zero. LLVM inspection found no direct
copy calls in evaluate, execute, run_block, run_body, call_expr or interpret and
no RC calls in inspected interpreter functions. Class declaration retains the
two intentional independent table copies. Direct cleanup remains present.

Paired instrumented allocation probes passed all eight normal/stress outputs.
Managed exit-live, retain/release/share metrics and compiler RC event counts are
zero in every run. Every measured evaluate/execute/run_block/run_body/interpret
function allocation bucket is now zero. Equality evaluation's observed
20-to-300 iteration slope fell from 832 to zero bytes/iteration; whole-application
traffic slope over those same two inputs fell from 1869.94 to 155.89
bytes/iteration, including remaining real startup/runtime storage.

| Labelled tiny workload | Baseline traffic bytes | Candidate traffic bytes | Reduction |
| --- | ---: | ---: | ---: |
| equality, 20 iterations | 2,802,744 | 1,662,088 | 40.70% |
| equality, 100 iterations | 2,954,552 | 1,676,744 | 43.25% |
| equality, 300 iterations | 3,326,328 | 1,705,736 | 48.72% |
| equality, 300 iterations, stress | 3,321,920 | 1,754,528 | 47.18% |
| two fib(8) calls | 3,284,144 | 1,699,432 | 48.25% |
| two fib(8) calls, stress | 3,287,736 | 1,741,224 | 47.04% |

Managed peak for normal equality300 was 890,936 -> 838,072 bytes; stress
was 842,120 -> 838,136. Those are separate from cumulative traffic. Process RSS
and runtime were not measured here. All raw counter profiles/outputs and exact
commands are retained in this directory; `allocation-comparison.json` contains
all eight pairs and direct function attribution. `build-outputs.json` pins
executable/LLVM/provider hashes and `candidate-llvm.json` pins the IR inspection.

The coordinator's scripts were reviewed read-only. Reported fixes included
asserting the 246 VM/241 tree normal/stress summaries (974 runs per arm), pinning
provider JSON, tying reused verified-release qualification to the current build,
and explicitly executing case-driven P1/P2/historical runtime regressions in
all five modes. P2's `_tests` file deliberately needs its native-clock fixture
and must be run with the recorded `--cases P2/cases.json` command (six tests).

No compiler changes, ownership annotations, escaping borrows, RC fallback,
historical source/evidence edits, feedback-log additions or pushes were made.
No further optimization followed these passing local checks. Coordinator owns
complete conformance, the five-mode/cache gate, integrated Guardian and
exclusive full-input timing under the unchanged 3x Zig cutoff.

