# A1: aggregate values and complete conversions

Status: runtime storage foundation implemented; frontend record syntax,
construction, field checking, preserving updates, complete conversions, fixed
arrays, checked indexing, and additional integer widths remain pending.

## Chosen storage semantics

The first records will be immutable values containing scalars and finite record
values. Nominal type identities are separate from runtime value tags: primitive
IDs are reserved, and aggregate values carry their declared type ID. Frontend
schemas and user-facing names must be added with declarations; the internal
runtime currently renders an aggregate ID as `type#N`.

A copied aggregate may share immutable backing storage. Each operand or
initialized local owns a reference. Loads retain, stores replace and release the
old local, calls transfer argument references into parameter slots, returns
release callee locals and transfer one result, and discard releases its operand.
A field read retains its result before releasing the containing value. This
produces value behavior without eagerly deep-copying unchanged nested values.

The runtime does not expose these host pointers to guest code. This is not a
reference/borrow model. References will require allocation identity, bounds,
and lifetime information before guest pointers or slices are accepted. Resources
and effects are also separate later work; host reference counting does not prove
those language contracts.

Zero-reference aggregate nodes are released with an intrusive work list, without
allocation or host recursion. Nested immutable sharing cannot introduce guest
cycles through construction. All runtime buffers release remaining values on
traps and host errors. Local slots currently retain a value until overwrite or
function exit; lexical cleanup obligations for resources must be introduced with
the resource model. Loop declarations reuse their assigned slots.

## Implemented evidence

`src/value_test.zig` exercises the new representation and internal VM instructions:

- A value survives local overwrite, argument passing, return, field projection,
  and discard, producing 42.
- Step-limit traps at every instruction boundary release all owned references.
- Allocation-failure sweeps cover aggregate construction and VM ownership paths.
- Repeated nested fields survive destruction of the outer record.
- A 20,000-level immutable chain is released without host recursion.
- Invalid internal field accesses and scalar operations release consumed values.
- 10,000 VM loop constructions/overwrites fit a 4 KiB live-allocation budget,
  including VM/validator storage, and leave zero outstanding bytes.

These tests intentionally use internal bytecode while the representation is
being established. No unsupported record syntax is accepted by the parser.

## Next frontend acceptance

1. Resolve record names to nominal identities and reject duplicate fields,
   unknown field types, and recursive by-value layouts.
2. Require complete construction with exactly one initializer per destination
   field; retain source evaluation order even if fields are written out of order.
3. Resolve field access using the actual record identity and enforce field types.
4. Preserve all unmentioned fields in an update of the same nominal record.
5. Declare complete conversions with explicit source-field accounting; adding a
   field must break the conversion until preserved, transformed, or discarded
   by name. Passing the whole record to a helper does not discharge accounting.
6. Extend exact discovery with nominal record/field identities; never serialize
   only field spelling or flatten unrelated domains into one scalar signature.
7. Add fixed arrays, bounds-checked indexing, and the additional integer-width
   semantics from plan A1, with checked conversion and overflow fixtures.

The full roadmap remains active. Storage validation alone does not complete A1.
