# The new compiler core, stage S1: values, ownership and conformance (design)

**Status:** design for S1, 2026-10-05. Branch `claude/new-core-s1-20261005`. Companion to
`new-core-ir.md` (the S0 design, whose §5 facts, §6 ownership sketch and §7 emission this
note makes concrete). Inputs: plan `docs/audits/new-core-plan-2026-10-05.md` §6 (S1 scope),
decisions N1–N5, R1 (own runtime), D1–D4
(`gc-retirement-and-one-count-plan-2026-10-03.md` §4.2), checkpoints A and B1.

**Scope of S1:**
- records;
- `Option`/`Result` with `?` and error traces;
- unions built in place;
- unique and immutable lists with append, pop, index and element writes;
- one-count RC in `core_rt.c`;
- `mut` parameters;
- the N6 decision.

**Rows:**
- `record_reads`, `tagged_stack`, `mutate_unique`, `mutate_shared` (`benchmarks/runtime/ports/main.my`);
- `record_construct`, `record_update`, `option_handle`, `result_propagate` (`expanded/compute/main.my`);
- `list_scan`, `list_append`, `list_filter`, `alloc_short`, `alloc_retained`, `mutate_nested` (`expanded/collections/main.my`).

**Not in S1:**
- `call_indirect` (function values) and `packet_decode` (bytes);
- dicts, sets, text beyond `len`/`int()`/literals/`print`, generics, fixed arrays `[N]T`.

Those are S2.

## 1. What the front end already gives us

`typed.Program` is already value-functional. The S1 builder lowers it without inventing any semantics:
- Field writes `p.x = v` arrive as `assign(p, update(p, {x: v}))`.
- Element writes `xs[i] = v` arrive as `replace(xs, i, v)`.
- `?` arrives as `propagate{value, output}`.
- Variants arrive as `variant{tag, value}`, `unwrap` and `wrap`.
- A `mut` parameter's type tells the ABI: `typed.referenceRecord` and `referenceMut`.
- Boxed recursive fields are marked `Field.boxed` / `Variant.boxed`.

D3 (MUT-EXCLUSIVE-4, `E_MUTATION_OVERLAP`) is enforced by the checker (`src/mut_exclusive_test.zig`). So no write in the new core needs a pending-receiver token.

## 2. IR additions (the IR-first step, §8)

**Types (`ir.Compound`):**
- `record(fields)`: field types in declaration order.
- `union(cases)`: one payload type or none per case; tag 0..n−1 in the checker's case order. This also covers `Option[T]` and `Result[T, E]`.
- `list(T)`: elements may now be scalars, `str`, a list, a record or a union. `T` keeps the element type, not a storage type.
- `box(T)`: an immutable RC block holding one `T`, for `boxed` fields and payloads.

**New operations.** Every update returns a new value; whether it reuses storage is decided by §6:

| op | operands | result | check |
|---|---|---|---|
| `record_make` | fields in `extra` | record | none |
| `record_get` | `a` record, `data` field index | field value | none |
| `record_set` | `a` record, `b` value, `data` field | record (consumes `a`) | none |
| `union_make` (exists) | `data` tag, `a` payload | union | none |
| `union_tag`, `union_payload` (exist) | | | |
| `list_set` | `a` list, `b` index, `extra[0]` value | list (consumes `a`) | bounds |
| `list_pop` | `a` list | list (consumes `a`); the builder reads `list_get(a, len−1)` first | empty-list |
| `list_get_field` | `a` list, `b` index, `data` field path | field of an inline record element | bounds |
| `box_make` / `box_get` | value / box | box / value | none |
| `retain`, `release` | `a` managed value | none | none |
| `is_unique` | `a` managed value | `bool` | none |
| `err_trace` | `data` site, `a` mode (origin / append) | none | none |

`list_copy` (B1) stays; it becomes the copy arm of a copy-on-write branch.

`list_get_field` lets a list of records be read field by field, so a whole record is never loaded or copied just to read one field (`record_reads`). The builder emits it for `xs[i].f` (`field(index(..))`).

## 3. Records

**Value semantics, two representations, one rule.** A record is an SSA value in the IR, always. The emitter chooses the representation by size:
- **Small:** every field flattened to scalars or pointers, at most 4 words (32 bytes). Lowered as LLVM struct values (`insertvalue`/`extractvalue`), passed in registers, returned in registers (`{i64, ptr}` ≤ 2 words) or via `sret` (3–4 words). SROA splits them, so a small record costs nothing over separate locals.
- **Large:** more than 4 words. Passed by `ptr` to read-only caller memory (`readonly noalias`), returned through `sret`.

