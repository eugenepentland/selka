# SSA, optimization, and agent reasoning audit

19 September 2026. Recommendation: keep ordinary source assignments and structured
loops. Investigate value-based, flow-sensitive analysis inside the compiler.
Requiring source-level SSA is not justified by the evidence collected here.

## Scope and evidence

This is a focused audit of assignments, aliasing, effects, lowering, and native
optimization, not a complete compiler correctness or security review. Inspected
the working tree at `4919ea9f` with existing uncommitted work. Executed probes
against the installed compiler and QBE; their hashes, source hashes, probe
sources, commands, diagnostics, emitted IL, SSA dump, and assembly comparison
are preserved in [the evidence file](ssa-language-audit-2026-09-19-probes.json).
The binary was not rebuilt, so these observations describe that recorded binary
alongside the inspected source, not a newly verified build of every working-tree
change.

Three small programs passed native execution under `--gc-stress`. Two expected
checker rejections were reproduced. Five emitted function units passed QBE.
No runtime benchmark, agent evaluation, full acceptance suite, or Guardian gate
was run. Compiler implementation and language semantics were not changed.

## Findings

### 1. Native compilation already constructs SSA

The relevant pipeline is:

```text
Python-like source
  -> checked typed expressions/statements and effect/origin summaries
  -> typed stack bytecode and conservative inlining
  -> QBE IL with local/operand slots
  -> slot promotion -> SSA -> load optimization/GVN/code motion
  -> native assembly
```

Evidence:

- `src/compiler.zig:173` and `src/project_compile.zig:248` lower and inline.
- `src/lower.zig:166` emits `store_local` for initialization and assignment.
- `src/native_ir.zig:9` represents stack types at instruction inputs and maximum
  stack capacity; it is not an SSA value graph.
- `src/qbe.zig:914` deliberately places scalar slot allocations in the entry
  block so QBE can promote them.
- `vendor/qbe/main.c:67` calls `promote`, then `ssa`, before its optimization
  passes. `vendor/qbe/mem.c:17` defines the promotable-slot restrictions.

The scalar probe compared these function bodies, both with an `int` parameter:

```text
value = x + 1                 incremented = x + 1
value = value * 2             doubled = incremented * 2
return value                  return doubled
```

Their assembly was **identical after substituting the function's own linker
symbol**, including its metadata symbol. Each assembly file had 87 lines. The
emission disabled debug/step/frame accounting through the existing emit options;
checked arithmetic remained. Native assertions verified both return 42 for 20.

A second function used an `if/else` and a `while` with reassigned `total` and `i`.
Its four source-local slots were promoted: there were no memory operations on
those local slots after SSA construction. QBE produced three phi nodes: the
branch merge and the two loop-carried values. This does not mean the function
had no other memory traffic; runtime frame/trap state still exists.

