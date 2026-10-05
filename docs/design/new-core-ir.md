# The new compiler core: Core IR, facts and LLVM emission (S0 design)

**Status:** checkpoint A of stage S0 (`docs/audits/new-core-plan-2026-10-05.md` §6),
2026-10-05. Branch `claude/new-core-s0-20261005`. Decisions N1–N5, L1–L4 and D1–D4 are
fixed inputs. Sections marked *design only* describe S1+ work that S0 must leave room for
but does not build; *checkpoint B* marks S0 work not yet done. Measurements are in §11.

**Built at checkpoint A** (about 2.9k lines of Zig plus 260 of C, 0.6k of them tests):
`mylang-core build` compiles the integer_math slice and a control-flow program from
`typed.Program` through the Core IR and LLVM; release builds run the fact pass, which
already brings the slice to the spike's level-1 speed (1.67 cycles/element, §11).

## 1. Shape of the core

```
FILE.my ─► front end (module "mylang": lexer, parser, sema)      reused, unchanged
              │  typed.Program  (src/typed.zig)                    decision N3
              ▼
          src/core/build.zig      typed tree → Core IR (SSA, on-the-fly construction)
          (B) src/core/verify.zig IR well-formedness checks, and the facts' verify mode
          src/core/facts.zig      intervals, list facts, trip counts → marks checks proven
          (S1) src/core/own.zig   ownership: uniqueness, borrows, one-count RC insertion
          src/core/emit_llvm.zig  Core IR → LLVM IR text (typed accesses, attributes)
          src/core/driver.zig     zig cc: .ll + runtime C → executable (-O0 / -O3)
              ▼
          native executable, linked with src/core/runtime/core_rt.c only
```

`mylang-core` is its own executable (N2): `src/core/main.zig` imports the front end as the
`mylang` Zig module (`src/compiler.zig`) and touches nothing below `typed.Program`. The only
front-end change is one export (`pub const typed`). `zig build core` installs it;
the default `zig build` and the `mylang` binary are unchanged (the step is not attached to
the install graph).

## 2. The input: what `typed.Program` already carries (N3 evidence)

`mylang-core dump-typed FILE.my` prints the checked tree. For the slice and for a probe
using `sum`, `zip`, `enumerate` and `for x in xs`, the tree contains **no** `for`,
comprehension or prelude node: the checker has already desugared them into the same small
statement vocabulary (`block`, `initialize`, `assign`, `branch`, `loop{condition, body,
step}`, `loop_exit`, `match`, `ret`, `discard`) and ordinary expressions:

| Source form | Checked form (built by) |
|---|---|
| `for j in range(n)` | `block{ init j=0; init limit=n; loop{ j<limit, body, step: j=j+1 } }` (`sema_loops.zig`) |
| `[f(j) for j in range(n)]` | `block_value{ init j, limit, out=acquire_buffer(capacity expr); loop{…, discard append(out, f(j))} ; value: out }` (`sema_collections.zig`) |
| `sum(xs)`, `zip`, `enumerate`, `for x in xs` | index loops over `length`/`read` buffer operations, with `iteration_check` for for-each (`prelude_builtins.zig`, `sema_loops.zig`) |
| `xs[j]` | `block_value{ init alias=xs; read(alias, block_value{ init k=j; if k<0: k=k+len(alias); k }) }` |
| `len(xs)` | `cast i64 (buffer_operation length)` (the length is `u64`) |
| `int(text)` | `buffer_operation parse_int` → `Option[int]` |
| `match opt: case Some(v)` | `match{ value, arms[tag, payload slot, body] }` |
| `out.print(a, b)` | `print{ stream, arguments }` |

**Finding.** `prelude_builtins.zig` runs *inside the checker*; it produces typed nodes, not
bytecode, so its desugaring is already in `typed.Program`. `lower.zig` is the typed →
bytecode step, and what it adds is not desugaring but:

1. value-semantics copy placement (`VALUE-SEMANTICS-2`, `value_semantics.Facts`);
2. evaluation-order snapshots of lent operands (`VALUE-SEMANTICS-14`);
3. hidden locals for boxed match payloads and dictionary receivers;
4. dropping `debug` nodes in release builds;
5. flattening to labels and jumps, after which `bytecode_inline.zig` inlines small calls.

