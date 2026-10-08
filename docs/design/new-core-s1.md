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

### 2.1 As built in step 0 (2026-10-05; `ir.zig` is frozen from here)

**Types.** `ir.Compound` is `list(T)`, `record([]Type)`, `union([]Type)` and `box(T)`; `option` is gone.
- A union case without a payload is `.void`. `Module.option(payload)` interns `union{void, payload}` (None is tag 0). `union_tag` is `u32`.
- `Module.intern` copies a record's or union's type list and compares it by contents.
- Layout helpers on `Module`: `size`, `alignment`, `words`, `fieldOffset`, `unionLayout`, `passedInMemory`, `pathTarget`, `managed`, `isBlock`, `kind`, `valid`.
- A record has C layout: fields at natural alignment, size rounded to the record's alignment. Nested records are inline.

**Union forms (`UnionLayout`).** The design's two forms became three:

| form | when | registers | memory |
|---|---|---|---|
| `niche` | two cases, one without a payload and one a `str`/list/box | `ptr`, null for the empty case | the pointer (8 bytes) |
| `scalar` | every payload case has the same non-aggregate type `T` | `{i8, T}` (`Option[int]` and `Option[bool]` as in S0) | tag word, then `T` at 8 |
| `words` | anything else | `{i8, [N x i64]}`, the payload's memory image | tag word, then `N` words |

The emitter reads and writes a `words` payload through an entry-block stack slot, which SROA removes.

**Operands that differ from the table above.**
- `err_trace`: `data` is the `TraceMode` (`origin` 0, `append` 1). The site is the instruction's `span`; `a` is unused. The emitter adds a site-table entry of kind `trace` (7) and calls `myl_core_err_trace(i32 site, i32 mode)`.
- `list_set`: `data` packs a one-element `extra` list holding the value.
- `list_get_field`: `data` is an `ir.FieldPath`: up to 5 steps of 12 bits each, plus the length.
  - On a record, a step is a field index.
  - On a union, step 0 reads the tag (`u32`) and step `k + 1` reads case `k`'s payload.
  - A box cannot be crossed; deeper reads use `record_get`.
- `retain`/`release` take any managed type. The emitter counts every block the value holds: each managed record field; a niche union when it is not null; a union's payload under its tag, so an integer in a payload word is never counted.
- `is_unique` takes only a block pointer (`str`, list or box).

**Ownership semantics, fixed for O.**
- `list_set` consumes the list and the value, and releases the element it replaces (load old, store new, release old).
- `list_pop` does not release the popped element: the builder's `list_get` before it takes the list's owner.
- `list_push` consumes the value.
- `own.copyShared` treats `list_set` and `list_pop` like `list_push`: it puts a `list_copy` before them unless the operand is provably unique.

**Records in the emitter.**
- Every record is an LLVM struct value in SSA, whatever its size.
- At calls between internal functions, a record or union over 4 words goes in by `ptr noalias readonly` (the callee loads it at entry) and comes back through `sret([S x i8])`.
- A list element, box payload or slot is loaded and stored field by field; no aggregate load or store and no `memcpy` are emitted.
- *Not built:* memory-backed SSA values for large records, and the WP-10b fusion of `record_make`/`union_make` with their consumer. Both are V's.

**Counting (§6, R-2).**
- `retain`, `release` and `is_unique` load the `u32` count with `!tbaa` `myl.count` and `!range [1, 0)`.
- A saturated count is branched around and never stored, because string constants live in read-only memory. `retain` is therefore a compare-and-branch, not a branchless `uadd.sat`.
- `release` calls the `cold` `myl_core_free(ptr)` at 0.
- TBAA scaffold: `!1` is the root, `!3` the count, `!5` the header (len/cap), `!7` the data. S0's list length loads, element loads and push stores now carry `!5`/`!7`. `!range` nodes for facts start at `!9`.

**Runtime.**
- `myl_core_box_new(size)` creates a block of kind 2 with the value at 32.
- `myl_core_free` frees the block only.
- `myl_core_err_trace` is a stub.
- Trap kind 6 (`list_empty`) prints `R_LIST_BOUNDS (length N)` with a `pop` record, as the old core's `myl_qbe_fail_pop_bounds` does. `list_set` and `list_get_field` use the `index` detail of `list_get`.

