# Rejected Lox scalar upvalue accessors, 2026-09-26

Neither accessor variant produced a worthwhile improvement. No accessor
source change is included in the optimized migration patch.

The first candidate added `heap.upvalue_slot` for read-only capture/close
conditions and `heap.upvalue_value` for open-stack/closed-heap reads in
`get_upvalue`. On closures, it cost 1.00763× QBE instructions and used
0.99540× LLVM instructions. Four other VM cases changed by less than 0.18%.
The one follow-up split retained only `upvalue_slot`: closures measured
0.99941× QBE and 1.00070× LLVM. That does not justify adding the helpers.

Both sides used the frozen Debug compiler `aa2fcbc6`, SHA `6e82c879…`, with
ReleaseFast guests and LLVM optimization level 3/full LTO. Measurements
used the mandated `pc.py`, CPU 3 and median-three samples, with exact output
checks. The shared source includes the indexed setter, late closure
publication, class-method accessor and global hash hoist. Before either
edit, every module and JSON fixture matched `617ce4dc`'s frozen hoist
source byte for byte. [Raw results](evidence/d9-lox-upvalue-rejection.json)
include both candidates, source hashes and individual samples.

Scratch source and scripts remain in `d9-lox-upvalue-reads/.tmp-upvalue/`:
`before/`, `port/` (combined candidate), `slot-only/`, `build.py`,
`measure.py`, `build-slot-only.py` and `measure-slot-only.py`.
The source composition preceding the experiment is merge `1b477932`.

Preliminary ordinary port tests passed; the candidates were rejected on
performance before acceptance validation. An environment-only
`MYLANG_OPTIONS=--gc-stress` invocation of `mylang test` is not counted as
native-test stress evidence: that command requires its explicit
`--gc-stress` option. The independently discovered parser/resolver failures
under that option are being investigated separately. Direct native binary
stress runs continue to use `MYLANG_OPTIONS`.
