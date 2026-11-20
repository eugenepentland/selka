# Adjacent variant reads — 2026-09-27

This compiler slice removes a redundant whole-variant lifetime hold between a
checked list read and its immediately following ordinary match. The selected
payload still receives its normal owning snapshot before an arm can execute.
It addresses the measured generic Object-walk cost in Lox helpers, without
changing runtime uniqueness, semantic sharing, allocation or return conventions.
Stage 4 performance acceptance remains unmet; the exact isolated measurements
below do not include the independent native type-fact or dictionary-tail work.

## Source and physical proof

The control is joined `5b876012`, Debug compiler SHA-256
`f87393b249f45699d63a1f5a81dc47fb59faa41d1396fc8035131d7b2533b120`.
The candidate is real merge `680b857e` plus the archived source patch, Debug
compiler `300a83f5c51bfc5b590c0254940b4534df1e18d79a0b3ac248de047cc6c370d1`.
Both compilers and their runtime bundles are preserved; neither accepted GC
source nor benchmark input was changed.

`qbe_rc_variant_read.after` admits only an adjacent checked list READ and
ordinary SWITCH_VARIANT, with one plain index and no other operand. Its exact
private list local cannot be caller storage, a place, a scoped receiver,
iterator or uncounted borrow. The generated fast branch requires an initialized
ordinary owner or private LOAN16 journal and an empty operand journal. Otherwise
it executes the complete original loan path. It keeps the checked interior
address in the operand until dispatch; it never copies that address into
scratch subsequently cleared by operand cleanup.

Both PCs must be free of implicit COW/share/capture/publication effects, and
external entry to the switch refuses admission. The shared `boundaryQuiet`
query is also used by actual early-cleanup scheduling; this extraction changes
no cleanup behavior. The function limit is 4096 instructions, the preceding
scalar-index scan is at most 64 instructions per candidate, and authority
traversal is separately limited to 256 nodes. The resulting 262144 bound covers
only the dedicated index scans; representation, local and existing plan queries
are additional bounded work. No unenforced global work allowance is claimed.

All reachable variant payloads must be copyable and transitively free of unique
resources, finalized boxes, managed identity, live views, opaque handles and
callable authority. This includes the old arm binding, whose fixed payload type
is checked along with every arm. Ordinary dispatch retains the full incoming
payload before dropping that old binding, and preserves role/guard reset on
loop reuse. An immediately preceding READ also excludes the existing narrowing
shortcut, which requires a preceding LOAD.

The list journal keeps its logical children alive across the two PCs. Ordinary
payload retention uses the same destination region and physical identity;
PIN, O and SHARED behavior are unchanged. H does affect the allocator's resize
eligibility, so uniqueness ignoring H is not sufficient proof. The admitted
span cannot run a guest finalizer: payloads exclude callback authority, public
ownership helpers have already drained at an ordinary guest boundary, and
nested guest entry under an active drain cannot drain queued siblings. The old
arm binding cannot reenter either. Thus no source replacement can expose a
resize difference before the old intermediate H would have ended. Calls,
source rebinding and large growth are allowed only after ordinary arm
publication, when the selected snapshot is independently owned.

The prior design and detailed source/profile attribution are preserved in
`d9-rc-adjacent-variant-read-plan-2026-09-27.md`. The actual production emission
admits 37 sites, including `heap::string_obj` (one), `heap::set_object_field`
(one), `vm::load_frame` (two) and `vm::get_property` (one). It leaves ordinary
selected-payload retain, list writes and all 58 flat `vm::run` loan sites intact.

## Validation

- Focused units: 16/16, including five named new tests and 11 common unnamed
  blocks. They cover exact adjacency/entry/gap refusal, 64/65 scan limits,
  callback/escaped/live-view/callable-payload refusal, guarded fallback, original
  bounds failure and the distinct step check before selected retain.
- Eight permanent standalone assertions pass under both actual backends,
  before/after and GC stress/RC: 64 assertions. They cover source rebind/growth,
  later-arm callbacks, independent snapshots, duplicate children, heap/arena
  children, nested matches and reused pattern locals with empty/plain arms.
- The native step sweep contains 1440 executions: 704 step traps and 736 normal
  completions. Every before/after status and stdout matches within each backend
  and runtime. Eight additional bounds executions report `R_LIST_BOUNDS`.