**Verifier** (`verify_ir.zig`). It checks:
- that reachable blocks are terminated, with phis first;
- phi arity against the predecessors;
- predecessor lists against the terminators;
- every operation's operand and result types;
- SSA dominance;
- `verifyPlan`: values a vector plan reads before its loop must dominate the preheader.

It runs in debug builds of `mylang-core`, after construction and after the release passes, and on every module `test_support` builds, optimizes or runs.

**Open for V and O.**
- `myl_core_list_copy` copies elements with `memcpy`, so a copied list of managed elements must retain them (O).
- `myl_core_free` must release children by kind and element descriptor (O).
- `list_reserve`'s grow frees the old block whatever its count (the uniqueness rule).
- `print` of a record, union or box is `UnsupportedInstruction` (V).

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

### 6.1 As built in checkpoint O-1 (lane O, 2026-10-05)

**Where it runs.** `own.zig` runs per function in release builds after the facts (and
the trip-count guards), before the vector plans, and grows the fact tables over what it
adds (no facts; new blocks reachable); debug builds run it after construction
(`pipeline.finish`). `build.zig` no longer calls B1's `copyShared`.

**Phase A, copy on write.** Per update (`list_push`, `list_set`, `list_pop`) of list `a`:
- form 3 (`list_copy` first, no test) when `a` is borrowed **or still live after the
  update** (an owned value used later is shared by definition, so a retain plus a test
  would only copy anyway);
- form 1 when `a` is owned, dead after, and statically unique: from `list_new`,
  `list_copy`, an update, or phis of those, with no call argument and no retained
  consuming use that can still reach the update (liveness plus a CFG walk that stops at
  the value's definition, so a call after a loop does not taint the loop's appends);
- form 2 otherwise: `is_unique` branch, `list_copy` + `release` arm, a phi into the update.
- Verify builds put `is_unique` + a block ending in `unreachable` with `data = 1` before
  every form-1 update; the emitter makes that block an `R_CORE_FACT` trap
  (`count == 1 before an in-place update`).
- The `list_get` before a `list_pop` of the same list owns the popped element (§2.1); a
  pop without one gets a read of the dropped slot after it, released at once.
- A `record_set` of a managed field reads the old field first (owned: the consumed
  record's reference goes with it) and releases it after.

**Phase B, counting.** Per-value block liveness, where a borrowed part's uses (`list_get`,
`list_get_field`, `record_get`, `union_payload`, `box_get` of a managed value) count as
borrow uses of its nearest owned ancestor:
- a consuming use moves the value when nothing later needs it, otherwise a `retain` goes
  first; a phi operand is consumed on its edge;
- an owned value dies after its last use (before it when that is the `ret`), or on the
  edge where it stops being live: at the top of a one-predecessor successor, else at the
  end of a one-successor predecessor, else in a split block; no release goes on a path
  into a block ending in `unreachable`;
- a borrowed value a consuming use takes is retained first; immortal values (string
  constants, `undef`) are never counted;
- **promotion** (not in the §6 sketch): a borrowed part whose owned ancestor is consumed
  while the part is still used is retained right after its read and counted from there,
  so an element read before an in-place update of its list does not force a copy of the
  list; without it the ancestor's liveness alone would keep it valid;
