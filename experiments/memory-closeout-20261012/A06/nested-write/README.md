# Nested field writeback reproducer

Base source: `fbfcaa7a923186a8e773c3760f81c10aa345a432`. The baseline source-check
compiler is A10's command-support build, SHA256 recorded in `before.json`.

`positive.my` fails at `owner.left.scalar += 3`, despite preserving ownership of
both managed child records. `src/sema_places.zig` constructs nested typed `update`
nodes, each rebuilding one exact field projection. The outer store receives
`.update` access, but `single_owner.zig` visits every nested value with `.move` and
therefore diagnoses the generated child-field projection as an escaping move.

`single-owner-field-writeback.patch` contains the exact proposed checker changes
for A07 to apply in its reserved file. Its second hunk is a helper insertion snippet,
not an independently applicable unified patch. The child update must refer to the
same typed parent node and the same field index. Matching only ownership origin,
root local or field index would incorrectly grant writes to unrelated projections.

`src/core/a06_nested_write_test.zig` is reserved to A06 and requires coordinator
registration. It adds two tests: four source negatives (wrong field, wrong owner,
partial move and overlapping argument), and a counted native positive in
unoptimized and verified release modes. The positive checks independent snapshots,
owner replacement, early returns, zero RC events, zero managed exit-live bytes,
direct destructions and a clean emitted LLVM ABI.

The raw `before.json` results confirm all five sources typecheck before ownership
analysis. The positive is refused at its first nested field assignment. The overlap
negative currently fails earlier in its callee with the same field-write defect;
after the fix it must reach the overlapping-call diagnostic. No passing native
execution is claimed before the compiler fix is applied and the test is run.
