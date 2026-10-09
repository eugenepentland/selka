# Restricted evaluation foundation

Track F now has a bounded, effect-free evaluator exposed as `eval-project`:

```sh
zig build
zig-out/bin/selka eval-project examples/modules/main.selka
zig-out/bin/selka eval-project examples/modules/main.selka --max-steps=1000 --max-frames=32 --max-eval-bytes=1048576
```

Both commands produce 12. This is the evaluator foundation for compile-time work,
not yet a compile-time expression in the language, a schema generator, or an
incremental build cache. The command prints the entry's i64 result only after
successful evaluation, using the same checked integer/value semantics as the VM.

## Authority and inputs

The existing project loader reads the entry and its declared reachable import graph,
then checks every loaded body and lowers the checked program. Evaluation requires a
parameter-free main and an empty inferred transitive effect set. The checks include
untaken branches and recursive calls. Uncalled effectful helpers can remain in the
project; they are type checked but do not belong to main's effect summary.

No allocator, clock, random, filesystem, network, or environment authority is injected.
An unused capability parameter still rejects with E_EVAL_INPUT. Reachable effects
reject with E_EVAL_EFFECT before execution. Source loading is host I/O over declared
module paths; it retains the loader's existing limits and symlink behavior. This is
not an operating-system filesystem sandbox. External data input manifests and target
configuration are not yet supported.

Immutable aggregate construction, ordinary calls, loops, checked operations, and
other effect-free VM operations can participate. Host bookkeeping allocation is
separate from the guest allocation effect. All ordinary type, privacy, ownership,
result handling, and bytecode validation rules remain in force.

## Explicit budgets

Defaults are one million bytecode instructions, 256 active frames, and 16 MiB of VM
allocator storage. The CLI accepts positive --max-steps, --max-frames, and
--max-eval-bytes overrides. These options belong to evaluation; the VM's general/arena
selection and external provider configuration are not exposed by this command.

A fixed buffer bounds all allocation through the evaluation VM allocator, including
bytecode validation, frames, values, and bookkeeping. The allocator can reclaim its
last allocation; it does not promise general heap reuse. Allocation order and
fragmentation can therefore exhaust the quota even when guest values have been
released. The budget is not a measurement of peak live guest data or whole-compiler
memory: source loading, parsing, checking, lowering, and report rendering remain
outside it. Bytecode validation occurs within the quota before entry restrictions
and is also retained by the VM runner.

VM allocation exhaustion reports R_EVAL_MEMORY at the entry source start. Ordinary
step/frame exhaustion and guest traps keep their original source locations and
bounded call traces. Failure to obtain the backing buffer from the host remains
OutOfMemory/CLI host status 2; it is not mislabeled as a guest quota failure. Semantic
rejection and runtime traps exit 1 without partial result stdout; success exits 0.

Budget sizes are explicit inputs. Successful fixed-width guest results use the VM's
semantics, but host allocation layouts can affect quota exhaustion. Cross-target
layout evaluation, actual instruction-cost reporting, dependency manifests,
generation, schema derivation, cache identities, and invalidation remain pending.

## Acceptance

Unit tests compare an aggregate computation with ordinary VM execution at each of
39 instruction budgets, including populated trace entries; enforce frame and memory
limits; force recursive execution to exhaust the allocation quota; reject zero
budgets; reject authority and effects in untaken transitive calls; permit an uncalled
effectful helper; and sweep host allocation failures with cleanup. Actual CLI tests
cover imported function evaluation, values, nontermination, recursion, quota and
authority errors, and option rejection. Debug and ReleaseFast run the same tests.

[Evaluation dependency reports](evaluation-reports.md) now expose source snapshots,
implementation identity, and budgets with `--evaluation-report`. This establishes
request identity recording; caching and invalidation remain pending.

The [persistent evaluation driver](evaluation-cache.md) now reuses successful VM
results by request identity. Frontend reuse and finer invalidation remain pending.