So the new core **bypasses `lower.zig` entirely**. Items 1–3 are exactly the ownership
questions the new core must answer itself in S1 (§6), and it answers them on SSA values
rather than on stack slots; item 4 is a flag; item 5 is replaced by SSA construction and
LLVM's inliner. Nothing needed for S0's kernels is missing from the typed tree. Two things
it does not carry that S0 recomputes cheaply: loop trip counts (the `loop` statement has the
condition and step, which is enough) and "this list came from a comprehension of length n"
(derived by the fact pass from the `acquire_buffer`/`append` pattern, §5).

## 3. Core IR

A typed SSA form, one `Function` per checked function, in `src/core/ir.zig`.

**Values.** Every instruction defines at most one value; a value is named by its instruction
index (`Ref`). Function parameters and constants are instructions. Join values are `phi`
instructions at the head of a block, with one operand per predecessor in predecessor order
(the builder records predecessors, so the emitter prints LLVM `phi` directly).

**Types** (`ir.Type`, interned per module):

| Core type | Source | LLVM |
|---|---|---|
| `bool` | `bool` | `i1` |
| `i8 … i64`, `u8 … u64` | fixed-width ints | `iN`; signedness lives in the IR type and selects `nsw`/`nuw`, `sdiv`/`udiv`, `icmp slt`/`ult` |
| `f64` | `float` (a `domain` over `u64` in the checker) | `double` |
| `vec(T, N)` | — (produced by the vector lowering) | `<N x T>` |
| `list(T)` | `list[T]` | `ptr` to an RC block (§8); element accesses are typed `getelementptr T` |
| `str` | `str` | `ptr` to an RC block of UTF-8 bytes |
| `option(T)`, `union(cases)`, `result(T, E)` | `Option`, unions, `Result` | an SSA pair `{tag, payload}` (`{i1, T}` for `Option`) while in registers; stored in place in memory (§7) |
| `record(fields)` | `record` | an LLVM struct value in SSA, flattened to fields by SROA; stored in place |
| `cap` | `Stream`, `Host`, other capabilities | `i64` token (stream: the fd); dropped at `extern` calls |

**Lists, strings and records are values.** No instruction mutates a value another `Ref`
names. `list.push(l, v) → l'` and `record.set(r, i, v) → r'` return new values; whether
they reuse `l`'s storage in place is the ownership pass's decision (S1), and in S0 the only
`push` is on a list the builder created (`acquire_buffer`), whose old value is dead after
the push. This is what makes the immutability facts free: a load of `len(l)` or of an element
through one `Ref` is invariant for that value's whole lifetime, so the emitter marks it
`!invariant.load` and gives the data pointer `noalias` where it escapes into a helper.

**Operations** (S0 subset first, then what S1 adds):

- constants: `iconst`, `fconst`, `bconst`, `undef`;
- integer arithmetic `add sub mul neg`, `div rem` (truncating), `floor_div floor_rem`
  (Python), bit operations and shifts, `cmp` with a predicate; float arithmetic and
  comparisons; conversions `int_to_float`, `float_to_int` (checked), `widen`, `narrow`
  (checked or proven);
- each checkable instruction carries a `check` field: `exact` (trap at this instruction),
  `region` (release builds may move it inside its L2 region, §7) or `proven` (the fact pass
  showed it cannot fail; nothing is emitted). S0 implements `none`, `exact` and `proven`;
  `region` arrives with the L2 lowering. `proven` also licenses `nsw`/`nuw` and, for
  `floor_*` over non-negative operands, `udiv`/`urem`;
- lists: `list.new(capacity)`, `list.len`, `list.get(l, i)` (bounds-checked), `list.push`;
  strings: `str.parse_int` (→ `option(i64)`), `str.len`;
- unions: `union.make(tag, payload)`, `union.tag`, `union.payload(tag)`;
- calls: `call f(args)` (internal, mylang calling convention), `call_extern f(args)` (C ABI,
  capability arguments dropped);
- output: `print(stream, args, sep, end)`, expanded by the emitter into runtime calls;
- terminators: `jump`, `branch(cond, then, else)`, `ret`, `unreachable`.

