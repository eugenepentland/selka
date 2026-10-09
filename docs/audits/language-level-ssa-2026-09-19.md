# Audit: would single-assignment form at the language level help? — 2026-09-19

The question: should mylang adopt SSA (static single assignment) as a *surface*
property — every name bound once, loop-carried values made explicit — either to
make the native code optimize better or to make programs easier for AI agents to
reason about? Measured on this checkout (`perf/lever-search`, head `4919ea9f`),
with probes and captured IL under `experiments/ssa-audit/`.

## Decision

**No, on both counts.** The backend already derives SSA from Python-style
reassignment: QBE turns every scalar local and operand slot into a temporary and
inserts the phis a language-level form would have written by hand. The memory
traffic the three runtime audits actually measured comes from aggregates,
runtime helper calls and text representation, none of which single assignment
touches. On the reasoning side the checker already guarantees the properties
SSA is valued for (one type per binding, definite assignment on every path, no
hidden mutation of a local from outside its function), while the hazards agents
do hit — list/dict/class aliasing and record copy semantics — are untouched by
how many times a name is assigned. The corpus reassigns a quarter of its local
names, mostly inside loops, and the language already tried and removed an
immutable-by-default surface once.

## What "SSA at the language level" could mean

Three readings, in decreasing strength:

| reading | what the programmer writes | verdict |
| --- | --- | --- |
| **A. Real SSA** — explicit `phi`/block arguments, as in LLVM IR, MLIR, QBE IL | loop state as phi operands or `iter_args` | Not a programming surface anyone, human or model, writes at length. Training data contains it only as compiler output. Rejected without measurement. |
| **B. Single assignment, no phis** — every name bound once; loops become recursion or folds (Erlang/Elixir, Haskell) | `def loop(i, total): ... return loop(i + 1, total + v)` | Loop-carried state becomes calls. A mylang call costs a frame record, roots and ~150 instructions (`runtime-performance-2026-09-18.md`), and QBE has no tail-call elimination, so the hot loops get slower, not faster. 163 loop-carried names in the corpus would be rewritten. |
| **C. Immutable by default with `var`** (Rust `let`/`let mut`, Kotlin `val`/`var`, Zig `const`/`var`) | `total = 0` immutable; `var i = 0` to reassign | The only reading worth a debate. It is a readability convention, not an optimization: the checker already fixes a binding's type at its first assignment. mylang had exactly this (`docs/plan.md` §`let`/`let mut`, `W_UNNECESSARY_MUT`) and removed it in the 2026-09-14 Python-surface refactor to match Python. The census below says ~25 % of bindings would gain a keyword and the other 75 % would gain nothing the checker does not already enforce. |

The rest of this note measures reading A/B's optimization claim, since that is
the one that could have been true, and then addresses reasoning.

## 1. The backend already computes SSA from reassignment

The pipeline is: `sema.zig` (function-scoped locals, definite assignment) →
`lower.zig` (stack bytecode with `load_local`/`store_local` on numbered slots) →
`qbe.zig`, which declares one `alloc8` per local (`%l{n}`) and per operand-stack
height (`%s{n}`) in the entry block. QBE's `promote` (`vendor/qbe/mem.c`)
replaces any entry-block `alloc` whose every use is a load or store of the same
width with a temporary, and `ssa()` then inserts phis. Until 2026-09-19 the GC
root push stored each slot's *address* into the root record, which disqualified
the slot from promotion; `QBE-ROOTS-2` (value-carrying roots, landed that day)
removed that, so scalar slots are promotable again. That landing, not any
surface change, is what put the loop variables in registers.

Probe `experiments/ssa-audit/scalar_loop.my`:

```mylang
# doc: skip Historical pre-redesign syntax retained as audit evidence.
def sum_evens(items: list[int]) -> int:
    total = 0
    i = 0
    while i < len(items):
        v = items[i]
        if v % 2 == 0:
            total = total + v
        i = i + 1
    return total
```

`total`, `i` and `v` are all reassigned in the loop, exactly the pattern reading
A/B would forbid. After `promote` + `ssa` + copy elimination (`qbe -d C`,
`evidence/scalar_loop.sum_evens.after-ssa.txt`) the loop header is:

```
@i4
	%l2.37 =l phi @i0 0, @checked102 %v102.54     # i
	%l1.38 =l phi @i0 0, @checked102 %l1.51       # total
```

Every `%l{n}` and `%s{n}` `alloc8` prints as `nop`; the function carries 8 phis.
The final assembly (`evidence/scalar_loop.sum_evens.s`) has 15 stack references
in 174 lines, and none of them is a local variable:

| stack references | count | cause |
| --- | ---: | --- |
| frame record setup and restore (`{prev, meta, position}`) | 6 | frame protocol |
| position store before `myl_native_list_get` | 1 | trap location for a helper that can fail |
| `%agg25` out-slot around `myl_native_list_get` | 4 | `items[i]` is a runtime call that writes its result through a pointer |
| position stores on `@overflow`/`@cast_overflow`/`@failed` cold paths | 4 | `QBE-POSITION-2` |