- phis no live instruction reads are ignored (their operands are not consumed).
- **R-2:** retains arise only at non-last consuming uses, borrowed escapes and
  promotions, so no cancelling pair is emitted by construction; `elidePairs` drops any
  `retain x … release x` in one block with only pure reads between. Every S0 kernel's
  hot loops hold no count operation (0 retains in the whole programs; the 1–2 releases
  drop `main`'s lists after the loops; per-iteration instruction counts are equal to the
  pre-O build's).

**Runtime.** `reserved` holds a pointer to an `i32` element layout the emitter writes
once per managed element type (`@myl.layout.N`: size, block-pointer offsets, each guarded
by a chain of union-tag tests), stored by `list_new` and `box_make`; `list_copy` and
growth copy it, `list_copy` retains every child, and `myl_core_free` releases children
iteratively through a pending chain linked in the dying blocks' `cap` words. The C entry
releases `args` after `main` and an `Err` payload after reporting it. `MYL_CORE_LEAKCHECK=1`
reports blocks still allocated when `main` returns. `myl_core_err_trace` keeps the origin
and a 32-entry ring; the site's operation is the action text. Only `Err(...) created`
and `? propagated` can be told apart today: the verifier holds `err_trace`'s `data` to a
bare `TraceMode`, so `returned`, `? converted to Union.case` and `Err produced by the
runtime` need an IR change (§13 R-1 note for the integrator).

### 6.1.1 Allocator and the buildable rows (checkpoint O-2a, 2026-10-05)

**Profile first.** `perf record` on CPU 10: alloc_short spent 26% in `myl_core_free`,
13% in `block_new`, 12% in glibc `free` and most of the rest in `aligned_alloc`, plus a
call per push to `myl_core_list_reserve`; alloc_retained was dominated by glibc.

**Built** (`core_rt.c` "allocation", `emit_llvm.zig` `runtime_fast_paths`):
- size classes per 32 bytes up to 1 KiB (header included), each a free list, carved from
  64 KiB chunks never returned; the class sits in `kind`'s high byte; a list's `cap` is
  all its block holds, so a small list grows within its class;
- larger blocks `aligned_alloc(32)`; a large list grows with `realloc` (re-aligned if it
  moved off 32 bytes: 16-byte `malloc` alignment cost integer_math 4% at 4096);
- `myl_core_list_new`, `myl_core_list_reserve` and `myl_core_free` are `alwaysinline`
  IR in every module (pop/push on `myl_core_free_lists`, the `len < cap` test); the C
  slow paths are `_slow`, `list_grow`, `free_block` (children, large blocks);
- the leak count needs no fast-path counting: carved plus large blocks, less large frees
  and free-list entries at exit (`live_count`);
- a release of a list nothing can share (§6.1's form-1 rule at its death; a call that
  received it shares it) carries `data = 1` and frees without the count test (verify
  builds assert `count == 1`).

**Rows the new core builds without V** (`measure_rows.py`, CPU 10, 9 rounds, cycles per
element at 4096 / 64; count updates and allocator calls in the innermost loops from
`lane-o/count_rc_in_loops.py` over the -O3 assembly):

| row | before O-2a | O-2a | Zig ReleaseSafe | ratio | count updates in innermost loops |
|---|---:|---:|---:|---:|---:|
| alloc_short | 107 / 108 | 18.4 / 19.2 | 21.8 / 22.2 | 0.84 / 0.86 | 0 (none in the whole program) |
| alloc_retained | 247 / 183 | 34.7 / 31.9 | 80.8 / 78.9 | 0.43 / 0.40 | 0 |
| list_append | 8.7 / 10.8 | 7.1 / 11.1 | 12.3 / 16.8 | 0.57 / 0.66 | 0 (growth calls only) |
| list_filter | 10.3 / 14.2 | 8.1 / 10.4 | 10.6 / 13.9 | 0.77 / 0.74 | 0 (growth calls only) |
| list_scan | 4.0 / 4.1 | 4.0 / 4.0 | 4.6 / 4.7 | 0.87 / 0.87 | 0 |
| option_handle | 2.0 / 2.4 | 2.0 / 2.4 | 6.5 / 7.4 | 0.30 / 0.33 | 0 |

The count updates left anywhere are once per batch (a list passed to `fold`, released
after the call) or once per run. S0 kernels against O-1: the same within 1% except
binary_search 4096, +8–10% (30.3 → 33.0): the same instructions per iteration (458,883),
with branch misses 150–160k → 250–290k per run from the hot loop's moved address (same
64-byte alignment; the inline allocator paths make `main` longer), the layout
sensitivity S0 already recorded for this kernel.

### 6.2 `err_trace` modes (checkpoint O-2a; for lane V's `ir.TraceMode` and verifier)

`data` is the mode, in this order (`TraceMode` gains three members; `a` is `none` except
for `converted`). The emitter (`errTrace`) writes the action text into the site table and
calls `myl_core_err_trace(site, restart)`; restart modes reset the ring.

| `data` | name | emitted | runtime | printed action |
|---:|---|---|---|---|
| 0 | `origin` | where `Err(...)` is built (ERROR-TRACE-1) | restart: origin = site, 0 appends | `Err(...) created` |
| 1 | `append` | on a `?` error arm that passes the error on unchanged | append | `? propagated` |
| 2 | `runtime` | after a runtime or capability call that answers `Err` (S2+) | restart | `Err produced by the runtime` |
| 3 | `converted` | on a `?` error arm that wraps the error into a case of the caller's error union; `a` = a `str_const` holding `Union.case` (the old core's spelling) | append | `? converted to Union.case` |
| 4 | `returned` | on the path where `return e` returns an `Err` the statement did not build (a variable, a call, a conditional), after testing the tag; not for `return Err(...)` (already the origin) nor `return Ok(...)` | append; folded into the line before when that site is in the same function on the same line | `returned` |

