# RC contract result preservation, 2026-09-26

Postcondition inspection consumed the hidden `Result` local before the return.
Both `Ok(3)` and `Err("empty")` consequently reached the caller as `Ok(0)`.
The RC guest sweep exposed this in two existing `contracts.my` tests.

Contract-generated matches now carry an explicit borrowed inspection bit through
lowering and both bytecode inline remappings. Their scrutinee is loaded without
moving its owner; the selected payload is borrowed until the clause completes.
The subsequent return transfers the intact hidden result. Ordinary source
matches keep their existing ownership rules. Boundary invariant inspections use
the same contract-only path.

A focused lowering regression checks the borrowed switch and non-consuming local
load. All 11 existing contract guests passed uncached on each of QBE and LLVM.
The new guest exercises 40 managed-list successes, an error propagated through a
helper, and a unique `TextFile` returned through `@ensures(True)`, written and
closed by the caller. Its main passes on both backends with identical balanced
counts: 241 heap allocations/retirements, 361 acquisitions and 602 releases.
LLVM execution uses `--release` (O3/full LTO); the compiler is Debug.

Raw existing test records, exact compiler/source hashes and new guest counts are
in [results.json](../../experiments/d9-rc-contract-results-20260926/results.json).
The focused Zig filter passed 12/12 (one selected regression plus supporting
unnamed tests). This package requires the next combined integration full gate;
these focused results do not claim a full-gate verdict.

## GC compatibility follow-up

The first combined gate at `9192db49` found that GC's unconditional unique-local
cleanup still closed a borrowed contract payload before the caller could use it.
The GC emitter now excludes explicitly borrowed match locals from destruction and
skips discarded-payload destruction when inspecting a borrowed variant. This is
the same ownership distinction already enforced by RC guards.

All three new guests now pass uncached with `--gc-stress` on QBE and LLVM,
including the returned file resource. The focused GC IL regression passes 12/12.
The RC main still passes on both backends with the identical balanced traffic
above under ABI 2. Exact execution records and source hashes are retained in
[gc-compatibility.json](../../experiments/d9-rc-contract-results-20260926/gc-compatibility.json).
The failed combined gate is retained and will be rerun after integration.
