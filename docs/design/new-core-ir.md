# The new compiler core: Core IR, facts and LLVM emission (S0 design)

**Status:** stage S0 complete (checkpoints A and B, `docs/audits/new-core-plan-2026-10-05.md`
§6), 2026-10-05. Branch `claude/new-core-s0-20261005`. Decisions N1–N5, L1–L4 and D1–D4
are fixed inputs. Sections marked *design only* describe S1+ work that S0 leaves room for
but does not build. Measurements are in §11.

**Built in S0** (about 5.7k lines of Zig plus 280 of C, 0.9k of them tests): `mylang-core
build` compiles the S0 compute kernels (`integer_math`, `float_math`, `call_direct`,
`branch_predictable`, `branch_mixed`, `binary_search`), a multi-kind program with the
benchmark's per-element `kind` dispatch, and a control-flow program from `typed.Program`
through the Core IR and LLVM. Release builds run inlining, loop unswitching, the fact pass,
trip-count guards and the narrow-lane vector lowering; `--verify-facts` checks every fact
at run time, and a whole-program differential fuzz compares all of it with the old core.

## 1. Shape of the core

```
FILE.my ─► front end (module "mylang": lexer, parser, sema)      reused, unchanged
              │  typed.Program  (src/typed.zig)                    decision N3
              ▼
          src/core/build.zig      typed tree → Core IR (SSA, on-the-fly construction)
          src/core/passes.zig     release passes, in order:
            inline.zig            single-block leaf calls inlined
            version.zig           loop unswitching on invariant branches
            facts.zig             intervals (int and float), list facts, trip counts
            version.zig           trip-count guarded copies of wide reductions, facts again
            vector.zig            narrow-lane vector plans for counted reductions
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

`test/core/int_math.my` (kind 0 of the compute benchmark, from the WP-8 spike) needs:
`list[str]` arguments, `len`, `int(text)` with `match` on `Option[int]`, a comprehension
over `range`, nested counted loops, `//` and `%`, a C `extern` call through a `Host`
capability, `out.print` of two integers and `main`'s exit status. The other S0 kernels add
floats, `list[bool]`, helper calls and a data-dependent `while` over a list parameter;
`compute_s0.my` puts all six kinds behind the benchmark's per-element `kind` dispatch.
The unmodified `benchmarks/runtime/expanded/compute/main.my` is refused cleanly
(`E_CORE_UNSUPPORTED: record type`, then `Result`, `bytes` and function values): those are
S1. `mylang-core build FILE.my -o OUT [--release] [--link C]` runs the whole pipeline.
Results are in §11.

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
- **Float intervals** (finite doubles, one ulp of outward rounding per operation, none
  for a possible NaN or infinity) prove `int(f)` in range; a value proven inside `i32` is
  converted to and from double through `i32`, which AVX2 vectorizes (`float_math`).
- **Trip-count guards** (`version.zig`, the first runtime guard). A reduction `acc += s`
  with `s ≥ 0` that the 2^47 rule cannot bound (`float_math` sums values up to 1.07·10^6)
  gets a guarded copy: `if bound ≤ K` (K the largest trip count for which the sum fits,
  less one trip of slack) the copy, whose sum the next fact pass proves, runs; otherwise the
  original with its exact checks. The guard's taken edge is a single-predecessor block, so
  the ordinary edge refinement does the proof.
- **Loop unswitching** (`version.zig`) uses the same copy machinery: a branch in an
  innermost loop whose condition compares only loop-invariant values becomes a guard before
  the loop, with the branch constant in each copy. The benchmark's `if kind == 0 … elif …`
  per element becomes one straight loop per kind (up to 16 copies per function).
- **Runtime guards over list data** (*S1*): when a list's element range is unknown (file
  data), the same copy machinery can guard on a `min`/`max` pass over the immutable list.
  The ladder study recovered the whole gain this way in 3 of 4 cases.