Every mode's site is the instruction's span; function names print module-qualified and
paths as the old core shows them (§13 R-1). Recorders carry `"call-inline-cost"="0"`.
Until the verifier admits modes 2–4 and `a` on mode 3, `trace_test.zig` runs them unverified.

### 6.3 Lists on the stack (checkpoint O-2c, 2026-10-05)

`promote.zig`, run by `own.zig` first in release builds (it needs the facts). A list
qualifies when it is built in the function from `list_new` by a straight chain of pushes
or by a counted fill loop the facts recognized (`listFacts`: the header phi's length is the
loop bound), its elements hold no blocks, every other use only reads it (`list_len`,
`list_get`, `list_get_field`) and no read can run after a push of the version it reads
(a CFG walk that stops at the version's definition), and its capacity (the push count, or
`hi` of the bound's interval) is at most 4 KiB of elements. Calls, returns, stores, other
phis and other updates make it escape (no callee analysis yet: any call escapes).
- *Marks:* `list_new.data = capacity + 1`, each filling push `data = 1`; the web's values
  are never counted (no retain, release or copy-on-write test).
- *Emission:* an entry-block `alloca [32 + capacity × stride] align 32` with the block
  header (count 1, size class 0xff, `cap` = capacity) written where the `list_new` runs,
  and pushes without the growth test. No web value reaches a phi, so an instance is dead
  before its `list_new` runs again in an enclosing loop.
- *Verify builds* assert `len < capacity` before each such push (`R_CORE_FACT`); the
  `--sabotage-facts` build of `test/core/rc_stack.my` (where `seed % 5` bounds a fill loop)
  is caught.
- *Results:* alloc_short 18.4 → 4.86 / 5.05 cycles per element (Rust 5.02 / 5.39, Zig
  Safe 21.8 / 22.2): LLVM keeps both lists in registers. Other rows and every S0 kernel
  binary are unchanged (the kernels' code is identical to the S1 head's). Promotions
  (`mylang-core coverage` now prints `stack=N`): test/core 7 lists in 4 of 71 functions,
  tests/lang 174 in 99 of 902, bench/parity 1 in 41, examples and benchmarks/runtime 0.
  tests/lang release conformance is unchanged (218 matching, 31 mismatching, all builder).

### 6.4 Shared blocks across loops and `mut` ownership (checkpoint O-2b, 2026-10-05)

**The uniqueness bug** (`rc_fresh_loop_roots::test_prior_enclosing_iteration_publication_refuses_freshness`).
Form 1's "nothing shares it before the update" used a CFG walk that stopped where the
shared *value* was defined again. A block outlives its SSA value through phis: `items`
retained into `saved` at the end of one outer iteration re-enters the inner loop as the
same block through the outer and inner header phis, and was then pushed in place (4
where the old core prints 3). The walk (`carries`) now tracks which members of the
update's phi web hold the block: a phi takes it on an edge whose operand holds it, a
member defined again holds a new one, and the update is shared when it is reached with
its operand holding the block. It also used to stop at the first path reaching the
update (fuzz: `rc_alias_paths.my`). Two related fixes: a removed trivial phi (`copy`)
among a block's phis no longer ends the phi scan, and a value a call both takes (`mut`)
and borrows gets a second owner (`rc_pin_elide`), as does a part borrowed by the call that
takes its owner (`mut_record_call_window`).

**`mut` ownership on the by-value ABI (§14).** `ir.Signature.owned` (bit per parameter, set
by the builder for `mut` parameters; an `ir.zig` addition) makes the parameter owned in the
callee (defined on entry; updated after a count test, form 2) and its argument a consuming
use in the caller: moved when the caller's value is dead until the write-back (no retain),
retained when it is still read (`b = a; f(mut a)`, so the callee sees count 2 and copies).
`takeFields` keeps record-shaped `mut` traffic copy-free:
- `g = r.f; …; r' = record_set(r, f, v)` in one block, `g` the only read of `f` there and
  nothing but other-field reads of `r` reachable after `g`: `g` owns the field and the set
  drops nothing (`bag.items.append(x)` in a `mut Bag` callee or its inlined copy);
- an owned record read only field by field in its block, each block-holding field once:
  the reads own the fields and the record is never counted (the write-back of a call with
  a result, or its inlined `record_make`).
A loop of 400,000 `mut` appends (list, and a record's list field, at debug and release with
the calls inlined) runs in milliseconds; before, release copied on every call.

**Rebinding a `mut` parameter** (`mut_rebinding`, two tests) is not ownership: V's
write-back returns the rebound value, so `items = other` inside the callee reaches the
caller's `items`; the old core leaves the caller's variable alone (COW-MUT-REBIND-1).

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

**R-1 decided (lane O, checkpoint O-1, 2026-10-05): DWARF line tables, not call labels.**
- *Built:* every function gets `uwtable` and a `DISubprogram` (the C entry too, named
  `myl.entry`, so inlining `main` into it keeps the locations; it is never printed); every
  call and every trap call gets `!dbg` with its source position; the module asks for
  DWARF 4 (`emissionKind: FullDebug` with no variables or types: `LineTablesOnly`
  emits no subprogram DIE for a function nothing was inlined into). `myl_core_trap`
  prints the site's frame, then walks the stack with glibc `backtrace` (libgcc's
  `_Unwind_Backtrace` over `.eh_frame`; nothing is linked in, unlike zig's static
  `-lunwind`, +20 KB) and maps each return address through the executable's own
  `.debug_info`/`.debug_ranges`/`.debug_line` (read from `/proc/self/exe`, ~350 lines
  of C): the subprogram and inlined-subroutine entries holding the address give one
  frame each, the innermost line from the line table, the others from `call_line`.
  `--trap-frames=posix_exit` builds without the tables, for measurement.