**Where records live in memory:**
- in list elements, inline as an array of structs with stride `sizeof(record)` and 8-byte alignment;
- in `box(T)`;
- in `sret`/argument slots.

**Construction in place (WP-10b).** `record_make` is never materialized in a temporary and then copied. The emitter fuses it with its single consumer:
- `list_push(l, record_make(...))` / `list_set` → field stores into the new slot;
- `ret record_make(...)` with `sret` → field stores into the return slot;
- `box_make(record_make(...))` → field stores into the box.

No `memcpy` and no aggregate `store` of a loaded struct is ever emitted for records of 64 bytes or less. This is the rule that removes the 16-byte blit store-forward stall.

**Field reads and writes:**
- A read is `record_get`, folded to `extractvalue` for an SSA record, or a `getelementptr`+load when the record is in memory (`list_get_field`).
- A write `record_set` on a small record is `insertvalue`, so no RC and no memory.
- On a record in a list, `list_set(l, i, record_set(list_get(l, i), f, v))` is pattern-fused by the emitter into one field store, once ownership says `l` is unique: `record_update` and `xs[i].f = v`.

**Nesting:**
- Nested records are flattened into the parent (`a.b.c` is one field path).
- Boxed (recursive) fields go through `box(T)`: a write copies the path to it (`typed`'s RECURSIVE-VALUES-2).

**Managed fields** (a record holding a list or `str`): the record is still a value. Copying it means `retain` on each managed field. A record dies by `release` on each managed field. §6 inserts these per field. A record with no managed field needs no RC at all.

**Facts:**
- A record value is immutable, so a fact about `record_get(r, i)` holds for `r`'s lifetime.
- Field intervals propagate through `record_make`/`record_set` (the interval of field `i`), so `record_update`'s field arithmetic is proven exactly as scalars are in S0.

## 4. `Option`, `Result` and unions

**Representation:**
- `union(cases)` is an SSA pair `{tag, payload words}` in registers: `tag: i8`, payload as `max_case_words` `i64`s.
- In memory it is the same layout, with an 8-byte tag word followed by the payload words.
- **Niche:** `Option[T]` for a managed pointer `T` is the pointer itself, with null as `None` (as `option_niche.my` expects). `Option[bool]` and small scalar `Option`s stay `{i8, T}`.
- Payloads that are records are flattened into the payload words. Boxed payloads are a `box` pointer.

**Built in place.** `union_make` follows the record rule: fused with its consumer into stores of the tag word and the payload words (`tagged_stack` pushes unions into a list). A `match` on a union in a list reads the tag with `list_get_field`, then only the payload fields the arm uses.

**`?` (`propagate`)** lowers to:
- `union_tag`, then a branch;
- on the error arm: `err_trace(site, append)`, wrap into the caller's error-union case when `output` differs, release the live owned values, `ret`;
- on the success arm: `union_payload`.

Building `Err(...)` emits `err_trace(site, origin)` (ERROR-TRACE-1).

**Error traces (ERROR-TRACE-1..5):**
- `err_trace` calls `myl_core_err_trace(site)`, which is cold, `nounwind` and `"call-inline-cost"="0"`. It sits only on Err paths, so a successful `?` executes nothing extra.
- The trace is the runtime's ring of the origin plus 32 site indices into `@myl_core_sites`, which already holds line, column and function.
- The entry wrapper prints `error: VALUE` and the trace when `main` returns `Err`.
- Debug and release builds are identical here.

**Trap traces (the PC table).** For every call instruction the emitter writes an inline-asm label right after the call into section `.myl_sites` as `(address, site)`. The trap handler then:
- walks the stack with `_Unwind_Backtrace` (from `.eh_frame`, so no frame-pointer cost);
- maps each return address to the nearest label at or after it.

The label follows its call, and no other call can sit between them. This gives "in f at file:line:col" for every frame, with no per-call runtime work.

**Trap regions.** Debug builds keep exact checks. Release builds keep exact checks too unless a row misses the L1 gate because of them. Then L2 lowering follows §7 of `new-core-ir.md`: bounds hoisted to one `high ≤ len` test before a counted loop, and a sticky overflow `or` at the region exit. That is an S1 stretch, owned by the values lane.

## 5. Lists

**Block layout (S0, unchanged):** a 32-byte header `{u32 count, u32 kind, i64 len, i64 cap, i64 reserved}`, then data aligned to 32 bytes.
- `reserved` now holds the element descriptor: element size plus the `managed` bit, so a release frees its children.
- Elements are stored inline: scalars, pointers, and records or unions at their stride.

**Operations:** `list_new`, `list_len`, `list_get`, `list_get_field`, `list_push`, `list_set`, `list_pop` and `list_copy`. All updates consume their operand and return a new value.

**Copy on write under one count.** `own.zig` (§6) gives every consuming update one of three forms:
1. **Statically unique** (fresh in this function and dead after, B1's rule extended to records and unions): in place, no test.
2. **Owned but maybe shared** (a phi of owned values, a call result, a loaded element):
   `if is_unique(l): in place else: l2 = list_copy(l); release(l); update l2`.
   `is_unique` is `count == 1` from one load. A saturated count (D4) is never unique.
3. **Borrowed** (a non-`mut` parameter, an element read through a borrow): always `list_copy` first. The callee does not own the block.

`mutate_shared` takes form 2 (`snapshot = values` makes the count 2, so the first write copies). `mutate_unique` takes form 1.

**D1, live place.** The builder already re-reads the root variable at every step (S0 §6). That variable is an SSA value that changes when the body writes it. A borrow of the iterated list at loop entry (no RC traffic, invariant length) is used only when the builder proves:
- no write to the root local or a path under it;
- no `mut` pass of it in the body.

Otherwise each step reads the current version and performs the iteration check.

**D2:** dict views are S2. **D3:** checker-enforced (§1). **D4:** §6.

**How mutation interacts with facts.** Facts attach to SSA values, and an update produces a new value:
- A list fact on `l` (length, element hull) never applies to `l'`.
- `list_push`/`list_pop` give `l'` the length `len(l) ± 1` when `len(l)` is a known `Ref`.
- `list_set` gives the element hull `hull(l) ∪ range(v)`.
- Length bounds (checkpoint A) refer only to immutable parameters. A `mut` parameter is a place (§7) and is never a bound's list.
- The B1 invariant in `new-core-ir.md` §5 is the contract: an update may reuse a block only when the old value is dead (form 1 or a passing `is_unique`), so no live `Ref` ever observes a changed length.

## 6. One-count RC (`own.zig`, after facts)

**Runtime (`core_rt.c`):**
- `count` is a `u32`; `0xFFFFFFFF` is IMMORTAL/saturated (D4), which string literals already use.
- **Retain** is `if (c != SAT) c += 1`, and on overflow to SAT the object stays SAT.
- **Release** is `if (c != SAT && --c == 0) myl_core_free(p)`. `myl_core_free` reads `kind` and the element descriptor and releases children iteratively, with no recursion depth.
- All of this is single-threaded and non-atomic.

**Emission:**
- `retain`/`release` are emitted *inline* (load, add, store on the `count` word), each access tagged with a distinct TBAA type `myl.count`.
- The free path is an out-of-line `cold` call.
- Element and field accesses carry a different TBAA type. LLVM's GVN and DSE can then fold a `retain`/`release` pair on the same pointer with no intervening possible alias (a call or a `myl.count` store). LLVM itself removes the dead pairs this pass leaves.

**Ownership states per managed SSA value:**
- `owned` (+1): results of `*_make`, `list_new`, calls, `list_copy`, updates.
- `borrowed`: parameters other than `mut` ones; `list_get` results of managed elements while the container is live.

**Insertion rules:**
- **Last-use move:** an owned value's last use, if it is a consuming use (update, store into a container or record, return, `mut` slot write, phi operand), takes the value without RC.
- **Release:** an owned value with no consuming last use gets `release` after its last use. If it dies on a CFG edge, the release goes on that edge, in a split block.
- **Escape of a borrow:** a borrowed value that escapes (stored, returned, passed as owned) gets `retain` first.
- **Phis:** every operand is made owned on its edge, by a retain if it is borrowed.
- **Borrow inference:** reads (`len`, `get`, compare, print, a borrowed argument) of a value whose owner is live across the read need nothing.
- **Traps** run no releases (RC-TRAP-TEARDOWN-1).
- **`?` and early `ret`** release the live owned values on that path. Liveness is computed per block, so this falls out of the release rule.

**Uniqueness** comes from the same liveness. Form 1 of §5 is "owned, fresh origin, no other live sharer" (B1's `unique`). Form 2 is "owned, otherwise".

## 7. `mut` parameters

**Semantics:** `inout`. The callee's writes, including a rebinding of the whole parameter, reach the caller's variable. The checker guarantees the call-site marker, a mutable local argument, and no overlap (D3).

**ABI:** a `mut` parameter is a `ptr` to the caller's slot: an `alloca` holding the list pointer, or the record or union words.
- The callee loads from the slot at function entry and after every call that receives the slot, and stores before each such call and at every return.
- In between, the value is an ordinary SSA value. `mem2reg`/SROA erase the slot in leaf callees and after inlining.
- The caller does: `store v → slot; call f(slot); v' = load slot`.

**Ownership:** the slot owns its value (+1). The callee may update in place only after `is_unique`. A count of 1 means only the caller's variable holds the block.

**Facts:**
- Every load from the slot is a new SSA value with no facts carried over: no list facts, no intervals beyond the element type, no length bound.
- Facts derived *within* one load-to-store stretch are as precise as for locals.
- Length bounds never use a `mut` parameter as their list.

## 8. Debug builds (N5), measured 2026-10-05

| File | `mylang-core` debug rebuild | Release | Old core (QBE) debug |
|---|---:|---:|---:|
| 145 lines | 0.05 s | 0.09 s | 0.44 s |
| 2,405 lines | 0.19 s | 0.85 s | 3.0 s |

These are wall times on CPUs 4–9, cold zig cache for the edited file; the largest `tests/lang` file is 1,676 lines and the median 92. Whole-file `-O0` is ~40× inside the 10 s rebuild budget.

**Decision:** per-function object caching is deferred to S4 (projects). S1 caches only the runtime object, as today. The S1 budget to hold:
- a debug build of any S1 conformance file in under 0.5 s;
- `zig build test-core` in under 5 min.

## 9. Conformance runner

**Command:** `mylang-core test FILE.my [--release] [--filter S]`.
- It checks `FILE.my` with the old runner's stub (`def main() -> int: return 0` appended, `src/native_test_snapshot.zig`).
- It builds **one executable per file**, whose generated `main(argc, argv)` dispatches on `argv[1]` = the test's qualified name, so each test is its own process (trap isolation) without one build per test.
- **Discovery** reuses `src/native_test_cases.zig`'s rule: `test_*` or `@test`, returning `bool` or `Result[bool, E]`. Property tests with parameters are out of S1.
- **Per test** it prints the old runner's line (`passed|failed mod::test_x`) and the summary line. Exit status: 0 ok, 1 failure, 3 empty.

**Comparison with the old core:** `experiments/new-core-s1-*/conformance.py FILES` runs:
- `mylang test FILE --json` (old core);
- `mylang-core test FILE` at debug and release.

It requires the same set of test names, the same pass or fail per test, and the same trap code for a trapping test. The trap position may differ under L2. The S1 exit check is "every file below: identical, debug and release". It runs in test-core as a pinned list.

**The S1 set.** These 13 files use only S1 features today:
- `rc_element_moves`, `rc_plain_projection`, `local_stack_list`, `rc_loop_uniqueness`;
- `mut_record_call_window`, `mut_collection_call_window`, `exclusive_ownership`, `argument_evaluation_order`;
- `gc_mut_argument_roots`, `rc_mut_aliases`, `rc_mut_uniqueness`, `rc_plain_update_paths`;
- `rc_readonly_body`.

**S1 adds 18 files.** Fifteen need only the §11 interim arena rule (dependency code A) or floats, which S0 has:
- `rc_named_record_writes`, `rc_plain_record_writes`, `closed_record_inout`;
- `rc_fresh_constructors`, `rc_fresh_spans`, `rc_fresh_returns`;
- `positive_list_index`, `rc_read_list_versions`, `rc_fresh_loop_roots`, `rc_scalar_loops`;
- `rc_scope_inline`, `rc_empty_frames`, `rc_inert_receivers`, `rc_plain_list_writes`, `rc_loop_versions`.

Three need a small text subset that S1's runtime gets: `str` literals, `print`, `==`, and `list[str]` fields. They are `rc_tree_drains`, `move_elision` and `rc_inline_glue`.

**S1 conformance set: 13 + 18 = 31 files.**

**Excluded, with the reason:**
- generics: `python_variants`, `option_*`, `migrated/generic_results`;
- other list methods, tuples or fixed arrays: `rc_plain_appends`, `rc_append_loops`, `rc_plain_retains`, `rc_plain_aggregates`, `rc_match_scalars`;
- imports: `migrated/propagation`. It is the main `?` file, so C splits its cases into single-module copies as an S1 stretch.
- a capability (`Filesystem`): `error_traces`.

**`Option`/`Result` and `?` are therefore covered in S1 by:**
- the `option_handle` and `result_propagate` rows;
- the fuzz (§10);
- `rc_tree_drains`;
- the split `propagation` cases.

`conformance.py --why` lists each excluded file's blocking feature.

**Rows:**
- The S1 rows above run as split single-row programs, like `test/core/compute_s0.my`, because the shared setup of `compute`/`collections` uses bytes, function values and dicts.
- Each row is measured against Zig ReleaseSafe (L1) with checksums identical to the old core.

## 10. Differential fuzz in S1

`fuzz.py` gains:
- records with list fields;
- unions in lists with `match`;
- `?` chains;
- `mut` list and record helpers;
- aliasing (`b = a`, then writes to either).

Each must match the old core at debug, release and verify. The verify build also asserts `is_unique` claims: form 1 sites check `count == 1` and trap `R_CORE_FACT`.

## 11. N6: `with arena()` in the new core

**Counts (2026-10-05), correcting the plan's "the Lox and EDA code use it":**

| Corpus | `.my` lines | Arena blocks | What they are |
|---|---:|---:|---|
| `tests/lang` | 25,326 | 156 in 76 files | All test the feature, or RC/GC rules inside an arena |
| other `tests/` | — | 6 | same |
| `examples/` | 1,909 | 1 | one phase with `scratch.escape(result)` |
| `bench/` | 1,921 | 5 | `*_arena` variants (binary_trees, knucleotide), `alloc_churn_arena` |
| `benchmarks/runtime` | 844 | 0 | — |
| Lox port (`bench/lox-mylang`, and every Lox branch under a Lox path) | 5,094 | **0** | — |
| EDA (`/home/epentland/ai/canopy/eda`) | **0 `.my` files** | 0 | the tree is Zig |

**Option A: keep it as a region allocator under the one count.** Costs in the new core:
- a second allocator (bump chunks per depth, reuse cache) in `core_rt.c`;
- an `arena` bit and region depth in every header, and every `retain`/`release` testing it (arena objects are uncounted);
- the store barrier `R_ARENA_ESCAPE` on every managed store;
- `escape()` as a deep copy;
- `region.enter`/`exit` handling on every early exit, `?`, break and trap;
- a facts rule that values die at block exit.

Estimate: about 1.5k lines of runtime plus IR, and a per-retain/release branch on all code, not just arena code. Under one-count RC the benefit is bulk free of a phase's temporaries, which last-use release already gives with near-zero leaks.

**Option B: retire it.**
- A `mylang fix` rewrite: `with arena() [as n]:` becomes the block's body (dedented), and `n.escape(v)` becomes `v`.
- `E_ARENA_*` diagnostics are deleted and `docs/arenas.md` is removed.
- Cost: the migration (162 test blocks, 1 example, 5 bench blocks; about 70 test files keep their non-arena tests, and about 5 arena-only files are deleted) plus a deprecation release.
- The `*_arena` bench variants become duplicates of their plain versions.

**Recommendation: B.** No application uses arenas. Under one-count RC, last-use release frees a phase's temporaries at the same points. Keeping A taxes every RC operation in all code. The user decides.

**Interim rule (holds under A or B):** the new core lowers `with arena() [as n]:` as a plain block and `n.escape(v)` as `v`. RC frees at last use. The checker still enforces `E_ARENA_ESCAPE`, so no program the old core accepts behaves differently. Arena-feature conformance tests are excluded from the S1 set:
- `arena_managed`, `arena_scopes`, `arena_class_escape`, `arena_regions`, `rc_arena_values`;
- the arena-only tests inside other files, by name filter `*arena*` in `conformance.py`.

## 12. Lanes

**Step 0, IR first (owner: this lane, Opus; ~2 days).**
- **Owns:** `ir.zig`, `print.zig` and the op stubs in `emit_llvm.zig`.
- **Adds:** compound types `record`, `union` (generalizing `option`) and `box`; every §2 op; `retain`/`release`/`is_unique`; the TBAA metadata scaffold; a verifier.
- **Exit:** test-core green; a hand-built-IR test for each new op emits valid LLVM.

After step 0, `ir.zig` is frozen. Changes to it go through the step-0 owner.

| Lane | Model | Owns (disjoint) | Depends on | Exit check | Estimate |
|---|---|---|---|---|---|
| **V Values** | Sonnet | `build.zig` (records, unions, `?`, `list_set`/`pop`, `mut` call sites), `emit_llvm.zig` record/union/list emission (owner from step 0 on), `facts.zig` field/element rules, `vector.zig` (if touched), `test/core` row programs | step 0 | `record_*`, `option_handle`, `result_propagate`, `tagged_stack`, `list_*` rows build, match the old core and reach Zig ReleaseSafe; fuzz clean | ~6–8 days |
| **O Ownership + runtime** | Opus | `own.zig`, `runtime/core_rt.c` (RC, free, copy, error trace, PC table), `driver.zig`, `target.zig`; `emit_llvm.zig` gets only RC/trace emission via one hook function V calls | step 0; V's `mut` ABI by day 3 | `mutate_*`, `alloc_*` rows correct and at gate; `rc_*`/`mut_*` conformance files pass; verify asserts uniqueness; no leaks under an `MYL_CORE_LEAKCHECK` counter at exit | ~7–9 days |
| **C Conformance** | Sonnet | `main.zig` `test` command, `src/core/test_runner*.zig`, `experiments/new-core-s1-*/conformance.py`, fuzz generators, the test-core list | step 0 (runner starts on S0 vocabulary at once) | runner matches the old core on the 13 clean files; the 38-file list wired into test-core; fuzz extended (§10) | ~4–5 days |

**Order:**
1. Step 0.
2. V, O and C start in parallel.
3. O needs V's `mut` lowering (call-site slots) before its `mut` work. V needs O's `retain`/`release` placement before managed-field records can pass conformance.

Integration happens on this branch, with a test-core plus conformance run per merge. Records of scalars and unions land first (V alone), then managed fields (V+O).

## 13. Review decisions (2026-10-05, integrator)

The user approved, 2026-10-05:
- N6 = **Option B, retire arenas.**
  - In S1 only the §11 interim rule applies.
  - Removing arenas from the old core, the `mylang fix` rewrite and the doc and diagnostic deletion are a later lane outside S1. Codex owns the old core now.
- S1 conformance is graded per test function (§9 set plus the 13 clean files). Arena tests are excluded.

Changes to this note, binding on the lanes:

**R-1. Trap traces: spike before committing to §4's inline-asm labels.**
- *Owner:* lane O.
- *Candidate 1:* inline-asm labels after calls.
- *Candidate 2:* `-gline-tables-only` plus a small `.debug_line` reader in `core_rt.c`, with `_Unwind_Backtrace` in both.
- *Requirements:*
  - labels must stay unique under inlining, unrolling and tail duplication (local numeric labels or `%=`);
  - neither candidate may change S0 kernel or S1 row cycles by more than 1%;
  - frames must be correct at -O3.
- Choose by measurement and record the choice here.

**R-2. Retain and release pairs: own.zig must not emit cancelling pairs.**
- LLVM cannot fold `retain; …; release` on its own. To prove the release does not free, it must know that the count is ≥ 1, the same kind of premise that failed for the bounds check in checkpoint A.
- Avoid the pairs at the source, Perceus-style: borrow inference plus last-use moves, and a peephole in own.zig that drops `retain x … release x` with no consuming use or call in between.
- Also put `!range [1, 0)` (1..SAT) on count loads, so LLVM can do what it can.
- Every row report counts the retain and release operations left in hot loops after -O3. The target is 0 where ownership is static: `mutate_unique`, `list_append`, `alloc_short`, `record_update`.

**R-3. No generics or imports in S1.**
- Generics stay out of S1, and so do imports: imports are S4.
- Split copies of the `migrated/propagation` cases go in `test/core/`. `tests/lang/` is never edited by the new-core lanes.

**R-4. Lane order and ownership.**
- **Start in parallel now:** step 0 (Opus) and C (Sonnet). The C runner starts on the S0 vocabulary.
- **After step 0 is merged:** V (Sonnet) and O (Opus) start.
- **Branches and worktrees:** each lane has its own branch and worktree, cut from the S1 branch. The integrator merges each into `claude/new-core-s1-20261005` after test-core, the conformance list, fuzz and review.
- **Freeze:** `ir.zig` is frozen after step 0. Any later change to it goes through the integrator.
- **Shared test lists** (`src/core/root_test.zig`, the test-core list in `build.zig`): lanes only append, and the integrator resolves conflicts.

**R-5. Stop conditions for every lane.** Stop and report if any of these happens:
- a rebuild after an edit takes over 10 s;
- test-core takes over 5 min;
- a fuzz or conformance mismatch is not explained;
- a change to language behaviour is needed. Park it for the user.

**R-6. Old-core bugs found by a lane are reported, not fixed.**