Thus, forcing different source names would not unlock SSA for these cases. QBE's
[IL reference](https://c9x.me/compile/doc/il.html#Phi) explicitly supports
non-SSA input. LLVM likewise documents promoting mutable local slots into SSA
with [mem2reg](https://llvm.org/docs/tutorial/MyFirstLanguageFrontend/LangImpl07.html).

### 2. Earlier value tracking could improve a real checker limitation

This program is rejected at `work[0] = 42` with `E_MUTATION_PERMISSION`:

```text
def f(a: list[int]) -> int effects(managed_allocation):
    work = a
    work = [2]
    work[0] = 42
    return work[0]
```

The assignment to `[2]` unconditionally replaces the alias. The write targets
fresh local storage, which the documented effect model permits. The caller's
list is untouched. A variant that binds the fresh list to a different local
passes checking and native assertions verifying both the return value and the
unchanged caller list.

The cause is visible in `src/origins.zig:454`: assignments merge a new origin
into the local's accumulated origin instead of distinguishing successive values.
Once `work` carries the origin of `a`, the fresh assignment cannot remove it.
This is a reproduced conservative rejection, not evidence of an unsound accepted
program.

**This is the strongest concrete argument for earlier SSA found in this audit.**
The analysis could distinguish `work_initial = a` from `work_fresh = [2]`, and
attribute the write to `work_fresh`. That can improve diagnostics and reduce
agent repair work without changing the user's variable names.

A flow-sensitive control-flow analysis can also fix this without introducing a
new general-purpose IR. Compare that smaller change against typed SSA before
committing to a compiler rewrite. Do not simply replace `Origin.merge` with an
overwrite: branches, loops, existing aliases, nested managed fields, and escaped
references require a correct transfer/merge model. At a join, union the possible
origins; at a loop, compute a conservative fixed point.

### 3. Single-assignment names do not make shared state stable

This probe uses each local name only once and still observes mutation:

```text
values = [1]
alias = values
before = values[0]
alias[0] = 9
return before * 10 + values[0]  # 19
```

Its native assertion passed under GC stress. Scalar SSA tells us which reference
a name denotes. It does not tell us whether the referenced list changed.

The language deliberately shares lists, dictionaries, and class objects;
records copy their value fields while sharing managed descendants
(`docs/statements.md:13`, `docs/managed-memory.md:17`). A read-only view would
also require care: preventing writes through one reference does not prevent
another alias from writing. Deep immutability and exclusivity are separate
semantic commitments with different costs.

Another successful probe declared `first(values)` with `effects()` and called it
before and after a declared mutator. The calls returned 1 and 9. An empty effect
set does not make a read of mutable input independent of memory state. Neither
SSA names nor `effects()` alone justify memoizing such a call or moving it across
a potentially aliasing write. They also do not prove termination or freedom from
traps. LLVM's [MemorySSA documentation](https://llvm.org/docs/MemorySSA.html)
describes a separate memory-dependence representation that works with alias
analysis; ordinary scalar SSA does not replace that work.

### 4. Optimization opportunities lie in preserved semantics and representation

Several important pieces already exist:

- `src/typed.zig:531` stores mutation footprints and return origins.
- `src/lower.zig:565` preserves those facts in bytecode.
- `src/origins.zig` follows managed descendants, calls, and return aliases.
- `src/qbe.zig:1590` copies scalar GC roots into root records, keeping the
  original scalar slots promotable. Aggregate roots still reference storage.

The inspected QBE emitter does not provide a general optimization pass using
per-parameter mutation/return-origin summaries to reason across guest calls.
This is a candidate use for a richer typed representation before operations
become pointer arithmetic and runtime calls. Candidate passes include range
propagation, redundant checked-read elimination, and value-record scalar
replacement. Each needs a demonstrated missed optimization and a correctness
argument; the existence of SSA alone is not a speedup.

Respect the existing semantics: checked integer overflow, bounds failures,
evaluation order, source-located traps, root lifetimes, arenas, and execution
budgets constrain movement and deletion. Removing apparently unused arithmetic
can remove an observable trap. Two writable parameters may alias; a mutation
footprint is not a blanket `noalias` promise. The current single-threaded heap
also does not become safe for automatic parallel execution just because scalar
dependencies are explicit.

Existing repository measurements strengthen this prioritization:

- [The hot-loop landing report](hot-loops-landed-2026-09-19.md) already records
  promotion-friendly roots, loop-aware inlining, and additional load elimination.
- [The later runtime report](runtime-to-2x-landed-2026-09-19.md) attributes gains
  to bulk output, text representation, and teardown. Its copy-cost experiment
  puts all aggregate copies at roughly 3% of instructions in those workloads.
  That is not a general bound on scalar replacement, whose secondary effects
  can remove other work, but it cautions against promising large gains from
  copy elimination alone.
- [The proposed LLVM experiment](llvm-backend-experiment-plan-2026-09-19.md)
  offers a separate way to measure backend quality with source and runtime held
  fixed. It is a proposal, not an already measured result.

Those are historical results from the repository, not measurements rerun here.

### 5. Agent comprehensibility should be evaluated separately

The language already offers useful foundations: definite assignment, stable
types, explicit capabilities, mutation contracts, checked results, and
machine-readable interfaces. The branch probe correctly rejected a possibly
unassigned name with `E_UNBOUND` and pointed to its first assignment.

Descriptive names for distinct stages can help an agent reason locally. Mandatory
version names and explicit phi nodes also introduce maintenance obligations:
every branch edit can affect merges, and every loop needs its carried state
represented. SSA means one static definition, not one execution; a definition
inside a loop can execute repeatedly. A source-level design must still supply
structured iteration, recursion, or another way to express that recurrence.

An immutable-by-default binding rule is a different, potentially smaller design
choice. It can prevent accidental reassignment without exposing SSA syntax, but
would change today's Python-like assignment rules and would not fix shared
object mutation. Treat it as an experiment, not a proven productivity improvement.

For agent tooling, prefer source-linked explanations of which assignment reaches
a read, which objects may alias, and what a call may mutate. Existing interface
and origin infrastructure provides a starting point; avoid making agents read
full compiler IR to answer ordinary source questions.

The repository's [diagnostic-feedback experiment](../../experiments/diagnostic-feedback/findings-2026-09-19.md)
reports benefits from concrete repair suggestions in some fault families.
Its [elegance-metrics experiment](../../experiments/elegance-metrics/findings-2026-09-19.md)
does not validate a structural dependency metric as a proxy for agent cost.
Neither experiment tests source SSA. Their relevant lesson is to measure actual
successful maintenance, not infer productivity from a cleaner-looking graph.

## Recommended next steps

1. **Address the reproduced origin precision problem.** Prototype flow-sensitive
   value origins, retaining structured source syntax. Compare a focused analysis
   change with an SSA representation that can support additional analyses.
2. **Inventory missed optimizations before broad IR work.** Select representative
   scalar loops, managed reads across calls, record operations, and the existing
   tokenizer. Inspect emitted and optimized code. Price the actual removable
   work under unchanged runtime and safety semantics.
3. **If justified, add a typed value/control-flow representation internally.**
   Use block arguments or phi nodes, explicit memory operations, source spans,
   and conservative call effects. Keep managed operations recognizable until
   after analyses. Start with a narrow validated subset; do not introduce a full
   MemorySSA system before an optimization needs it. Preserve resource cleanup,
   GC safepoints, and deterministic per-function cache identities.
4. **Run separate performance and agent experiments.** For performance, compare
   the same source/runtime and record correctness, time, instructions, RSS,
   compile time, and incremental rebuild cost. For agents, compare current
   syntax, a binding-immutability variant, and current syntax with better
   dataflow explanations on matched tasks. Include branches, loops, shared
   mutation, and multi-step maintenance. Use hidden semantic tests, repeated
   randomized runs, equal tool/budget conditions, and report correctness,
   repair rounds, time, and token use separately.

The decision supported now is **SSA inside the compiler where it earns its cost;
ordinary structured source code with clearer state guarantees and feedback**.
The current evidence does not support requiring source-level SSA to obtain
better native code or claiming it would make agents more effective.