The per-iteration memory traffic is therefore the `list_get` helper call and its
scratch slot. A language-level SSA form would produce the same two phis and leave
those five memory operations exactly where they are.

## 2. What stays in memory is not about assignment

Probe `experiments/ssa-audit/record_loop.my` reassigns a 16-byte `record`
local in a loop (`c = advance(c, i % 3 == 0)`). QBE keeps 16 `blit`s, 10 allocs
and 21 stack references, and builds only 2 phis (the scalar `i` and the loop
condition). The emitted IL shows why:

```
 blit %l1, %agg10, 16        # copy the record local into per-pc scratch
 storel %agg10, %s0          # push the scratch's *address* as the operand
```

The address of `%agg10` is stored, so `promote` cannot touch it, and the record
flows through memory on every iteration whether `c` is assigned once or ten
times. Fixing this is the aggregate scalar-replacement work already queued as
§3 of `runtime-to-2x-2026-09-19.md`; it is a lowering change, not a surface one.

The same holds for the other measured costs in the three runtime audits: runtime
helper calls for trivial operations, per-operation checks, `u32` text with a
264-byte fixed cost per string, `calloc` per allocation. Single assignment in the
source changes none of them.

What QBE still lacks — dead-store elimination, a loop-invariant hoist that can
see through a helper call — is also unaffected: those passes run on the SSA form
QBE already has, and the surface cannot supply them.

## 3. The corpus leans on reassignment

`experiments/ssa-audit/reassign_census.py` over `experiments/sexpr-port`,
`tests/lang`, `src/schematic/guest` and `src/stdlib` (62 files, 11,543 lines, 745
functions; regex census, ±a few percent):

| measure | value |
| --- | ---: |
| functions that reassign at least one local | 92 (12 %) |
| distinct local names | 896 |
| names assigned more than once | 221 (25 %) |
| of which assigned inside a loop | 163 |
| plain assignment statements | 1,342 |
| augmented assignments (`+=` and friends, `PY-AUGASSIGN-1`) | 180 |
| `x = x op …` self-updates | 60 |

Under reading B every one of the 163 loop-carried names is rewritten into a
recursive helper or a fold the language does not have. Under reading C, 221
bindings acquire a `var` keyword and 675 acquire nothing, since their type was
already fixed at first assignment.

## 4. Reasoning for agents

The properties people want from SSA when they say "easier to reason about" are
already rules of this language, spelled in the spec:

- one type per binding, fixed at first assignment (`PY-SCOPE-1`);
- a read is rejected unless every path assigned the name first
  (`PY-SCOPE-2`, `PY-SCOPE-3`), including the zero-iteration loop case that
  Python only catches at run time;
- no closures and no methods, so a local's value changes only at an assignment
  statement visible in the same function body;
- `W_UNUSED_BINDING` for a binding that is never read.

The rest of the guarantee, "the name means one thing", is what a reader gets from
a Python function today, and the audit-guide scorecard's syntax finding stands:
agents are trained on Python, JavaScript, Go, Java and Rust, all with mutable
locals, and see SSA only as compiler output. The 110-idiom velocity suite passed
105 idioms unchanged precisely because assignment behaves as in Python.

Where agents did lose repair rounds in the diagnostic-feedback experiment
(`experiments/diagnostic-feedback/findings-2026-09-19.md`) was `Result` returned
for `int`, unsupported generic requirements and module naming — never binding.
Where the scorecard found a silent hazard was a by-value record parameter write
(probe S03) and list/dict sharing: aliasing and copy semantics, which are
orthogonal to how many times a name is assigned.

Two SSA-adjacent ideas do have a plausible agent payoff and cost no surface
change; both are unmeasured and belong in a velocity probe before any commitment:

1. **Flow-sensitive narrowing**, which is per-definition typing inside the
   checker (SSA internally, Python outside). Today `Option[T]` is consumed only
   by `match` or `?`; a Python-trained agent writes `if x is None: return …` and
   then uses `x`. Typing the definition reaching each use would accept that.
2. **A reassigned-parameter lint**, since a parameter reassigned in its body is
   the one reassignment pattern that reliably confuses readers about which value
   a later line means. Cheap to add beside `W_UNUSED_BINDING`; check the corpus
   first for how often it occurs.

## Recommendation

1. Keep the Python binding model (`PY-SCOPE-1..3`). Do not add SSA, phis, or a
   `const`/`var` split to the surface.
2. If the motive is code quality, spend it on the queue in
   `runtime-to-2x-2026-09-19.md` §3–4: aggregate scalar replacement and inlining
   the scalar `list_get` path. Those are the only per-iteration memory operations
   the scalar probe still has, and the record probe's whole cost.
3. If the motive is agent reasoning, settle the `class` reference-type and
   aliasing decision from the scorecard first, then probe narrowing and the
   parameter lint.
