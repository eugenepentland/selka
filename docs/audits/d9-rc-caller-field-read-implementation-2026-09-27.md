# Checked scalar-list reads from incoming record storage

The bounded incoming-lifetime certificate removes temporary list loans from two
Lox bodies, `vm::read_byte` and `vm::make_closure`. The unchanged full N10 median
instruction counts fall 5.33% QBE and 5.24% LLVM against the completed named-home
slice. This remains far outside Stage 4 performance acceptance: 20.24× and 32.78×
the archival accepted-GC counts. There is no default or runtime ABI change.

| Actual backend | Before | After | After/before | Before/GC | After/GC |
| --- | ---: | ---: | ---: | ---: | ---: |
| QBE | 154,847,125,432 | 146,597,270,007 | 0.946723 | 21.3782× | 20.2392× |
| LLVM O3/full LTO | 118,761,080,254 | 112,536,573,744 | 0.947588 | 34.5924× | 32.7793× |

Every number is the median of three raw, unscaled retired-instruction events on
CPU3. All twelve production events report 100% running and exact expected
output. Before/after execution order alternates. Separate full-size counted runs
reduce H acquisitions/releases from 160,905,294 to 146,041,398 on both backends.
All other counters remain identical: 44,407,747 owner acquisitions, 48,758,355
owner releases, 4,350,608 heap allocations/retirements, 1,095,889 clones and
20,836,904 uniqueness checks. GC references are completed rows of the original
corpus experiment, not newly interleaved GC samples: 7,243,227,886 QBE and
3,433,157,037 LLVM, using the unchanged input and accepted compiler.

## Authority and exact scope

The new query requires the concrete canonical guest parameter's
`caller_storage` contract and physical `inout(parameter=root)` entry, identical
storage resolution and no private alias/place substitution. It does not assign
an ordinary owner role or grant uniqueness. The suspended caller may protect a
leaf through an ordinary owner, a loan/hold, a receiver scope or an open arena.
That lifetime is sufficient only until the checked scalar result is copied out.

The existing at-most-64-PC interval remains unchanged: private single-writer
capture, all explicit entry/exit edges checked, no callback/mutation/independent
cleanup/arena transition, empty operand/capture induction and a final buffered
actual-emission veto. Named-home ownership analysis is still required for named
roots; only an independently verified incoming root skips that analysis. All
journal/layout slots and original fallback remain. Whole-record safe-type
admission still refuses unique, callable, capability, opaque and live-view
content. Only ordinary scalar-element lists are admitted. No aggregate-result
or broad Runtime admission was added.

Only two full-project IL bodies change: `read_byte` has 2→0 native loans and
`make_closure` 3→1. Every other body is byte-identical. In particular `run` retains
48 loans, `read_short` four and `read_constant` two. The thirteen Runtime read
pairs with plain 16/24-byte aggregate results remain refused. Later ordinary
field updates retain their own existing lowering; interval-local elimination
must not be confused with whole-function loan elimination.

Public guest boundaries have drained prior pending destruction. A finalizer's
reentrant guest inherits an active outer drain. The closed interval adds no
independent dead work, and the caller anchor prevents its temporary list holds
from retiring the list. Thus removing the redundant loan/unloan drain boundaries
does not move a valid guest-visible finalizer. Unrelated prequeued idle C entry
is not granted a new contract. As with earlier borrowing certificates, removal
of unnecessary temporary H-limit admissions is intentional; mandatory value,
bounds, arithmetic, frame, step and remaining count-limit semantics stay intact.

## Bounded-proof correction and immutable evidence

Base `fa9e4cd5` follows named-home implementation `c1224f30`. The before compiler
is the immutable named-home `install-proof-final`; the measured after compiler
is the separate caller-field-read `install-prototype`. Complete identities,
source hashes, manifests and original source patch are archived.

A final review found that `containsLiveView` could scan a wide scalar record
before the safe-type traversal refused its pending-node bound. The corrected
incoming query removes that redundant prepass: `rc_field_authority.safe` already
visits every native child and refuses every builtin marker, including live
views. A focused transitive live-view test verifies this without the old query.
Named-home behavior is unchanged. Only an extreme no-view DAG formerly refused
by the redundant query's distinct revisit exhaustion can become eligible; the
semantic type and interval grammar do not broaden.

The shared incoming budget precharges 65,536 logical queued type/child visits
per uncached root, with at most 256 distinct types and 256 pending entries.
Seen-membership searches have an additional fixed factor of at most 256; the
logical allowance is not a total primitive-comparison promise. Completed
answers alone enter a 16-slot root memo, within the existing shared 262,144
allowance. The separate scalar-stack and CFG/emission budgets remain unchanged.
Allocator failures in safe-type native layout queries now propagate
OutOfMemory; a failed allocation followed by successful retry is tested.

The corrected compiler is a distinct immutable `install-proof-final`. Its four
full N10 executables and six guest/library controls are byte-identical to the
measured originals. Thirty-six after-control runs and both complete accounted
and unaccounted emissions repeat exactly. No measured binary or receipt was
replaced, and no new hardware timing is inferred from changed code.

## Controls and retained negative evidence

- 48 actual guest assertions: eight controls, before RC / after RC / after
  GC stress on both backends. Direct/forwarded and aliased inout homes,
  rebinding, negative indices, later replacement, callback fallback and nested
  caller arenas pass.
- 64 native embedding executions: 30 exact before/after pairs plus four
  explicitly different temporary-H-limit runs. The paired set covers O0/H1
  direct and forwarded callers, heap and arena storage, a real finalizer A
  queuing sibling B and reentering the guest, reentrant metadata registration
  success/refusal, bounds/arithmetic/step/logical-frame/physical-stack failures,
  custom allocator refusal after the read, and successful heap-frame cleanup.
- Readonly and callback bodies remain byte-identical in accounted/unaccounted
  emission. A real 788,288-byte heap frame retains its original allocation and
  cleanup; the RC heap budget does not govern that preexisting raw frame calloc.
- Focused RC filter passes 119/119, and final proof controls pass 20/20. Debug
  installs run Guardian88 with no ratchet growth. Parent owns full integration
  gates and centralized Guardian feedback.

Two initially proposed positive source forms were correctly rejected by the
existing checker: directly passing an inline record list element as `mut`, and
declaring an unwritten `mut` parameter. Their receipts are retained. The legal
replacement uses explicit local-copy/call/store-back and actual scalar writes.
Two harness assumptions were also corrected and preserved: the read itself
performs no custom allocator call, and an RC heap limit does not refuse a raw
heap frame. Allocation refusal is instead tested at the unchanged later list
replacement. These were fixture assumptions, not changed language behavior.

Run the standalone archive verifier with:

```sh
python3 experiments/d9-rc-caller-field-read-implementation-20260927/verify.py --live
```
