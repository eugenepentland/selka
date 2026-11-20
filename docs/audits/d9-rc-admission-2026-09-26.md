# Unique arguments at frame admission

A direct guest call previously cleared its consumed unique argument's guard
before the callee checked its frame limit. The callee's RC journal did not yet
exist, so refusal leaked the resource and any counted children. The original
recursive `Owned { File, list[int] }` probe retired zero of two allocations and
aborted at RC slab teardown. Indirect calls had the opposite missing step: their
caller guards remained armed after the callee consumed the same values.

Cold refusal paths now drop the unique obligations and counted children directly
from incoming ABI storage. Packed parameters use their existing vector; ordinary
scalar arguments need one reusable eight-byte scratch word. There is no journal
proportional to the parameter count and no change to the guest ABI. Heap frames
use a nontrapping try allocation, release consumed arguments, then raise the same
`OutOfMemory` trap. Successful entry transfers obligations into the normal
journal. Entry accounting checks run after those guards are initialized.
Indirect calls disarm unique argument guards before invoking the canonical entry.
Host and C-ABI declarations reject unique input shapes during checking.

Validation used Debug compiler
`321a7b0cfe1e9b96d228037b4113703f55184689e1c16c305756f82004f2a034`:

- Fourteen focused tests passed: three admission tests and eleven unnamed root
  blocks. They cover cold unique/count cleanup, packed wide values, indirect
  transfer and an oversized try allocation refusing without touching context.
- Fourteen existing fast-frame protocol tests passed (three named plus eleven
  unnamed). Guardian passed all 88 checks.
- QBE passed direct and indirect depth refusal, indirect success, a packed
  130-parameter signature and ReleaseFast stack-floor refusal.
- LLVM O3/full LTO passed direct depth refusal, indirect success, packed depth
  refusal and ReleaseFast stack-floor refusal. A mutually recursive indirect
  control also passed. All successful/trapped runs retired every allocation.
- Injecting `calloc` refusal for the exact heap-frame allocation produced
  `OutOfMemory`, with two allocations and two retirements on both QBE and LLVM.
  QBE used 600 empty-list locals (212,736 frame bytes); LLVM used 120 (43,776).
  The injected failure occurred before any of those local lists were created.

The self-referential indirect LLVM probe exposed a separate duplicate-function
prototype error; it is retained in the evidence and assigned to the parent
translator slice. This report does not claim that failure is fixed here. The
integration branch owns the full gate and overall RC acceptance.

[Raw evidence](evidence/d9-rc-admission.json.gz) contains sources, commands,
compiler hashes, counters, the old failure and the retained translator failure.
[Small probe sources](../../experiments/d9-rc-admission-20260926/direct.my) are
committed separately. Build them with `--rc-runtime=stats --mode Debug`, then run
with `MYLANG_OPTIONS=--max-frames=16`; the success probe instead exits zero without
a ceiling. Fast floor probes use `--mode ReleaseFast` without a logical ceiling.
The fault-injection shim is diagnostic only and names its exact frame allocation.
