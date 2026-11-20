# Stage 4 scalar-loop readiness reuse

The bounded compiler change removes repeated scalar admission work while keeping
the original runtime query and slow append. Full append instructions fall 47.0%
on QBE and 53.7% on LLVM; sieve falls 35.4% and 49.1%. Allocation churn also improves.
Full unchanged N10 Lox and schematic controls are effectively neutral. Every
paired output and RC counter agrees. These gains do **not** meet the Stage 4
performance gate: append still costs 2.25×/2.30× accepted GC, sieve 3.28×/3.84×,
and N10 Lox 31.24×/51.07×.

## Reviewed boundary

Root and the compiler peer reviewed the concrete implementation before timing.
The [proof/design](d9-rc-scalar-readiness-plan-2026-09-27.md) records the queue,
metadata, CFG, physical ownership and frame-accounting obligations. The runtime
C implementation and public ABI remain unchanged.

After final physical COW refinement, a bounded scan admits only a fresh canonical
ordinary named list root with a scalar element. It rejects callbacks, extra
receiver scopes/uniqueness, managed stack values, semantic copies/captures,
field-transfer hooks, inline origins, actual scheduled cleanup and external
interior/backwards-escape edges. Function/loop bounds and a shared scan budget
retain the canonical fallback on refusal. The certificate is independent of the
physical loop-entry uniqueness proof and reuses its verified root authority.

A private 8-byte flag resets after hoisted uniqueness on every external CE entry.
Ordinary backedges enter below that reset. A room append captures its scalar,
checks the current capacity and generation, and only then consults the flag.
The first successful unchanged `myl_rc_list_plain_ready` answer can be reused
inside the closed span. A refused answer and every growth/overflow slow path
clear the flag before the original helper. No backing address, capacity,
generation, budget or region is cached. Zero-iteration loops perform no query.

A successful answer proves the actual registered flat scalar binding and empty
death queue. The admitted operations cannot change that answer. In particular,
same-root scalar `.write`, if its other hooks admit, reaches the zero-edge
`native_retain_replace` memmove/region branch with no allocation/drain. Before
success the flag is invalid. The explicit indexed-write fixtures still have
capture/COW hooks and therefore remain ordinary per-operation controls.

The flag uses normal frame sizing and allocation, never operand scratch. One
wide fixture moves its first local by 8 bytes and increases its heap reservation
787584→787600: the existing frame estimator retains its 2× spill reserve. Trap
journals, logical steps, frame admission and physical floor checks are unchanged.
The measured source retains the native query's older comment saying admission
is never cached. A separate comment-only follow-up clarifies this compiler proof
without invalidating the frozen measured compiler.

## Matched production evidence

Before source is `fbcd7978`, a clean real merge of `4fd7bd63` and the approved
readiness diagnostic/design. Debug compiler SHA256:
`39f0f752c8ffeb9957fc5024bc2c11582ecb48701ca87a7ee99b614fd066ba6e`.
After Debug compiler SHA256:
`4763ab94baf190fa99a4e08fc59fc7887110931d8041a0cc48116dbb09efad07`.
Full source delta, production file hashes, inputs, manifests, exact commands and
all raw observations are in the
[archive](../../experiments/d9-rc-scalar-readiness-reuse-20260927/README.md).

Each row is alternating median-three retired user instructions on CPU3, actual
QBE or LLVM O3/full LTO. All 84 raw production observations have 100% event running;
no scaling is used. Counts run separately. GC columns use archival medians from
completed rows of the immutable accepted-GC corpus experiment, not fresh
interleaved GC observations. Inputs and independent output verifiers are unchanged.

