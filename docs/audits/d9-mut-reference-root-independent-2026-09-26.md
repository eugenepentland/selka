# Independent mutable-reference GC-root review, 2026-09-26

The parser stress failure comes from an omitted local use in liveness analysis.
`qbe_liveness.uses` counted `load_local` and `move_local`, but omitted
`ref_local`, the instruction that passes a fixed array or record by mutable
reference. A local used only by a later mutable call could therefore lose its
GC root across an earlier allocation.

In the failing migrated `parser_test::printed`, `heap.new_runtime` constructs
`rt`, then `output.capture` allocates before `parser.parse(mut rt, ...)`.
The emitted caller IL roots only the source byte string around `capture`;
it does not root `rt`. By the time `parse` roots the runtime and allocates
its token list, collection has already reclaimed runtime payloads. Independent
instrumentation by the implementation agent confirmed that freed Runtime list
headers had been reused for output buffers. The parser constructor's own root
records are initialized correctly; the null descriptor is a later consequence
of the earlier missing caller root.

## Controls

The frozen joined compiler is SHA
`d733b14aca8b25b0d4fb2d1becda50c98c2ab0f8cfac342e22a204bc58c9d82c`.
Debug QBE native GC-stress runs of `test_parse_logical` give:

| Source control | Result |
| --- | --- |
| Unchanged migrated source | Null-descriptor panic |
| Check the runtime stack length before `output.capture` | Same panic |
| Check it after `output.capture` | Pass |
| Construct the output before the runtime | Pass |

Each run executes one test with no cached result. These source variations are
diagnostic controls, not proposed workarounds.

A separate 16-line fixed-array program constructs `[1]list[int]`, performs an
unrelated list allocation, then passes the array only through a mutable call.
It passes with normal GC and returns the wrong result with native GC stress on
both the original 60b compiler
`48427e9ac1c01b74e60d1b4c098c8fc149a6b5fef3c07e110c7fb4ba16cbb545`
and the joined compiler in both modes. Adding an ordinary array read after the
intervening allocation makes all three compiler/mode combinations pass with
stress too. Thus the omission already affected fixed arrays before D9;
the mutable-record migration exposes it in the Lox source.

## Independent fix check

The implementation agent added `ref_local` to the existing liveness-use case.
This preserves the payload before the local's address reaches the operand
stack and also supplies the corrected lifetime to ownership and borrow analysis.
The generic fix, its spec update, structural root test and four guest tests
were reviewed without a remaining blocker.

A private frozen fixed Debug compiler, SHA
`be46540cb7a3bb9f32efd04a394b0044f31339c450ba146f3226f18c43cb80ac`,
passes all 16 independent runs: the unchanged migrated parser probe and
historical array probe, on QBE and LLVM, in compatibility and value modes,
with normal and native GC stress. All guests are Debug builds. The implementation
agent owns the complete port-test matrix and full gate; those are not claimed
by this report.

[Raw evidence](evidence/d9-mut-reference-root-independent.json.gz) retains the
negative and positive observations, exact commands, compiler and binary
identities, source variants, caller/parser IL and scripts. Scratch remains in
`d9-lox-frame-return/.tmp-frame-return/stress-review/`. Historical compilers and
shared baseline executables were read only; every guest output and cache used
private scratch.
