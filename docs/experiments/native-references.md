# Native borrowing, slices, and returned references

The native C route supports scoped shared/exclusive references to ordinary values,
reborrows, reference and slice parameters, checked slice narrowing/access, and
returned-reference provenance contracts. Integers, booleans, domains, enums,
records, fixed arrays, and supported variants retain their ordinary value
representations. Native buffer/resource/pool/arena operations remain pending.

Each frame allocates stable local and reference storage. A native reference points
to its owner's local storage and records its parent loan, access mode, active state,
child count, and optional slice offset/length. Growing the frame vector does not
move those owners or references. Root loans lock the entire owner, including empty
or disjoint slices, matching the current VM policy. Exclusive parents suspend
while a child is active; shared parents remain readable through shared children.
Owner reads/writes and reference operations check the corresponding lock/access
state. Ending a loan requires its children to have ended.

Reference writes replace the owner's value. Slice writes create updated array
storage. Existing value copies remain snapshots through the aggregate backend's
reference counts. Reference arguments are reborrowed separately from ordinary
arguments, preserving source parameter positions when both kinds are interleaved.
Calls retain caller operands and use explicit frames without recursive host calls.

A reference-returning call records its declared caller parent and destination.
The callee captures only a view of that same owner. Its lexical and parameter loans
must end before return; a fresh caller-side child loan then receives the captured
slice range. This preserves narrowing through forwarding calls and resumes the
original exclusive parent after the returned view ends. Static lifetime, provenance,
and access checks still run before emission. References cannot be stored as
ordinary guest values, and the frontend rejects escaping local owners.

Each emitted instruction retains its VM step. Slice range, read, and write failures
use R_SLICE_BOUNDS with source locations and call frames; frame/step limits remain
shared with the VM. Frame exit verifies that its references are inactive. Terminal
trap/OOM cleanup frees reference/local storage and the aggregate allocation registry
without following dangling parent pointers. Native storage/allocation timing is
not claimed to match the VM's memory registry.

## Acceptance

The shared native driver now includes the references, reference-parameters, slices,
returned-references, and propagation examples; interleaved value/reference arguments;
recursive reborrows across frame growth; shared aliases; whole-record reference
returns; empty slices; invalid ranges and read/write bounds; and cross-module
returned views and trap traces. Small successful programs compare every instruction
budget through completion at -O0 and -O2 with UBSan.

The native memory driver additionally checks nested returned slices and writes,
allocation failures including frame growth during recursive reborrows, bounds
traps while a loan is active, and step/frame unwinding
with AddressSanitizer and UBSan. Compiler unit tests cover every allocation failure
through checking/VM/native emission and retain static rejection of conflicting
owner access, writes through shared references, and returning a local owner.

```sh
python3 scripts/native.py examples/returned-references.my -o .zig-cache/native-views
.zig-cache/native-views
# 20
```

This implements the ordinary-value borrowing experiment in the native route.
Borrowed buffer/resource I/O needs the remaining native capability and ownership
operations. The full native track and other unfinished roadmap tracks remain open.
