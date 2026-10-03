# Checked VM constant reads

The common `OP_CONSTANT` handler now reads its operand with the existing
`read_byte(mut frame)`, then calls a readonly `constant_at(frame, index)`.
The helper returns the same checked `frame.constants[index]`. It avoids carrying
an inout frame into the combined operand/pool-read helper and lets LLVM inline
the reads. The original `read_constant` and every other source caller remain.

Apply `constant-readonly.patch` to the complete joined source 84 snapshot named
in `static-review.json`, after the earlier source overlays. It changes only
`vm.my`, a driver regression, and that regression's Clock provider fixture.
The new regression executes all constant operands 0 through 255 under Lox GC
stress and checks the output after consecutive print opcodes. It exercises the
last legal pool operand and the IP progression into each following instruction.

The code-byte read still occurs before the checked IP increment, the constant
pool read occurs afterward, and the stack write still follows the pool read.
The stack's normal COW/bounds/overflow work remains. The closure in `rt.frames`
still roots this activation's constants; neither helper allocates or calls the
collector. The readonly argument evaluation contains no callback or mutation.
Published IP before Lox error handlers and child calls is unchanged. Expanding
this source handler changes helper attribution for internal malformed-bytecode
native traps; this is a source refactor, and the public Lox error protocol and
valid compiled bytecode are the qualification scope.

Fresh LLVM/QBE qualification passed 85 tests in each RC and native GC stress arm:
340 passes, zero cached/failed/skipped/dropped. The existing runtime snapshot,
callee/root ordering, closure/upvalue and exact Lox error tests remain. Commands,
process statuses, compiler/QBE/source identities and logs are retained in
`qualification.json` and the four qualification logs. The fixed compiler is
`d14a7040…`; no compiler source changed and no broader compiler suite is claimed.

Static disassembly gives the following whole `vm::run` counts. These include
cold paths and duplicated inlining, and do not establish dynamic cost or speed.

| Backend | Control instructions / calls | Selected instructions / calls |
| --- | ---: | ---: |
| LLVM O3 full LTO | 5586 /486 | 5449 /454 |
| QBE | 8606 /440 | 8628 /442 |

The control LLVM opcode dispatch already has a 37-entry jump table and a range
check. Rust also dispatches through tables; mylang currently fetches eight-byte
integer code elements, while Rust fetches bytes. QBE emits a comparison chain.
Literal source match cases are rejected by the current parser, so no new syntax
or replacement opcode scheme was introduced.

LLVM's control run contains 29 static `myl_qbe_rc_unique_field` calls; QBE 22.
The ordinary path already inlines the payload/null, shared-mark and owner-count
checks and skips those helper calls. The exact linked runtime archive's
`qbe_runtime_rc.c.o` is LLVM bitcode (`42 43 c0 de`), not an opaque native object.
A mutable Runtime parameter still permits earlier value snapshots and other
handlers can publish or replace fields. Whole-run uniqueness hoisting remains
refused. Static sites do not show how often detachment executes.

Two direct pool-read variants and a scalar-local-reuse variant remain frozen
in private scratch. LLVM code shrinks, but QBE code grows from 8606 instructions
to 12684/12732. They are rejected for that structural growth. Its exact planning
cause has not been proved. The readonly helper emits 129 IL lines with only
three checked failure calls and two empty-return memsets; it emits no RC glue
calls. The selected LLVM run has zero calls to `read_constant`, compared with 10
in the control, due to final LTO decisions across the reachable call graph.

`build.py LABEL` and `test.py LABEL` reproduce builds and qualifications using
`scripts/build-slot.sh`, immutable compiler inputs and private caches/TMPDIR.
Complete source/binary hashes and rejected variant receipts are in
`static-review.json`; complete private assembly files have recorded hashes.
No timing, counter or perf workload ran in this lane. Central measurement is
required before accepting a runtime performance improvement.
