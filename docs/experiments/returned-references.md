# B: returned references with explicit input lifetimes

Status: returned whole-value references and slices are implemented. Together with
[scoped borrowing](borrowing.md) and [bounded slices](slices.md), this completes
the restricted-lifetime B experiment. [B acceptance](b-audit.md) maps the contract
to implementation and tests. Ownership/resources and general lifetime inference
are separate work.

## Contract and syntax

```text
fn tail(values: &mut []i64) -> &mut []i64 from values {
    borrow mut values[1..len_slice(values)] as rest {
        return rest;
    }
}

fn main() -> i64 {
    let mut values = new [3]i64 [2, 3, 5];
    borrow mut values[0..3] as all {
        borrow mut tail(all) as rest {
            write_slice(rest, 0, 9);
        }
        return read_slice(all, 1);
    }
}
```

A reference result names exactly one reference parameter using `from parameter`.
The supported result forms are `&T`, `&mut T`, `&[]T`, and `&mut []T`. The `from`
marker is contextual; existing functions such as domain factories named `from`
remain valid. The input may be any parameter position, including among mixed
value/reference arguments.

The result must be the named input or a reference derived from it through scoped
reborrowing or another reference-returning helper. A slice result may narrow a
slice input or a whole fixed-array reference. Types remain exact: a domain reference
cannot return its backing scalar reference, a slice cannot become a whole-value
reference, and an input with shared permission cannot supply an exclusive result.

Every `return` in such a function names an active reference with the declared
origin, element/value type, shape, and permission. A borrowed local, a copied input
value, or a different parameter fails `E_RETURN_LIFETIME`, even if two actual
shared arguments happen to alias at one call. Branches and matches may return
different narrowed views of the same declared input. The normal missing-return
and unreachable-code rules still apply.

A caller binds the result using `borrow helper(arguments) as result { ... }`.
Use `borrow mut` to request exclusive access from an exclusive result. Receiving
an exclusive result as shared is allowed. Result lifetimes are lexical. They
cannot be assigned into ordinary bindings, stored in aggregates, implicitly
converted into values, or used after the receiving scope ends. Calls returning
references are rejected in ordinary value expressions; use an explicit receiving
scope before forwarding or reading the result.

The caller's input remains suspended while an exclusive-derived result is active,
including when the result is shared. A result scope ending restores input access.
Shared inputs retain the existing shared fan-out rules. The call's value arguments
finish evaluating before temporary parameter loans are acquired.

## VM return protocol

Reference-returning calls identify a destination in the caller's reference table
and the original caller input's allocation identity. The callee receives ordinary
temporary parameter loans. Its result capture validates the active lease and
allocation provenance and records the selected slice offset/length, if any.

Lowering then ends all callee leases from child to parent. The reference-return
instruction releases callee locals and replaces the temporary call loans with a
new child lease of the original caller input, preserving the selected view and
requested permission. No guest code runs between ending the temporary loans and
creating the caller result. A step-budget trap during the explicit cleanup sequence
terminates the execution and releases all storage.

The returned reference therefore does not retain a dead callee frame, local slot,
or host pointer. Forwarding and recursive helpers apply the same protocol at each
return. Borrow registry slots are reused. Aggregate reads/writes preserve their
existing snapshot semantics and costs. This protocol currently uses one declared
input per result; it does not infer lifetime unions across multiple inputs or
permit arbitrary reference storage.

Bytecode validation checks return contracts, capture provenance, type/permission,
call result destinations, and operand-stack shape. The VM rejects missing captures,
inactive leases, conflicting borrows, and allocation identity mismatches. Invalid
internal bytecode is tested defensively; there is no untrusted bytecode loader.

## Acceptance evidence

The full suite passes 176/176 tests in Debug and ReleaseFast (153 core, 23 actual
CLI) on `0.17.0-dev.1683+5ceec001b`. Returned-reference tests cover:

- scalar mutation and restored parent access, shared results, and permission reduction;
- narrowed/empty slices, whole-array-to-slice results, recursive forwarding, and bounds;
- explicit parameter selection, mixed argument positions, branches, and exhaustive matches;
- rejected local/copy escape, wrong parameter provenance, inactive names, missing returns,
  shape/type mismatches, permission escalation, and ordinary-value misuse;
- aggregate snapshots and domain representation boundaries;
- allocation failures throughout compilation, execution, disassembly, and discovery;
- every instruction-budget boundary around capture, cleanup, and result creation;
- 10,000 returned-loan cycles within 16 KiB live runtime allocation, with zero bytes live
  after success or each tested trap;
- malformed capture/provenance metadata and actual CLI diagnostics/disassembly.

`examples/returned-references.my` returns 20. Exact duplicate discovery is `exact-v11`;
it retains the declared origin parameter, result permission/shape, capture identity,
and receiving scope while normalizing bound spelling. Formatting and whitespace
checks pass. Guardian gates were not exercised; hosted CI has not run.