- **Verify mode** (`--verify-facts`, from the spike's `llvm_direct_verify.zig`). Every
  check the facts proved is emitted anyway, every fact interval is asserted after its
  definition, blocks the facts call unreachable assert that they never run, comparisons
  are not folded, and no fact-derived promise (`nsw`, `!range`, narrowed conversions,
  vector code) reaches LLVM. A violated fact traps `R_CORE_FACT`. `--sabotage-facts` is the
  same build with one deliberately wrong rule (`x % c ∈ [0, c-2]`), for testing the
  verifier and the fuzz.

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
- **Release builds** (L2). A region is the code between two visible effects (stream
  writes, capability/`extern` calls, exit). L2 lets the emitter (a) hoist a bounds check to
  one `high ≤ len` test before a counted loop, (b) merge overflow flags into one sticky `or`
  tested at the region exit (every iteration in a loop not proven to terminate), and (c)
  drop checks the facts prove. **S0 needed only (c):** in every S0 kernel the facts prove
  every check in the hot loop, or the trip-count guard selects a copy where they are proven,
  so (a) and (b) were not built; S0 emits every remaining check exactly, which is a valid L2
  implementation. They are the lever for loops over data with no facts (S1–S2, file data).

**LLVM emission** (`src/core/emit_llvm.zig`) writes LLVM IR text and lets `zig cc`
(clang) parse it. Text over the C API keeps the core free of a libLLVM dependency and is
cheap at S0's sizes; per-function bitcode caching is S1 work.

- **Typed accesses:** LLVM has opaque pointers, so "typed pointers" means every access is a
  typed `getelementptr inbounds T`/`load T` against a data pointer derived once per list
  value; parameters carrying list data get `noalias` and `readonly` where the IR proves the
  callee does not write (always, in S0).
- **Narrow types:** element loads carry `!range`; proven-`i32` conversions go through
  `i32`. The vector lowering (`vector.zig`, the spike's `llvm_direct_vector.zig` ported to
  the Core IR) takes a counted reduction whose body is a straight chain (decided branches
  followed) or contains if/else diamonds: `<16 x i16>` lanes (or `<8 x i32>`), `packusdw`
  loads of the `i64` storage, `pmulhuw` reciprocals for constant divisors (checked
  exhaustively over the proven dividend range), lane `select`s for the diamonds with
  `list[bool]` masks permuted like the packed values, and `pmaddwd` into 32-bit lanes folded
  into the 64-bit total per block. It emits the vector part in front of the unchanged scalar
  loop, which then runs the remaining `trips mod lanes` elements from the vector part's
  counter and sum; whole-function emission means no call is spliced into the host loop.
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
**Decided (user, 2026-10-05): the new core keeps its own runtime.** `core_rt.c` grows with
this block layout and its single saturating count. The shared runtime (`src/native_*.c`,
`src/qbe_runtime*.c`: two counts, the GC, a QBE-shaped ABI) is never linked. Its algorithms
are ported into `core_rt` as S1–S3 need them (text and UTF-8, dictionaries and sets, number
formatting and parsing, I/O and capabilities), as C adapted to these blocks or rewritten,
each noting the old function it was ported from.

### 8.1 Portability

L4 holds: x86-64 Linux with AVX2 is the only target. Platform assumptions are kept in a few
named places so a later macOS (x86-64 or arm64) or Windows port is local work:

| Target-specific item | Where it lives |
|---|---|
| LLVM triple, CPU flags (`-march=native`), vector width, available intrinsics | `src/core/target.zig` (`Target`, `current`); read by `driver.zig`, `emit_llvm.zig`, `vector.zig` |
| Address-space bound behind the list-length rule (47 bits) | `target.zig` `user_address_bits` / `maxListLength`; `facts.max_list_length` is derived from it |
| x86 intrinsics (`packusdw`, `pmulhuw`, `pmaddwd`) | `vector.zig`, each behind `target.x86_avx2` with a generic LLVM fallback (plain `trunc` loads, vector `udiv`, 64-bit lane sums); `--generic-vectors` builds the fallback and the tests check its results |
| C ABI of `extern` calls (SysV x86-64, scalars and pointers) | `src/core/c_abi.zig` |
| Operating-system calls (write, exit; later clock, files, network, environment) | the platform-layer section at the top of `runtime/core_rt.c` (`os_write`, `os_exit`); argv arrives through the LLVM-emitted C `main` |
| Traps and traces (today: report and `_exit`, innermost frame only) | `myl_core_trap` in `core_rt.c` is the only trap entry the emitter calls; PC-table traces (S1) go behind it; `target.zig` names the mechanism (`Traps`) |

## 9. Files and reachability

```
src/core/main.zig        CLI: build, coverage, dump-typed, dump-ir [--facts] (guardian orphan root)
src/core/pipeline.zig    one build: check → IR → release passes → LLVM → link
src/core/passes.zig      the release passes in order
src/core/inline.zig      single-block leaf inlining
src/core/version.zig     loop copies behind a guard: unswitching, trip-count guards
src/core/vector.zig      narrow-lane vector plans and their LLVM
src/core/target.zig      the target description (§8.1)
src/core/c_abi.zig       C ABI of extern calls (§8.1)
src/core/frontend.zig    front-end loading (module graph or single file), positions
src/core/typed_dump.zig  dump-typed
src/core/ir.zig          Core IR types, module/function/block/instruction
src/core/build.zig       typed.Program → Core IR
src/core/print.zig       textual IR (dump-ir, unit tests)
src/core/facts.zig       intervals (int, float), list facts, counted loops, check marking
src/core/emit_llvm.zig   LLVM IR text
src/core/driver.zig      zig cc invocation and linking
src/core/runtime/core_rt.c
src/core/root_test.zig   test root (guardian test-reachability root); *_test.zig beside it
test/core/*.my           the S0 kernels, compute_s0 (multi-kind), control, overflow, bounds
experiments/new-core-s0-20261005/  fuzz.py, coverage.py, measure_kernels.py,
                                   build_kernels.sh, measure.py, build_all.sh, devloop.sh, results/
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
- **Fuzz** (`experiments/new-core-s0-20261005/fuzz.py`): whole-program differential fuzz
  against the old core with debug, release and verify builds; `--sabotage` checks that the
  verify build catches a wrong rule (§11).
- **Coverage sweep** (`coverage.py` over `mylang-core coverage`): accepted functions and
  refusal reasons per corpus. A `tests/lang` conformance subset (whole files the new core
  accepts, run under both cores) waits for S1, when enough of a file builds.
- **Gate wiring (decided by the manager, 2026-10-05):** `zig build test-core` (31 tests) on
  every change; `-Dcore-diff=true` before each commit batch and at hand-off; neither is
  attached to `zig build test`.

## 11. Measurements (2026-10-05)

Raw outputs are under `experiments/new-core-s0-20261005/results/`.

**Correctness.** Every S0 kernel (`test/core/*.my`) prints the old core's checksum at 4096,
64 and 4100 elements, at debug and release; so does the multi-kind `compute_s0.my` for all
six kinds, and `control.my` its whole output and exit status. `zig build test-core
-Dcore-diff=true` rebuilds the fixtures with the old compiler and compares directly.

**Fuzz** (`fuzz.py`: random S0-vocabulary programs, each built four ways — old core
`--release` as the oracle, new core debug, release and `--verify-facts` — and run with
five argument sets; stdout, exit status and trap kind must agree; a verify build must
never trap `R_CORE_FACT`):

| Run | Cases | Comparisons | Disagreements | `R_CORE_FACT` | Vectorized / versioned cases |
|---|---:|---:|---:|---:|---:|
| seed 21, before the fixes | 200 | 2,955 | 3 compiler crashes (fixed, now tests) | 0 | 42 / 22 |
| seed 31, final | 200 | 3,000 | 0 (3 reported: the old core printed `R_LIST_BOUNDS:` without the `error[…]` prefix; same stdout, status and kind) | 0 | 44 / 41 |
| sabotage, seed 78, final | 60 | 710 | 0 | caught in **55 of 60** cases | 12 / 11 |

The first fuzz run (before the vector lowering) found a real miscompile: a variable divisor
of -1 returned the dividend; and building `branch_mixed` found a second (masks loaded in
order against values loaded in `packusdw` order). Both are fixed and tested.

**Cycles per element** (`measure_kernels.py`: `perf stat` user cycles on CPU 10, start-up
subtracted, median of 7 interleaved rounds, a heavily loaded host; every configuration's
checksum identical; "spike" is its level-2 build of the unmodified compute benchmark):

| Kernel (4096 × 4000 / 64 × 250000) | Old core | **New core** | Spike L2 | C ladder (plain C / hand AVX2) | Rust | Zig ReleaseSafe |
|---|---:|---:|---:|---:|---:|---:|
| integer_math | 8.70 / 9.07 | **0.36 / 0.49** | 0.38 / 0.64 | 1.73 / 0.33 (v5/v7) | 5.71 / 6.18 | 7.81 / 8.32 |
| float_math | 8.30 / 8.43 | **1.57 / 1.71** | 1.61 / 1.85 | 1.38 / 1.28 (v5/v8) | 6.97 / 7.33 | 6.51 / 7.03 |
| call_direct | 3.04 / 3.16 | **0.30 / 0.32** | 0.31 / 0.49 | — | 2.02 / 2.94 | 3.02 / 4.12 |
| branch_predictable | 4.03 / 4.15 | **0.40 / 0.50** | — | — | 3.20 / 3.25 | 7.70 / 7.91 |
| branch_mixed | 4.12 / 4.13 | **0.40 / 0.49** | — | 0.62 / 0.30 (v8/v7) | 4.87 / 4.52 | 9.28 / 9.06 |
| binary_search (iterations / 10) | 144 / 33 | **87 / 30** | — | — | 38 / 20 | 137 / 28 |

Every kernel is at or below the spike's level 2 where it has one, and below the C ladder's
best compiler-derived rung for `branch_mixed`; `float_math` is 13% above the ladder's
plain-C v5 (no spike-level gap). `binary_search` has no facts to use (its indices are
data-dependent) and is bound by branch prediction; Rust is 2.3× faster there (S1: relational
facts `low ≤ middle < high ≤ len`, and if-conversion of trap-free diamonds).

**Whole-function emission does not slow the other loops** (`compute_s0.my`: all six kinds
in one `main` with the benchmark's per-element `if kind == …`; unswitching gives each kind
its own straight loop): integer_math 0.36, float_math 1.57, call_direct 0.30, both branch
kinds 0.40 cycles/element, the same as the single-kernel programs, against 3.7–10.1 for the
old core on the same program. `binary_search` is the exception, 144 against 87 alone: the
same instructions with 2.3× the branch misses (LLVM's layout of the search loop differs in
the large function; the old core shows the same sensitivity in the other direction).

**Dev loop** (`devloop.sh`: Debug compiler, `-j2`, build slot; raw output in `results/`):

| Loop | Old core (plan §2) | New core, checkpoint A | New core, end of S0 |
|---|---:|---:|---:|
| One-line edit → `zig build core` | 19.5–28.9 s | 1.8–2.2 s | 2.5–6.0 s |
| Same under `--watch -fincremental` | 0.9–17 s | 0.13–0.55 s | not re-measured |
| Edit → `zig build test-core` | 33.9 s (`test-units` arena) | 4.4–5.5 s (16 tests) | 6.5–7.5 s (31 tests, ~40 native builds) |
| `test-core`, nothing changed (tests rerun) | — | 1.1 s | 3.8–3.9 s |
| `test-core -Dcore-diff=true` | — | 25.6 s | 46.6 s (loaded host) |
| Build the slice, debug, runtime cached / fresh cache dir | old debug + `--link` fails | 0.06–0.09 / 0.22–0.26 s | 0.06–0.07 / 0.17–0.19 s |
| Build the slice, release, warm / fresh | 1.4–1.8 / 1.9–2.5 s | 0.06–0.08 / 0.28–0.31 s | 0.06 / 0.19 s |

The end-of-S0 column is from two runs at load average 5–9 on the 20-thread host. A run
during a load spike near 50 measured 8–16 s per rebuild and 28–51 s per test step (the old
core's release build of the slice took 6 s in the same run), kept in `results/` for
comparison. The compiler is about 2.5× the size it was at checkpoint A.

The default `zig build` is unchanged in behaviour: the new steps are off the install graph,
and guests built by the `mylang` binary before and after the branch's changes are
byte-identical. The `mylang` binary differs only because `src/compiler.zig` gained one line.

**Coverage sweep** (`coverage.py`, `mylang-core coverage`: each function built alone;
the first construct the builder refuses is the reason):

| Corpus | Functions | Accepted |
|---|---:|---:|
| `examples/` | 207 | 59 (29%) |
| `bench/parity` | 123 | 39 (32%) |
| `tests/lang` (with a trivial `main` added where missing) | 3,038 | 896 (29%) |
| `benchmarks/runtime` (compute, collections, text) | 141 | 36 (26%) |
| Lox port (`bench/lox-mylang`) | not checkable: it uses `class` (E_VALUE_CLASS) | — |

Refusal reasons over all corpora — the S1 vocabulary list, in order: record types (741) and
record construction/field access (206+7), dictionaries (211, S2), `mut` parameters (174),
`bytes` (142, S2), `Result` (138), unions (130), fixed arrays (114), `with` scopes (91),
shifts and other operators (41), domains (39), element writes (38), length of strings and
other collections (37), function values (37+13), `assert` (37), capabilities and file
handles (33), sets (25), `sort` (18), `join`/`split`/`slice` (S2).

## 12. Open questions and risks for the manager

1. **S1 order.** The sweep says records first (741+213 functions), then `mut` parameters,
   `Result`/unions with error traces, fixed arrays, `with` scopes and `assert`; dictionaries,
   sets and `bytes` are S2. Records, unions and `Result` need the ownership pass (§6) only
   when they hold managed values, so a first S1 lane can take scalar-field records and
   unions before RC lands.
2. **L2 regions were not needed in S0** (§7): every hot-loop check was proven or
   guarded. They become necessary for loops over data without facts; do you want them in
   S1, or with the runtime guards over list data?
3. **binary_search** stays 2.3× behind Rust: relational facts and if-conversion of
   trap-free diamonds (S1–S2).
4. **Per-function object caching for `-O0`** (N5) is not built: a whole S0 program compiles
   in under 0.3 s, so the cost is invisible until S1's larger programs.
5. **Trap traces** still name only the innermost frame (PC-table traces: S1).
6. **Lox port:** the version on `bench/lox-mylang` does not check in this tree (`class`
   under value semantics, `E_MUTATION_OVERLAP` with legacy sharing); the sweep needs its
   value-semantics port.
7. **Risk:** the fact pass, the copy machinery (versioning, unswitching) and the vector
   lowering are all load-bearing for soundness. The verify mode and the fuzz are the
   guard: keep `fuzz.py` (and `--sabotage`) in the lane gate for every change to them.
