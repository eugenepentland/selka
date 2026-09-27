# Non-H capture design controls

These are unchanged-compiler controls for the [read-only design](../../docs/audits/d9-rc-nonheld-capture-design-2026-09-27.md).
No role-proof implementation is included. `roles.my` exercises read/mut list
parameters, a legal copied user loop binding, a same-type helper return, a literal
source and a managed-result helper. All four GC-stress/RC × QBE/LLVM programs
pass; both RC runs have identical balanced totals (20 allocations/retirements,
O 9/29, H 15 pairs). Commands and immutable compiler/binary hashes are retained.
The managed-result helper is canonical on this compiler; the required alternate
entry refusal is an explicit proposed structural test, not claimed as exercised
by that function.

`loop-binding-rejected.my` contains the originally suggested direct loop-binding
mutation. `receipt.json.gz` preserves its E_VALUE_BINDING_WRITE checker refusal.
The valid program assigns the element to a separate local first. Its named
source is defined inside an enclosing backedge and would remain on the original
path under the proposed first certificate. `bytecode.txt.gz` and `emitted.json.gz`
retain the actual lowering, including H branches in canonical parameter and
named-source functions. The exact driver is `verify_roles.py`; it uses immutable
append compiler d048 and explicit actual LLVM release selection.