| Workload | Backend | Before | After | After/before | Before/GC | After/GC |
|---|---|---:|---:|---:|---:|---:|
| parity/suite/sieve | QBE | 4,180,751,390 | 2,700,751,365 | 0.645997 | 5.084234× | 3.284398× |
| parity/suite/sieve | LLVM | 1,671,745,466 | 851,745,387 | 0.509495 | 7.527070× | 3.835002× |
| parity/micro/alloc_churn | QBE | 7,972,232,134 | 7,217,232,221 | 0.905296 | 2.605173× | 2.358453× |
| parity/micro/alloc_churn | LLVM | 5,297,233,123 | 4,863,233,141 | 0.918070 | 2.715957× | 2.493440× |
| parity/micro/list_append_sum | QBE | 2,518,577,550 | 1,334,581,018 | 0.529895 | 4.252235× | 2.253237× |
| parity/micro/list_append_sum | LLVM | 1,222,706,822 | 566,708,819 | 0.463487 | 4.964808× | 2.301125× |
| schematic/fixture | QBE | 326,000,137 | 325,532,276 | 0.998565 | 17.530831× | 17.505671× |
| schematic/fixture | LLVM | 237,957,813 | 241,411,812 | 1.014515 | 26.267283× | 26.648557× |
| schematic/changed-net | QBE | 325,699,878 | 326,227,014 | 1.001618 | 17.506386× | 17.534719× |
| schematic/changed-net | LLVM | 241,509,175 | 237,778,136 | 0.984551 | 26.646039× | 26.234389× |
| schematic/changed-value | QBE | 325,592,775 | 326,042,247 | 1.001380 | 17.509743× | 17.533915× |
| schematic/changed-value | LLVM | 241,421,399 | 237,671,073 | 0.984466 | 26.652193× | 26.238168× |
| Lox VM binary_trees N10 | QBE | 226,314,480,098 | 226,311,882,105 | 0.999989 | 31.244976× | 31.244617× |
| Lox VM binary_trees N10 | LLVM | 175,143,346,854 | 175,344,769,609 | 1.001150 | 51.015245× | 51.073915× |

The Lox emission audit initially expected no admitted loop. It found exactly one
changed function, `object::new_closure`, among 405. Full N10 controls therefore
remain in the table, including all mixed samples. No Lox or schematic improvement
is claimed. Their small mixed movement is not grounds to discard the scalar gains.

Counts are identical in all 28 separate executions. Append retains one O and H
acquisition, one uniqueness check and ten allocations; sieve retains one O and H,
six uniqueness checks and two allocations. N10 retains 4,350,608 allocations and
retirements, 81,463,495 O acquisitions, 85,814,103 O releases and 276,752,828 H pairs.
The gain removes repeated validation, not required ownership traffic.

## Correctness controls and limits

The focused suite passes 14 tests (three named plus 11 common blocks), including
actual lowering entry routing, CE/reset/query/slow ordering, internal backedges,
heap-frame placement and refusal cases. Whole-tree Guardian passes all 88 checks;
no ratchet changed. Root serializes the separate full integration gate/feedback.

Both actual backends execute 48 paired RC guest assertions and 24 default-GC
stress assertions over the new six-case loop fixture and the existing six-case
scalar append fixture. Positive emitted bodies cover integer widths, floating
bits, boolean comprehensions, empty/repeated dynamic lifetimes, growth and a
fresh receiver allocated inside its caller's arena. Callback, snapshots,
managed elements and indexed capture writes retain ordinary lowering.

The production-library embedding harness executes 52 runs, 26 exact before/after
pairs. It wraps real production allocator hooks to queue a finalizer during
backing growth after earlier cached room appends. The finalizer sees length 8
before publication and registers metadata. Guest reentry during another active
finalizer preserves a queued sibling until the outer drain resumes. Generation
exhaustion, custom allocation refusal, initial/later byte ceilings, first/later
step refusal, physical floor and logical frame refusal have identical visible
output, trap code, consumed steps and counters. The heap-frame and zero-iteration
paths pass as well; every successful or failed run balances allocations/O/H.

Initial probe mistakes are preserved in the archive: trimming can make a limit
set to current bytes sufficient, and a small leaf legitimately lacks a floor
check. Corrected refusal controls exercise a genuinely insufficient growth
ceiling and the wide-frame floor. These were harness assumptions, not compiler
failures, and no production behavior was weakened to pass them.

`verify.py --live` recomputes all medians and paired checks and checks the frozen
compiler/binary/input identities. No full-corpus acceptance claim, default flip,
main merge, ABI change, threshold change or benchmark-input change is made.