- *Frames:* `test/core/trap_frames.my` (a bounds trap two calls deep) prints the old
  core's frames, `leaf 6:25 / mid 11:9 / main 20:15`, at -O0 and at -O3 where LLVM has
  inlined everything into the C entry. Names are unqualified, as the first frame already
  was (the old core prints `trap_frames::leaf`).
- *Labels (candidate a) lose:* an `asm sideeffect` label after each internal call in
  section `myl_sites` (local numeric labels, so inlined, unrolled or duplicated copies
  each record their own address) names only frames whose call survived: at -O3 the
  same program printed the trapping frame alone, since the inlined calls' labels sit in
  `main` with no record of the inline chain. The asm also stays in loops LLVM inlines a
  call into and blocks optimization there: binary_search 4096 went from 30.8 to 33.7–34.2
  cycles per search (+11%).
- *Cost of the tables (S0 kernels, `measure_variants.py`, CPU 10, 7–15 interleaved
  rounds, cycles per element, `base` = the S1 head before lane O):*

  | kernel (4096 / 64) | base | RC, no tables | RC + DWARF | RC + labels |
  |---|---:|---:|---:|---:|
  | integer_math | 0.355 / 0.491 | 0.355 / 0.492 | 0.356 / 0.490 | 0.356 / 0.492 |
  | float_math | 1.566 / 1.704 | 1.567 / 1.706 | 1.566 / 1.704 | 1.565 / 1.705 |
  | call_direct | 0.298 / 0.320 | 0.300 / 0.321 | 0.299 / 0.321 | 0.300 / 0.321 |
  | branch_predictable | 0.397 / 0.496 | 0.396 / 0.497 | 0.398 / 0.498 | 0.397 / 0.497 |
  | branch_mixed | 0.393 / 0.496 | 0.394 / 0.496 | 0.394 / 0.496 | 0.393 / 0.497 |
  | binary_search | 30.37–30.47 / 17.64–17.69 | 30.81–30.93 / 17.81–17.85 | 30.79–31.20 / 17.81–17.85 | 33.65–34.18 / 17.59–17.61 |

  The DWARF build's code is the no-table build's instruction for instruction (only
  non-loaded sections grow: +552–568 bytes per kernel binary, 0.5%; labels +168–264);
  compile time is within run-to-run noise (compute_s0, fresh clang cache: debug 82–87 ms
  either way, release 202–257 ms against 217–248 ms). binary_search's +1.3–1.8% against
  `base` is layout, not work: its search and outer loops are the same instructions at
  the same 64-byte alignment, the program executes the same instructions per iteration
  (458,883 per outer iteration in both; 6k more once, for the frees at exit), and the
  difference is branch misses (128k against 144–159k per run) from moved addresses.

