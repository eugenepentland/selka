# Records that hold borrows (plan, 8 November 2026)

**Status:** asked for by the user on 8 November, after lane PA's F-PA-1: a record cannot hold a borrow of a plain read-only
parameter, so the port copied five inputs into a record on every call (20% of `schematic-labstation`). This plan answers "make it
so a record can hold a borrow". Three decisions are the user's (section 8). Nothing is built.

It continues `zero-copy-ownership-plan-2026-11-07.md`. That plan's part 2 (borrowed collections) waited on the census. Lane Z2A
re-counted it on 8 November (`experiments/copy-census-2a-20261108/REPORT.md`): part 2a removes 478 of 2,031 copy sites. Stages 2
to 4 below are that part 2, and stage 1 is new.

## 1. What a record can hold today

One shape per program, checked by pin `g3-s1b4-fb8d57f7` (main `853c40460`). The programs are in
`experiments/record-borrows-20261108/probes/`.

| Probe | Shape | Today |
| --- | --- | --- |
| p05 | a field of a plain parameter: `Spot(net=inner.a)` | accepted, no copy (1A) |
| p13 | a field of a loop variable | accepted (1A) |
| p04 | a bare plain **record** parameter: `Outer(inner=inner)` | accepted (1A: a record has no view form) |
| p10 | a borrowed record inside another record of borrows and numbers | accepted (1A) |
| p09 | a borrowed record returned under `from`: `-> Spot from inner` | accepted (1A) |
| — | `Some(p)` of a read-only record parameter, a recursive walk's parent | accepted (O4, frame box, A18) |
| **p01** | a bare plain **bytes** parameter: `Spot(net=net)` | `E_SINGLE_OWNER_BORROW` (F-PA-1) |
| **p02** | a bare plain **list** parameter | `E_SINGLE_OWNER_BORROW` |
| **p03** | a bare plain **dict** parameter | `E_SINGLE_OWNER_BORROW` |
| **p14** | p01 returned under `from net` | `E_BORROW_MIXED`, `E_SINGLE_OWNER_BORROW` |
| **p11** | `Some(place)`: `Opt(ref=Some(owner.a))` | `E_OWN_MARKER` |
| **p06** | a slice: `Spot(net=owner.a[1:3])` | `E_SLICE_ESCAPES` |
| **p07** | **mixed**: a fresh field beside a borrowed one, `Item(message=f"...", ref=owner.a)` | `E_OWN_MARKER` |
| **p08** | a borrowed record appended to a local list | `E_OWN_MARKER` |
| **p12** | a borrowed record appended to a `mut` out-parameter | `E_SINGLE_OWNER_BORROW` |

So a record can already hold a borrow when the source is a place in memory: a field, an element, an owner, a record parameter.
It cannot when:
- the source is a plain parameter of text, bytes, list or dict type (p01-p03, p14);
- the borrow sits inside an option (p11);
- the source is a slice (p06);
- the record mixes fresh and borrowed fields (p07);
- the record goes into a collection (p08) or into caller storage (p12).

## 2. Why: blocks and views

Every managed value is a pointer to a **block**: a 32-byte header (kind, length, capacity) followed by the data
(`src/core/runtime/core_rt.c`, `myl_block`). A record field of type `bytes` holds such a pointer, so a record built from borrows
(1A) holds the source's own block pointers and never drops them.

A plain text, bytes or list parameter does not arrive as a block. It arrives as a **view**, a data pointer and a length
(`str_view`, `bytes_view`, `list_view` in `dump-ir`), because the caller may pass a slice. A view has no block to point to, so a
field cannot hold one without copying. The IR verifier says it outright: "a view has no aggregate or function storage
representation". This, not the checker, is what F-PA-1 runs into.

What the callee does have:
- **Text and list parameters already carry an owner** (C9): a trailing block pointer, which is the argument's own block when the
  argument was a whole value, or a static sentinel when it was a slice. `fn g(str_view, bytes_view, list_view[str], str,
  list[str])` is what `g(s: str, b: bytes, n: str[])` lowers to. Bytes parameters carry no owner.
- **A dict or set parameter is the caller's block** (`fn g(dict[bytes, i64], ...)`), with no view form. Refusing p03 is only the
  checker's conservative rule; nothing in the representation stops it.
- **Static storage:** a block whose kind has `MYL_STATIC_STORAGE` is never destroyed. O4's frame box and the text literals use it.

## 3. Two designs

### A. Inferred: one record type, borrowed or owned per value (recommended)

Keep 1A's model: no syntax, and the checker decides at each constructor whether the value is borrowed. Lift the limits in section 1
one by one:

```mylang
record IslandInputs:
    seed_ref: bytes
    hub_count: dict[bytes, int]


func anchor(seed_ref: bytes, hub_count: dict[bytes, int]) -> int:
    return consider(IslandInputs(seed_ref=seed_ref, hub_count=hub_count))   # stage 1: no copy


record Finding:
    message: str
    ref: bytes


func findings(design: Design) -> Finding[] from design:
    mut out: Finding[] = []
    for inst in design.instances:
        if len(inst.value) == 0:
            append(mut out, Finding(message=f"{inst.ref} has no value", ref=inst.ref))   # stages 2 and 3: no copy of ref
    return out
```