- Four internal C ABI probes clamp the heap budget after constructing and
  journaling a deep payload's pool. The candidate's emitted fast read is verified,
  and its ordinary selected-payload retain refuses workspace allocation before
  acquiring children. The baseline refuses its earlier redundant Object loan.
  Both unwind all owners and report `R_MEMORY_BUDGET`. This is a workspace
  refusal control, not a new acquired-prefix or forged-finalizer test; the
  unchanged runtime's existing prefix rollback controls remain applicable.
- All counted executions balance O, H and allocation/retirement counts, with no
  saturation. Whole Guardian passes all 88 checks. Root owns the combined full
  suite gate; no full-gate result is claimed for this isolated patch.

The initial validation driver accidentally used unrecognized
`MYLANG_GC_STRESS=1`; those original ordinary-GC rows are explicitly retained.
The final 64-assertion receipt uses the supported `MYLANG_OPTIONS=--gc-stress`.
A first bounds assertion expected the wrong diagnostic spelling; its 1440
completed step receipts were preserved and the bounds matrix resumed with the
actual `R_LIST_BOUNDS` contract. No expected language output was weakened.

## Exact unchanged workload measurements

| Input | Backend | Before instructions | After instructions | After / before | After / accepted GC |
| --- | --- | ---: | ---: | ---: | ---: |
| N4 | QBE | 1,140,202,793 | 966,412,305 | 0.847579 | diagnostic input |
| N4 | LLVM | 898,143,719 | 748,852,380 | 0.833778 | diagnostic input |
| N5 | QBE | 2,125,757,462 | 1,790,137,757 | 0.842118 | diagnostic input |
| N5 | LLVM | 1,673,148,708 | 1,372,122,731 | 0.820084 | diagnostic input |
| N10 | QBE | 254,030,801,904 | 211,062,133,817 | 0.830853 | 29.139221 |
| N10 | LLVM | 197,851,866,495 | 161,381,484,252 | 0.815668 | 47.006639 |

The exact GC denominators are 7,243,231,888 QBE and 3,433,163,639 LLVM,
from three CPU2 measurements of the same frozen accepted GC binaries in
`experiments/d9-rc-flat-borrow-joined-20260927/results.json.gz`. The extracted
raw samples, original archive hash, binary paths and archive-time binary hashes
are in `accepted-gc-reference.json`. These are a different sample set from the
root corpus's 7,243,227,886 / 3,433,157,037 receipts; they do not replace those
receipts or change accepted GC source/binaries.

Both backends use their actual production code generator; LLVM is explicitly
O3 with full LTO. Instructions are interleaved median-three measurements on
CPU10 with raw `cpu_core/instructions/u` events and 100% running fractions.
Every reduced and full run matches its exact expected stdout. Counted binaries
are measured separately from production instructions.

| Counter, both backends | Before | After |
| --- | ---: | ---: |
| Heap allocations / retirements | 4,350,608 | 4,350,608 |
| Owner acquisitions | 81,463,495 | 81,463,495 |
| Owner releases | 85,814,103 | 85,814,103 |
| Hold pairs | 276,752,828 | 264,505,085 |
| Clone shells | 1,095,889 | 1,095,889 |
| Uniqueness checks | 20,836,904 | 20,836,904 |

Removing 12,247,743 H pairs leaves owners, allocations, clones and uniqueness
unchanged. These counts support attribution to physical loan removal, and also
show the remaining cost: 264.5 million H pairs and 1.1 million clone shells.
The immutable accepted GC instruction controls are unchanged. The resulting
full-workload ratios remain far above the 1.3 outlier cap; no corpus geometric
mean or acceptance conclusion follows from this one workload.

The timing wrapper records outer `time(perf)` RSS only, which includes the
wrapper process. It is not reported as direct guest RSS. Root explicitly
requested deferring a separate RSS matrix to the combined full-corpus
candidate, since this slice leaves allocation counts/layout unchanged.

Immutable commands, actual backend manifests, compiler/binary/source hashes,
raw events, outputs, counts and exact selected IL are archived in
`experiments/d9-rc-adjacent-variant-read-20260927/`. Its `verify.py` checks the
archive without rebuilding or rerunning workloads. The next compiler and
runtime proposals remain separate from this frozen evidence.