**Layout sensitivity of binary_search (checkpoint O-3, 2026-10-05; data, no policy landed).**
With identical code, binary_search 4096 ranged from 30.4 to 44 cycles per search across
builds whose only difference was where `main` landed (O-2a, O-2c). `lane-o/layout_shift.py`
shifts every program address by 0–960 bytes in 64-byte steps (a padding function placed
first) and builds each shift under four flag sets; megacycles for `4096 400 7`, median of 5:

| policy | most shifts | worst shifts | spread |
|---|---:|---:|---:|
| current (innermost loops aligned to 64) | 50.1–51.4 | 64.5 (+512), 56.1 (+448), 56.0 (+0) | 29% |
| + `-falign-functions=64` | 50.1–51.7 | 66.8 (+512), 56.2 (+448, +960) | 33% |
| + `-falign-loops=64` (every loop) | 50.2–52.0 | 74.2 (+0), 73.2 (+960), 65.4 (+448) | 48% |
| + `-falign-functions=4096` | 50.1–51.6 | 73.3 (+640), 59.5 (+128), 59.0 (+64) | 46% |

The slow shifts execute the same instructions and double the branch misses: the search's
data-dependent branch shares predictor state with other branches depending on address bits
above the 64-byte line, which no alignment policy controls (larger alignments only move
which shifts are slow). The lever is the code, not the layout: a branch-free search step
(`cmov` for `low`/`high`, which LLVM does not choose here) would remove the predictor from
the loop. That is facts/emission work, not a target flag; binary_search numbers should be
read as a 50–65 megacycle band (≈30–39 cycles per search) until then.

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

## 14. Lane V, checkpoint V-1: as built, and where it differs from §3–§7

**What the checked tree actually gives the builder** (corrections to §1):
- `xs[i] = v` on a list is `buffer_operation write`, not `replace` (`replace` is the fixed-array form).
- Writes through a nested place (`s.items.append(v)`, `xs[i].f = v`, `xs[i][j] = v`) are rooted in checker-hidden `<collection>` locals read from the place; the old runtime shares the list block, the new core must store the new value back.
- The checker can type the literal in `i16 + 1` as `i64`; the builder retypes it.

**Places (`build.zig`).** The builder remembers, for each hidden receiver, the place it was read from (a local plus field and element steps) and, after a write through it, rebuilds the path from the root's current value (`record_set` for a field, `list_set` for an element) and writes the root. If the root was written between rooting the receiver and using it (a `mut` call in an index), whether the write shows through depends on whether the old runtime changed the list in place or replaced it, which a value cannot tell: the operation is refused.

**`mut` ABI, by value (differs from §7).** `ir.zig` has no `ptr` type and no slot load or store, so the slot ABI would need three new operations. A `mut` parameter is passed by value and returned: a function with `mut` parameters returns a record of its result (unless `unit`) followed by each `mut` parameter's final value (the value alone when it is the only part), and the caller writes each back into the argument's place, reading the place's value after the other arguments are evaluated. Under D3 this is `inout`: nothing else can name the place during the call. For ownership the parameter is owned (the caller's variable is overwritten by the result); facts about a parameter value stay sound because the old value is dead after any in-place update. If the slot ABI is still wanted, it needs `slot_load`/`slot_store` and a `ptr` type in `ir.zig`.

**Memory-backed values (§3).** A record or union over four words is a pointer to a stack slot: a parameter is the caller's read-only pointer, `record_get` is a load at the field's offset, `record_set` copies into a fresh slot or, when the old value's other readers ran earlier in the same block, writes it where it is, and a value read out of a list, box or call result is copied into a fresh slot (never a view). A loop-carried one owns a slot filled on each incoming edge (conditional edges get a block of their own), staged through temporaries when several meet. A `record_make` or `union_make` whose only use stores it (`list_push`, `list_set`, `ret` through `sret`, `box_make`, or a field of such a construction) is written straight into the destination (WP-10b).

**Projection fusion (`fuse.zig`).** `xs[i].f` and `match xs[i]` become `list_get_field` reads (§4), before ownership.

**Facts (§5).** Record field intervals through `record_make`/`record_set`/phis; list lengths through new/push/pop/set/copy/phis and element hulls through writes and pushes; a read below the length's lower bound and a pop of a list at least one long are proven; verify asserts each. Facts about `mut` results stay empty because the result of a call has none.