S1 adds `retain`/`release` (one count), `unique?` tests, `borrow`/`end_borrow` markers,
`record.*`, `list.set`/`pop`, and the error-trace operations for `Result` `?`.

**Control flow.** Basic blocks with explicit terminators. The builder keeps the typed
tree's structure as metadata: for each `loop` statement it records a `Loop{header, body,
latch, exit, id}`, so loop facts never re-discover loops from back edges (the spike's main
fragility, README "What the bytecode did not carry").

**Source positions.** Every instruction stores the start offset of its span in the merged
source (`u32`). Traps and call sites resolve it lazily to `file:line:column` through
`frontend.position` (merged-source origins → file → line index). Checkable binary
operations use the checker's `op_span` (the operator), so a trap names the same column the
old core names.

**SSA construction.** `src/core/build.zig` walks the checked tree with the on-the-fly
algorithm of Braun et al. (2013): `write(local, block, value)`, `read(local, block)`, phis
created on demand, blocks sealed when their predecessors are known (a loop header after
its latch), and trivial phis removed through a forwarding table. Checked locals map 1:1 to
SSA variables; the checker's hidden locals (`<collection>`, `<range-limit>`) become plain
SSA values, so `values[j]`'s alias copy disappears at construction. `loop_exit` (break and
continue) jumps to the recorded exit or latch block of `target`. A node the builder does
not yet support stops the build with `error.Unsupported` and a reason naming the node kind
and its position (the start of the coverage sweep's refusal list, plan §6).

## 4. The S0 vertical slice

`experiments/new-core-s0-20261005/int_math.my` (kind 0 of the compute benchmark, from the
WP-8 spike) needs: `list[str]` arguments, `len`, `int(text)` with `match` on
`Option[int]`, a comprehension over `range`, nested counted loops, `//` and `%`, a `C`
`extern` call through a `Host` capability, `out.print` of two integers and `main`'s
exit status. `mylang-core build FILE.my -o OUT [--release] [--link C]` runs the whole
pipeline. Results are in §11.

## 5. Facts

Facts are side tables keyed by `Ref`, computed by `src/core/facts.zig` after construction
and before emission, in release builds only (debug builds keep every check and compile
faster):

