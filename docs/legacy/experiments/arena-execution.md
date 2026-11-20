# C: arena-backed VM execution
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

Status: execution-lifetime arena integration implemented. Embedders select
`vm.Options.memory_backing = .arena`; the CLI accepts `run --memory=arena`.
`general` remains the default and can also be selected explicitly. This is one
arena per execution, not nested source arena scopes or guest-controlled reset.

## Behavior

The VM owns the Arena at a stable address for the complete execution. Buffer
backing and memory cells used by source references come from that arena. Immutable
aggregate payloads, ownership wrappers, frames, locals, operand stacks, and memory
registries continue using the runtime parent allocator. This preserves snapshot
ownership and prevents a backing choice from changing source alias rules.

The same entry allocator capability, forwarding rules, logical buffer limits,
move checking, returned-reference contracts, and effect checking apply on both
backends. Selecting arena backing does not grant missing capabilities, bypass
`noalloc`, or change source semantics, bytecode, or duplicate fingerprints.

Local/operand owners are released before memory storage and arena backing. The
same cleanup runs on normal returns, guest traps, failed capability grants, and
host allocation errors. Runtime statistics are captured after cleanup. Filesystem
and network providers retain their existing explicit permissions and completion/
fallback-release behavior; their handles are not arena memory.

No backing reset occurs while guest code runs. Individual buffer destruction and
growth may leave unreclaimed backing until the execution ends. Logical live-slot
quotas therefore do not bound physical arena bytes, and a long-running allocation
loop may use more memory than the general backend. No speed or memory advantage
is claimed. The separate checked-reset backend will support later source scopes.

## CLI

```sh
zig build run -- run examples/buffer-views.my --memory=arena
# 19
```

The option is run-only and may appear once. Unknown/empty values and duplicate
options are usage errors. Execution budgets work with either backend. Checking,
dumping, and duplicate discovery do not select a runtime allocator.

## Acceptance evidence

`src/arena_execution_test.zig` compares general/arena execution of allocator
forwarding, growth, owned return values, returned slice reborrows, missing grants,
and capacity errors. Arena tests cover immutable snapshots, partial-construction
cleanup on propagation, every allocation failure through the emitted program,
and every instruction-budget boundary through the successful run.

1,000 separate executions each fit within 32 KiB live runtime allocation and
return to zero after each run. This demonstrates reclamation between executions,
not a bound for arbitrary programs or for allocation churn inside one execution.
`src/resource_slice_test.zig` also exercises fixed-array and owned-buffer resource
I/O with snapshot preservation, partial progress, and exact external cleanup.
Actual CLI tests exercise backend selection, matching output, traps, and usage
rejection in both host optimization modes.

[Pools/handles](source-pools.md), allocator-region identities, and
[lexical arena scopes with escape diagnostics](source-arenas.md) now integrate with
the VM. [Explicit source reset operations/results](arena-reset.md) are also implemented.


[Checked region backing](region-backing.md) extends execution arena selection to
pool registry storage. Owner wrappers and retained node snapshots stay on the parent
allocator. [Nested source arena scopes and conservative escape checks](source-arenas.md) are implemented.