**Equality, `?`, `pop`.** `==` on records, unions and lists of integers or booleans is structural (build-time expansion, loops for lists); `str`, recursive values and other lists are refused. `?` appends `err_trace` on the error arm and converts the error into the caller's union case; `converted` and `returned` trace kinds wait for `ir.TraceMode`. `pop` reads element `len - 1` (`flags.pop_read` makes a failing index the empty-list pop trap) and then `list_pop`s.

## 15. Lane V, checkpoint V-2: conformance with the old core, and what newly lowers

**Measured** (`conformance.py --set all`, 1470 tests of `tests/lang`, the old core as the oracle, debug and release, on the head with lane O's O-2b merged): 735 tests supported, 735 matching, 0 mismatching, 735 unsupported. The S1 set (31 files, 125 tests): 119 supported, 119 matching, 6 unsupported (4 writes through a receiver whose place an argument rewrote, `list[None]`, `sort`). `--verify-facts` over all of `tests/lang`: 815 passed, 0 failed. Coverage (`coverage.py`): 2248 of 3509 functions. The six value rows (`record_reads`, `record_construct`, `record_update`, `option_handle`, `result_propagate`, `tagged_stack`) run at 0.30 to 1.05 times Zig ReleaseSafe with no count update in any innermost loop.

**Wrong answers found by the comparison, and their rules.**
- *`mut` collection parameter rebound as a whole* (`items = other`): the old core detaches the name from the caller's payload (COW-MUT-REBIND-1), so only what the parameter held at the rebinding is written back. The by-value ABI wrote back the final value. The builder tracks the rebinding per path (`rebound`, `connected`); a rebinding in a loop, or on only some of the paths that join, is refused.
- *Hidden receivers.* A read through a receiver the checker captured before the arguments ran (`xs[poke(mut xs)]`) is a snapshot of the receiver (the old core's evaluation-order snapshot, VALUE-SEMANTICS-14); a write through it (`xs[f(mut xs)] = v`, `append`, `pop`, `clear`) whose place an argument rewrote is refused: the old runtime applies it to the captured payload, which may or may not still be reachable from the place (a replaced field and a cleared parent drop the write; an in-place change keeps it), and a value cannot tell them apart.
- *Narrowed `Option`* (`if x is None: return` then `x.append(v)`): the checker binds a hidden local to the payload. The place now has a `payload` step, so the write rebuilds the union and stores it into `x`; it was lost.
- *`len(text)`* counts scalars, not bytes (`myl_core_str_chars`).
- *Verify builds* called an unsigned operand above half its range negative in the `proven` division assertion (21 false `R_CORE_FACT`).
- *Fusion* resolved a call's callee index as a value (`operand_snapshots` panicked the compiler).

**Newly lowered.** The interim arena rule (§11): `with arena()` is a plain block and `escape(v)` is `v`. `assert` and the contract clauses: a branch to an `unreachable` whose `data` carries `flags.assertion_trap`, the clause kind and the message's index in `Module.strings`; `myl_core_assert_fail` prints the old core's first line, frames and `MYLANG-TRAP` record (a build-time constant condition leaves no branch). Runtime helpers appended to `core_rt.c`: `myl_core_str_eq`, `myl_core_str_chars`, `myl_core_str_concat`, `myl_core_str_join`, `myl_core_str_from_{i64,u64,bool}`, `myl_core_assert_fail`; the builder declares them as `extern_c` functions in the module on first use (`ModuleBuilder.runtimeFunction`), so `ir.zig` did not change. With them: `str ==`/`!=`, `a + b`, `separator.join(parts)`, `str(x)` of an integer, a bool or `None`, and f-strings. Also: `xs.clear()` (the place becomes an empty list), `xs.copy()` (the value), `len` of a string that is not a local, keyword calls (`call.evaluation`), `while True:` (no exit edge), and domains over integers or booleans (their wire type).

**Still refused, by choice.** A write to a list while a loop iterates it (D1's live iteration: the old core's answer depends on whether another name shares the payload, which a value cannot tell; a rebinding of the name is allowed), float text, string indexing and slices, `sort`, `extend`, `in`, ordering of strings, equality of recursive values, `list[None]`; dicts, sets, bytes, fixed arrays and function values (S2).

### 15.1 Checkpoint V-3: facts for the loop-carried kernels, sort, `list[None]`, and what stays refused

**Facts that were missing** (`facts.zig`, `build.zig`):
- *Conditions.* `if size < 2 or n < 1: return` built a boolean joined by a phi, and the fact pass's edge refinement (a comparison on a single-predecessor edge narrows its operands in every block it dominates) never saw `size >= 2` afterwards. `and`, `or` and `not` in an `if`, a loop or an `assert` are now control flow (`branchOn`); a plain condition is still evaluated first, so the numbering of a loop's blocks does not move.
- *Loop-carried lists.* A list phi now joins its settled operands' element hulls and lengths and their common `length` (the counted fill loop's bound). The back edge is skipped until it is settled, so `values[i] = (values[i] + b + 1) % 1000003` in a loop keeps the hull `[0, 1000002]` of the entry's elements and the written values; hulls that keep moving widen to unknown after eight changes, counted apart from the length.
- *Index remainders.* `x % n` of a list whose `length` is `n` (`n >= 1`) is below its length, so the bounds check is proven.

**Mechanism of the two slow value rows** (perf annotate, CPU 10). Both are one loop-carried chain of integer remainders. `index % size` was a signed `idivq` with a sign fix-up (xor, sar, and, add) because `size >= 2` was unknown, and `checksum % 1000000007` a signed multiply-high sequence with its fix-up because the list elements had no hull; each fix-up sits on the dependency chain. Now the divisions are unsigned (`divl` through the 32-bit bypass, unsigned magic multiplication with no fix-up) and the index normalisation and bounds checks are gone. mutate_unique 18.4 -> 14.6 cycles per iteration (Zig ReleaseSafe 17.0, Rust 13.2), record_reads 25.0 -> 17.4 (Zig 24.0, Rust 17.4); every other row is unchanged and all 14 are at or below Zig ReleaseSafe with identical checksums.

**Lowered now.** `sort` and `sorted` of integers, floats and text through `myl_core_list_sort` (a sorted copy that replaces the list; a stable merge sort, NaN last, signed zeros tied; `ModuleBuilder.runtimeFunction` declares one extern per symbol and signature), and `list[None]` (a list of `bool` that only holds `false`).

**Still refused: a write through a receiver whose place an argument rewrote (4 tests of the S1 set).** The old core's answer depends on *how* the callee changed the place, which values do not carry. Writes land on the current place when the callee changed what is inside it (`items[selected(mut items)] = i`, where the callee's own copy-on-write replaces the payload; `points[save(mut points, ...)].x = 13`), and on the payload captured before the call, now unreachable, when the callee replaced the node the receiver names or one above it (`m.stack[grow(mut m)] = v` after `m.stack = [...]`; `rows[0].append(clear(mut rows))`). An implementation needs a static classification of the callee's writes to the `mut` argument (replace of a prefix of the receiver's path against a write inside it, transitively through its own `mut` calls) at the call, which the single pass over callees in call order does not have; a wrong guess is a wrong answer, so the builder refuses.