- **Intervals** per integer value: constants, arithmetic (exact `i128` evaluation, the
  spike's `llvm_direct_dag.zig` rules ported), `floor_rem` by a positive constant `c` →
  `[0, c-1]`, `floor_div` by positive constants, conversions, and phis by a widening fixed
  point (a loop-carried counter `i = phi(0, i+1)` guarded by `i < n` gets `[0, hi(n)-1]` in
  the body). A comparison that dominates a block refines its operands there (the loop
  condition is the case that matters in S0).
- **List facts** per `list` value: `length == Ref` (the trip count of the loop that filled
  it) and `elements ∈ Interval` (the hull of every pushed value). Because list values are
  immutable SSA values, these hold for every later read of the same `Ref`, including in a
  different loop nest. This is the element-range fact the ladder study found decisive
  (`runtime-language-levers` §3.1).
- **Trip counts** per recorded `Loop`: counter, start, bound, step. The accumulator rule
  (entry range + trips × summand range) bounds reductions such as `pass_total`.
- **Check marking.** Each `exact` check whose operands' intervals rule out failure becomes
  `proven`: overflow, division by zero, `i64` floor fix-ups (non-negative operands), and
  list bounds (`0 ≤ i < len` where `len`'s list fact equals the loop bound).
- **One assumption,** stated once in `facts.zig`: a list holds at most `2^47` elements
  (elements of at least one byte in the 47-bit user address space of L4's single
  platform), so once a list of length `n` exists, `n ≤ 2^47`. It bounds trip counts and
  hence reductions. Unlike the spike, no counter ceiling is assumed: a counted loop's
  counter is bounded by its own loop bound (`[start, max(start, bound)]`), which is a fact.
- **Fixed point or nothing.** The pass iterates in reverse postorder with monotone
  reachability (as in SCCP) and widens a phi to its type range after eight changes; if
  the ranges do not settle within 64 rounds, nothing is proven.
- **Where it runs and what it changes.** `facts.analyze` runs per function after
  construction, in release builds only. It mutates the IR in two ways: `exact` → `proven`,
  and a comparison it decides becomes a boolean constant (so the dead branch folds in
  LLVM). The interval table stays beside the function for the emitter (`!range`).
- **Runtime guards over immutable data** (*design, S0 checkpoint B*): when a list's element
  range is unknown (file data) but the list is an immutable value, the emitter can version a
  loop: one pass computes `min`/`max` (hoisted out of every loop the value is invariant in),
  and the fast version runs when the hull fits the narrow lanes. The ladder study recovered
  the whole gain this way in 3 of 4 cases.

A `verify` mode (ported from the spike's `llvm_direct_verify.zig`, *checkpoint B*) emits an
assertion for every fact the emitter used (`len`, element hulls, intervals) and traps on a
violation; the differential fuzz runs with it on.

## 6. Ownership and one-count RC (*design only, S1*)

The plan's D1–D4 (one saturating 32-bit count, live-place iteration, non-storable dictionary
views, MUT-EXCLUSIVE-4) are built in from the first S1 commit. The IR already has the shape
they need:

- **Value states.** Each managed `Ref` is `owned` (this function holds +1), `borrowed`
  (valid for a scope; no count traffic) or `consumed` (moved into a call, store or return).
  Parameters are `borrowed` unless the callee's signature transfers them; results are
  `owned`; `list.push`/`record.set` consume their operand and produce an owned value.
- **Uniqueness.** `push(l, v)` runs in place when `l` is the last use of an owned value whose
  count is 1. Statically fresh values (built in the same function, never stored or
  passed out) skip the runtime test; otherwise the emitter tests the count and copies on
  write. This replaces `lower.zig`'s copy placement (VALUE-SEMANTICS-2/14) with a liveness
  question on SSA values: a "copy" is simply two live `Ref`s sharing a block.
- **Borrows.** A read-only use inside a region where the owner stays live (`len`, element
  reads, passing to a non-mutating parameter) is a borrow: no retain/release.
- **Live-place iteration (D1) is not a snapshot.** When a `for` loop's source is a place
  rooted at a local or parameter, every step reads the *current* value of that place: in
  SSA, the builder re-reads the root variable's current version at each step (the header
  phi of that variable), never a value captured at loop entry. Writes the body or a `mut`
  callee makes to the iterated list stay visible, as in Python; a change to its structure
  (length) is trapped by the existing `iteration_check`. Only when the body rebinds the
  root local does the loop iterate the value it had at entry. Borrowing the list at entry
  (one value, no count traffic, invariant length and data) is an *optimization*, valid only
  when the builder or the facts prove the body and its callees never write that place: no
  assignment to it or to a path under it and no `mut` passing of it. That is the common
  case (every S0 kernel), so it costs nothing there. The checked tree already reads the
  root local at every step (`buffer_operation read owner=…` inside the loop body, after
  `iteration_check`), so the builder's SSA reads follow D1 by construction; the facts'
  list facts attach to SSA values and so only ever describe the version actually read.
- **RC insertion** runs after facts: a `retain` where a borrowed value becomes owned
  (stored, returned), a `release` after the last use of an owned value, and none for
  values the uniqueness analysis proves dead-on-arrival. Release of a count-1 block frees
  it and releases its children; the count saturates at `2^32-1` (D4) and a saturated block
  is never freed.
- **Traps and teardown.** A trap is fatal (RC-TRAP-TEARDOWN-1): no releases run on the trap
  path, so trap blocks need no cleanup edges.
- **`with arena()` (N6)** is decided in S1; the IR leaves a region marker (`region.enter`/
  `region.exit`) as the attachment point either way.

## 7. Traps and LLVM emission

**Trap model.** Trap kinds and reports follow the old core so it stays the oracle: stdout
and exit status must match; the trap's stderr report has the same first line and
`MYLANG-TRAP` line (`R_OVERFLOW`, `R_DIVISION_BY_ZERO`, `R_LIST_BOUNDS`, …, detail fields
as the old core prints them), and exit status 1.

- **Debug builds** (`-O0`): every `exact` check is emitted in place, in program order;
  the trap block calls `myl_core_trap(site, a, b)` (`noreturn`, `cold`, branch weight
  1:2^20) with the site index into a constant table `{kind, line, column, width, operation,
  function}`. Measured: the trap's first stderr line and `MYLANG-TRAP` record are the old
  core's, byte for byte, for overflow and list bounds; the trace has only the innermost
  frame (`in grow at …`), where the old core also names the callers. Full traces (*S1*):
  a call-site table keyed by return address (PC-table traces), walked through frame
  pointers on a trap, gives every `in f at file:line:col` line with no per-call runtime
  bookkeeping.
- **Release builds** (L2, *checkpoint B*): checks become `region` by default. A region is the code between two
  visible effects (stream writes, capability/`extern` calls, exit). The emitter may (a) hoist
  a bounds check to one `high ≤ len` test before a counted loop, (b) merge overflow flags into
  one sticky `or` tested at the region exit, and (c) drop checks the facts prove. S0 emits
  them exactly (a correct L2 implementation of "exact"); (a)–(b) arrive with the vector
  lowering. A loop that is not proven to terminate tests its sticky flag every iteration
  (L2 constraint 3).

**LLVM emission** (`src/core/emit_llvm.zig`) writes LLVM IR text and lets `zig cc`
(clang) parse it. Text over the C API keeps the core free of a libLLVM dependency and is
cheap at S0's sizes; per-function bitcode caching is S1 work.

- **Typed accesses:** LLVM has opaque pointers, so "typed pointers" means every access is a
  typed `getelementptr inbounds T`/`load T` against a data pointer derived once per list
  value; parameters carrying list data get `noalias` and `readonly` where the IR proves the
  callee does not write (always, in S0).
- **Narrow types:** a value whose interval fits a narrower type is emitted in that type
  where it pays (loads with `!range`, `zext`/`trunc` at the edges). The vector lowering
  (*checkpoint B*, the spike's `llvm_direct_vector.zig` ported) emits `<16 x i16>` lanes,
  `pmaddwd` reductions and multiply-high reciprocals for constant divisors.
- **Arithmetic:** `exact`/`region` checks use `llvm.sadd/ssub/smul.with.overflow`;
  `proven` operations get `nsw`/`nuw`. Floor division over proven non-negative operands is
  `udiv`/`urem`; otherwise the fix-up `q - ((r != 0) & ((r ^ d) < 0))`.
- **Unions:** `Option`/`Result`/small unions travel as SSA pairs (`{tag, payload}`) and are
  stored field-wise into their destination (WP-10b's in-place rule by construction, so no
  stack temporary and no store-forwarding stall).
- **Float → int** (WP-10a) is inline: `fptosi` plus the range test `-2^63 ≤ x < 2^63`
  (false for NaN) branching to the trap.
- **Optimization:** debug `-O0`; release `-O3 -march=native` (L4: one platform; the host is
  the alderlake-class machine), LTO optional (the runtime is one small C file, compiled in
  the same `zig cc` invocation).

## 8. Runtime

**Choice: a minimal new runtime for S0,** `src/core/runtime/core_rt.c` (a few hundred
lines), linked as the only runtime object. It provides list and string storage blocks,
`argv` → `list[str]`, `int(text)` parsing with the pinned grammar (`docs/bytes.md`),
buffered stream printing, the trap reporter and process exit. `runtime_bench_now` stays the
benchmark's own `--link` C file.

**Why not link the existing runtime:**

- its blocks carry the two-count RC header and GC metadata, and its entry points take the
  QBE context first and follow the QBE aggregate ABI (`:myl_slice`), so linking even its
  list code drags the old ownership model into the new core;
- WP-5 (one-count RC on the shared runtime) is being changed right now by Codex lanes;
  binding to it would couple S0 to an ABI in flux;
- the plan's reuse target is the runtime's *algorithms* (text, dictionary, number
  formatting, I/O), which S2–S3 can port or link once WP-5 lands.

**The block layout S0 fixes, for S1:** a 32-byte header `{u32 count, u32 kind, i64 len,
i64 cap, i64 reserved}` followed by 32-byte-aligned data. The count is the single
saturating 32-bit count of D4. S0 creates blocks with count 1 and releases nothing (that
is the S1 ownership pass); the only free is the old block when a push outgrows it, which
the IR's uniqueness rule makes safe. String constants are emitted as static blocks whose
count is saturated (`0xFFFFFFFF`), so no release will ever free them.
S1 either keeps this runtime and grows it, or adopts the shared runtime if WP-5 lands with a
compatible block — a decision for S1 (plan §9's risk), not forced now.

## 9. Files and reachability

```
src/core/main.zig        CLI: build, dump-typed, dump-ir [--facts] (guardian orphan root)
src/core/pipeline.zig    one build: check → IR → facts (release) → LLVM → link
src/core/frontend.zig    front-end loading (module graph or single file), positions
src/core/typed_dump.zig  dump-typed
src/core/ir.zig          Core IR types, module/function/block/instruction
src/core/build.zig       typed.Program → Core IR
src/core/print.zig       textual IR (dump-ir, unit tests)
src/core/facts.zig       intervals, list facts, check marking
src/core/emit_llvm.zig   LLVM IR text
src/core/driver.zig      zig cc invocation and linking
src/core/runtime/core_rt.c
src/core/root_test.zig   test root (guardian test-reachability root); *_test.zig beside it
test/core/*.my           slice programs (int_math, control, overflow, bounds)
experiments/new-core-s0-20261005/  measure.py, build_all.sh, devloop.sh, results/
```

`guardian.toml` lists `src/core/main.zig` and `src/core/root_test.zig` as roots, so every new
file is reachable from one of them. The runtime C file is embedded into `mylang-core` with
`@embedFile` and written to the build's cache directory.

## 10. Tests and the dev loop

- **Unit tests** (`src/core/*_test.zig`, reached from `src/core/root_test.zig`): IR builder
  shapes on small programs checked from source (`print.zig` text compared exactly), facts,
  and emitter output fragments. Guardian rules apply (spec tags `NEW-CORE-*`).
- **End-to-end** (`src/core/e2e_test.zig`): builds each `test/core/*.my` program with
  `mylang-core` at debug and release and compares stdout (the first field, for programs that
  print a time) and the exit status with goldens recorded from the old core.
- **Differential** (`zig build test-core -Dcore-diff=true`): also builds each program with
  the old `mylang` and compares directly. The old compiler is built only in this mode.
- **Conformance subset** (*checkpoint B / S1*): `tests/lang` files whose functions the new
  core accepts, run under both cores; the refusal reasons are the coverage report.
- **`zig build test-core`** is the new core's lane gate; it is not attached to `zig build
  test` (the manager decides gate wiring).

## 11. Measurements (2026-10-05)

**Correctness.** `test/core/int_math.my` (the spike's `int_math.my`, kind 0 of
`compute/main.my`) prints `561601106` for `4096 300 7`, `8773872` for 64 and `562398344`
for 4100, at debug and release, identical to the old core's `--release` build; invalid
arguments exit 2 in both. `zig build test-core -Dcore-diff=true` also rebuilds all four
`test/core` programs with the old compiler and compares stdout and exit status: equal.

**Cycles per element** (`experiments/new-core-s0-20261005/measure.py`, the spike's
method: `perf stat` user cycles on CPU 10, start-up subtracted, 7 interleaved rounds,
SMT sibling idle; raw output in `results/int_math-cycles-2026-10-05.txt`):

| Configuration | 4096 × 4000 | 64 × 250000 | instr/elem (4096) |
|---|---:|---:|---:|
| old core, `mylang build --release` | 8.69 | 9.07 | 38.0 |
| new core release, `--no-facts` (every check exact) | 9.07 | 9.24 | 43.0 |
| **new core release (facts)** | **1.67** | **1.91** | 4.47 |
| spike level 1 (typed scalar), rebuilt from its branch | 1.67 | 2.00 | 4.47 |
| spike level 2 (explicit narrow-lane vector) | 0.36 | 0.59 | 1.22 |
| C ladder v5 (assumed ranges) | 1.73 | 1.98 | 4.46 |
| C ladder v7 (hand AVX2, u16 storage) | 0.33 | 0.47 | 1.21 |
| Rust (`compute-rust integer_math`) | 5.70 | 6.18 | 31.2 |

The facts alone reach level 1: LLVM sees `!range [0,1009)` on the element load, `nsw`
arithmetic and `udiv`/`urem`, narrows to 16-bit lanes and vectorizes by itself
(`vpmulhuw`, `vpmovzxwq` in the loop). Level 2 needs the explicit vector lowering
(checkpoint B). Without facts the new core is 4% slower than the old one (43 against 38
instructions per element): every check is an exact overflow intrinsic or compare in
program order, and nothing is hoisted yet.

**Dev loop** (`devloop.sh` under `scripts/build-slot.sh`, `-j2`, Debug compiler, warm
global cache, about nine other lanes on the host; raw output in `results/`):

| Loop | Old core (plan §2) | New core |
|---|---:|---:|
| One-line edit → rebuild (`zig build -Dcompiler-only` / `zig build core`) | 19.5–28.9 s | **1.8–2.2 s** (a first run measured 9.8–17.5 s, not reproduced) |
| Same under `zig build --watch -fincremental`, edit → new binary | 0.9–17 s | **0.13–0.55 s** |
| Edit → focused tests (`test-units -Dtest-filter=arena` / `test-core`, all 16 tests incl. 6 native builds) | 33.9 s | **4.4–5.5 s** |
| Tests with nothing changed | — | 1.1–1.2 s |
| `test-core -Dcore-diff=true` (also builds each fixture with the old compiler) | — | 25.6 s |
| Build the slice, debug (`-O0`), runtime object cached / empty cache dir | — (old debug build with `--link` fails, see §12) | 0.06–0.09 s / 0.22–0.26 s |
| Build the slice, release, warm / empty cache dir | 1.5–1.8 s / 2.0–2.5 s | 0.06–0.08 s / 0.28–0.31 s |
| Build `control.my` debug, warm / empty cache dir | 0.28 s / 0.51 s | 0.04 s / 0.14 s |

Caveats: the programs are tiny, so these say little about LLVM `-O0` on large programs
(the plan's 1–4.5 s cold code generation for `collections`/`text` is still the S1 risk);
"empty cache" means an empty `--cache-dir`, with Zig's global cache warm.

The default `zig build` is unchanged in behaviour: the new steps are off the install graph,
and guests built by the `mylang` binary before and after the branch's changes are
byte-identical (`control.my` debug, `int_math.my` release). The `mylang` binary itself
differs only because `src/compiler.zig` gained one line (debug-info line numbers).

## 12. Open questions and risks for the manager

1. **The list-length assumption** (`max_list_length = 2^47`, §5) is the only non-proven
   input to the facts. Accept it as a language/platform rule (L4), or require a runtime
   guard?
2. **Runtime for S1:** keep growing `core_rt.c` with one-count RC (§8), or adopt the shared
   runtime once WP-5 lands? Recommendation: keep our own block layout and port the shared
   runtime's algorithms (text, dictionaries, formatting) into it, because the shared
   runtime's ABI is QBE-shaped.
3. **How strict is the stderr oracle?** The first trap line and `MYLANG-TRAP` record match;
   the trace has only the innermost frame until PC-table traces land in S1. Is that
   acceptable for the conformance comparison (stdout + exit status + trap kind)?
4. **`Stream` selection:** `main`'s `Stream` parameter writes to stderr only when it is
   named `err` (my reading of CLAUDE.md); confirm that this is the checker's rule and not a
   type distinction S0 should take from `typed.Program`.
5. **Gate wiring:** `zig build test-core` (5 s after an edit) is the proposed lane gate;
   `-Dcore-diff=true` adds the old compiler's build (25 s). Which runs where?
6. **Next for checkpoint B**, in this order unless redirected: the vector lowering (spike
   level 2, required for the S0 exit check "at or below the spike"), the facts' verify mode
   and a whole-program differential fuzz, then `float_math`, `call_direct`, `branch_*`,
   `binary_search` and the unmodified `compute/main.my`.
7. **Old-core issue found:** `mylang build` *without* `--release` and with `--link
   file.c` fails (`native_clock.c:1:1: error: FileNotFound`, `NativeToolFailed`) even
   with an absolute path; release builds work. Not investigated further.
8. **Risks:** the fact pass is now load-bearing for soundness (a wrong interval silently
   drops a check); the verify mode and fuzz (checkpoint B) are what keep it honest. The
   builder refuses rather than guesses (`E_CORE_UNSUPPORTED`), so coverage, not
   correctness, is what limits it today: no records, dictionaries, sets, string operations
   beyond `int(text)` and printing, `assert`, `with`, or element stores yet.