**Pros**
- One type serves both uses. `Finding` is owned where it is stored long-term and borrowed where it is built from the design, so
  there is no `Finding`/`FindingView` split.
- Nothing to declare or learn, and nothing accepted today is refused, so there is no migration.
- It builds on what shipped: 1A, O4 and the trust point A18.

**Cons**
- The rules are a list of positions where a borrowed value may stand. `docs/ownership-rules.md` B9 is already one dense paragraph.
- A slice still copies (part 3's spans cover the long-lived cases).
- A borrowed value cannot outlive its function except under `from`.
- A record that works as an argument can be refused when it is appended to a long-lived list. The refusal names the field and
  carries the `copy(...)` repair, as today.

### B. Declared view fields

A field is declared a borrow, with its own layout (a data pointer and a length), and any record with such a field is a borrowed
type:

```mylang
record Finding:
    message: str
    ref: view bytes          # placeholder syntax
```

**Pros**
- A Zig `[]const u8` field maps one to one.
- A view field holds anything: a parameter, a slice, a field.
- Mixed records are natural, and a type's borrowedness shows in its declaration.
- It reaches more of the census's L class: data whose owner lives in an ancestor frame, such as `parse(source) -> Ast from source`.

**Cons**
- A second kind of record type. Its values cannot enter owned state, so a type needed both ways needs two declarations (Rust's
  `String`/`&str` split).
- New syntax, a type-system rule (borrowedness propagates to containing records, options, lists and dicts) and its migration.
- The IR verifier's "no view in an aggregate" goes away everywhere, so emission, drop, copy, equality, hashing and printing learn
  view fields.
- About twice A's cost: 48-86 lane-hours against A's 32-59.

**Why A:**
- The user chose "no syntax, inferred" for this class on 7 November, and A keeps one type per record.
- B's extra reach is mostly the L class, which part 3 (spans and keys) was planned to cover.
- If the port still shows many refusals after A's stages 1-2, B can be weighed again with that count.

## 4. Design A in stages

Each stage only turns refusals into acceptances. A refusal it does not lift keeps today's diagnostic, location and repair
byte for byte (1A's D-O2-5 method).

### Stage 1. Every read-only place is a source (F-PA-1) — 4-8 lane-hours

1. **Count first (1 h).** Rerun Z2A's sweep (`experiments/copy-census-2a-20261108/scripts/`, `mech.py`) on port main `e03abd5`.
   Count the sites each stage would reach, which Z2A's buckets do not split:
   - a source that is a bare plain parameter;
   - `Some(place)`;
   - mixed records standalone and mixed records in collections.
2. **Dict and set parameters.** The predicate accepts a bare read of a plain parameter whose type has no view form. The record lends
   the caller's block. Its loan is the parameter, which cannot change during the call, so `from p` returns work.
3. **Text, list and bytes parameters.** A parameter that a borrowed record holds bare is passed as a **block**, a new passing mode
   beside view, `own` and `mut`. The mode is decided from the callee's body and kept in its signature, as C9's owners are.
   - **The caller:** a whole value passes its block with no copy. A slice argument is copied once at the call into a temporary the
     caller owns; that is the same copy the record makes today, moved to where the slice is.
   - **The callee:** the record holds the block, so p14's `-> Spot from net` is sound.
   - **The alternative, for the lane to weigh in `DECISIONS.md`:** keep the view and decide inside the callee. A whole argument
     (owner not the sentinel, view equal to the owner) lends the owner; otherwise one frame copy is made per call. That changes no
     signature, but such a record can never be returned, which is O4's rule for frame boxes.
4. **`Some(place)`.**
   - **A projection** (a field or an element) cannot be moved implicitly, so its payload is lent.
   - **A bare local** needs the checker to tell a borrow from `return Some(x)`'s implicit move; 1A left it open (D-O2-7). Lowering
     takes the checker's mark, not the shape.
5. **Optional: task submission.** A group joins before its block ends, so a borrowed record can be a task's read-only argument when
   its sources outlive the group. Refused today.

**Not in stage 1:** slices stay copies, and E_SLICE_ESCAPES stays.

**Exit:**
- p01-p03, p11 and p14 accepted, each as a `tests/lang` guest test that fails first;
- a use-after-free probe (the owner dropped after the record's last use) and the leak check pass at debug, `-O0`, lean and
  `--release`;
- the complete gate passes, and `corpus_exact` shows 0 different;
- the port drops its F-PA-1 workaround and the counted sites with identical `equiv`.

### Stage 2. Collections of borrows (part 2a) — 16-26 lane-hours

Z2A section 7 sized it: lists, dicts, sets and options of borrowed records or text, and records that hold such a collection,
that stay local or are returned under a declared `from`.
- **Checker (`single_owner.zig`):** a collection local whose element stores borrow is a borrowed value. Its loans are the union of
  its elements' sources, found by a fixpoint over loops, with nested collections carrying nested loan sets. An element read is a
  borrow of those sources. A `from` contract stays declared, and `E_BORROW_UNDECLARED` keeps its repair.
- **Lowering and runtime:** a borrowed collection frees its buffer and never its elements. This is a shallow drop per container
  kind, which `--verify-facts` must accept.
- **Library contracts:** which `lists.*`, `dicts.*` and `sets.*` functions store a borrow or return a borrowed element.
- **Proofs:** the exporter marks the shallow drop. A trust point (A19, as O4's A18) is the cheap path. **Any change to the
  validator or the Lean model is a review stop.**
- **Port lane (4-7 h):** strip the 478 sites. The 82 that also need call precision (O3's leftovers) are hand rewrites.

**Exit:** p08 accepted; Z2A's shapes (returned under `from` 160, list of records 92, list of text 75, collection field 68, dict 36,
option 19); the port re-counted and timed.

### Stage 3. Mixed records — 6-12 lane-hours

A record whose fresh fields are owned and whose other fields are lent. Its overlay type carries a mask of the lent fields, and
its drop drops the owned ones.
- **Positions:** stage 1's, plus elements of stage 2's collections (one mask per collection type; an element with another mask is
  refused with the copy repair), plus `from` returns. A `from` return carries the mask in the IR signature, inferred from the body.
- **Reach:** 77 census sites (mostly findings: a formatted message beside borrowed names), plus the standalone ones stage 1
  counts.
- **Risk:** the census's largest unknown. The Lean model has no partly owned cell, so either the model or a trust point changes,
  and either one is a **review stop**.

**Exit:** p07 accepted; the findings shape above compiles with no copy.

### Stage 4. Caller storage — 6-13 lane-hours

- **`mut` out-parameters (93 sites, p12):** the callee's check summary records which arguments a borrow stored into `mut out`
  comes from. At the call, `out` gains loans of those arguments. This is inferred, with no syntax.
- **`mut self` fields (13 sites):** the same rule.
- **Cross-call precision (10 sites).**

**Exit:** p12 accepted, the port re-counted.

## 5. What stays a copy after all four stages

- **Slices** held in records (p06). A span (part 3) is the long-lived answer.
- **A borrow kept in state that outlives its owner's function,** such as caches and long-lived models over parse trees: Z2A's L
  class (436 sites). Part 3's spans, symbols and cache-as-table idiom cover it, or design B later.
- **Module constants and owned containers** that outlive the sources.

## 6. Order, lanes and gates

1. **Stage 1:** one Opus lane, worktree `mylang-devloop`. Then a short Sonnet port lane (the F-PA-1 workaround and the counted
   sites), run beside stage 2.
2. **Stage 2:** one Opus lane, after stage 1 lands. It shares `single_owner.zig` and `build.zig`, so the stages run in sequence.
3. **Re-count, then ask the user** about stages 3 and 4 with the port's numbers.
4. At most three lanes at once. S2 of the port can run beside these.

**Each landing gets:**
- the complete gate;
- `corpus_exact` with 0 different;
- the guest tests under `MYL_CORE_LEAKCHECK=1` in debug, `-O0`, lean and `--release`;
- the Debug compiler's certificate validation;
- `ownership-proof`'s Lean comparison unchanged, or the review stop;
- the port re-verified on a new pin: tests, `equiv s1a`/`s1b`, `fmt`, `fix --check`, and timing in one window.

`docs/ownership-rules.md` B9 is rewritten as a list of sources and positions, with an example per stage, and each stage adds a
`CHANGES.md` entry. Where the front end can decide a new shape, `W_NEEDLESS_COPY` learns it, so `mylang fix` removes the port's
now-needless copies. Where it cannot, the port lane uses Z2A's `mech.py`.

## 7. Estimates

The lane-hour figures come from Z2A section 7 and the analogy with lanes O2, O3 and O4. Elapsed time ran far under estimates:
O2 took 1.5 h, O3 2.6 h and O4 1.2 h.

| Stage | Lane-hours | Sites it reaches (Z2A, port at `9e49be1`) |
| --- | ---: | --- |
| 1, every read-only place a source | 4-8 | F-PA-1 plus the count in step 1 |
| 2, collections (part 2a) | 16-26 | 478, of which 82 also need call precision |
| 3, mixed records | 6-12 | 77, plus standalone ones |
| 4, caller storage | 6-13 | 116 |
| **All of A** | **32-59** | **671 plus stage 1's** |
| Design B, for comparison | 48-86 | A's 671, plus slices, plus part of L's 436 |

Z2A measured the wall-time share of stages 2-4 at 3.1% (`s1a`) and 5.9% (`s1b`). The port is already at 0.91x and 0.90x of
netlisp, so the gain is mostly shape: no copy where Zig has none, and less agent time on copies.

## 8. Decisions for the user

1. **D1, the design:** A, inferred (recommended), or B, declared view fields.
2. **D2, the scope now:** stages 1 and 2, then a re-count before 3 and 4 (recommended); stage 1 only; or all four.
3. **D3, proofs:** a new trust point per stage (A19 and on, the cheap path O4 took), or the Lean model extended for shallow drops
   and partly owned cells. A trust point keeps each stage small, while a model change keeps the proof whole. Either way it is a
   review stop.