**Still refused: a write to a list a loop iterates (D1).** The rule (the loop sees in-place writes to the iterated list, while a write that copy-on-write copies leaves the loop on the payload it started with) is a statement about block identity: the iteration reads the block it started on, and an update either mutates that block (unique) or leaves it (shared). To lower it exactly the loop's alias must be a non-owning view of the root's block, so that it neither counts as a second owner (`own.zig` would copy every update) nor is assumed immutable (`facts.zig` would state hulls and lengths that an in-place write breaks); that is a new kind of value in the ownership pass (lane O) plus an `iteration_check` emission, and a version of the loop per sharing state if the body can take a snapshot of the list. Lowering the loop as live reads of the root is right for the unique case and wrong for the shared one (`test_named_snapshot_remains_independent_of_iteration_writes`: the loop must go on over the old payload). A rebinding of the name inside the loop is supported.

**binary_search, noise.** The search loop's IR is identical to V-2's, and the other S0 kernels are within 0.5% (integer_math 0.355 / 0.491 cycles per element). The 4096-element search runs 30.9 -> 32.6 cycles per search in the paired run, +6% in `perf stat` (instructions -1%, branch misses 130k -> 230k) from the code placement of the one data-dependent branch in `main`; across runs the same binary moves between 30.8 and 38.3 on this loaded host. A branch-free form of that diamond is the fix (S2 if-conversion), not a placement policy.
