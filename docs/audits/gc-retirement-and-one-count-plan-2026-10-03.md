# Retire the tracing GC, then give every RC object one count: plan, 2026-10-03

This plan is written to be handed to AI agents that did not see the conversation it came
from. It covers two user goals:

1. **Retire the tracing GC.** Decided on 2026-10-02: reference counting is the only runtime.
2. **One count per RC object.** Every object carries `owners` and `holds` today; the goal
   is `owners` only.

**Decisions D1–D4 (section 4.2) were accepted on 2026-10-04: the user took the recommended
option for each.**

**2026-10-05:** Part G and the checker and front-end halves of Part C continue. The
old-core RC re-plumbing (C2, C6–C8) is paused. See §5. The runtime-performance plan `docs/audits/runtime-language-levers-2026-10-04.md`
(WP-5) schedules this work.

Base: `main` at `6df58b02`. The facts below were checked on that commit by three review
lanes on 2026-10-03; the evidence index is at the end. Read sections 1–3 before any work
package (WP).

## 1. Summary

**GC retirement is mechanical but wide.**
- Nothing in the repository needs the collector or `--legacy-sharing` outside tests and
  docs. That includes the Lox port, the corpus, `selfhost/`, schematic and the EDA app.
- A trial deletion of `Selection.gc` and the legacy-sharing switch gives at least 185
  compile errors in 72 files.
- Removable: about 2,300 lines of runtime C, about 2,000–2,700 lines of lowering and CLI,
  and about 1,500 lines of collector tests.
- About 2,950 lines of C library tests run on a tracing heap. They must be **ported to an
  RC heap, not deleted**.
- Two things the GC does today have no replacement yet, so they come first (WP-G1):
  - it is the differential fuzzer's baseline;
  - `--gc-stress` is the only whole-program memory-error stress mode.

**One count needs language decisions, not just runtime work.**
- Uniqueness already reads only `owners`. `holds` decides only when an object dies, plus
  one address-stability test in `storage_extend`.
- Most hold kinds are lifetime-only and can become a `+0` borrow, an owner, or a mark bit
  with no change in meaning:
  - call pins on `mut` arguments;
  - unproven operand loans;
  - ownerless temporaries;
  - runtime internals.
- Three hold kinds exist because mylang deliberately copies **Python's aliasing**:
  - **live iteration:** `for v in xs` sees `xs[1] = 9` written by the body or by a `mut`
    callee;
  - **live dictionary views:** `d.keys()` and friends stored in a variable;
  - **the pending-receiver window:** `xs[f(mut xs)] = v` and `b.items[g(mut b)] = v`.
- Every one of these matches CPython today (verified). A single count cannot express "an
  alias that does not block in-place writes", so each needs a decision (D1–D3, section 4.2).
- Holds are still **a third of all count operations** (33.6% across the corpus at full
  size). 80% of them are operand loans, concentrated in the Lox VM. The census (4.3) found:
  - **no corpus program depends on a hold for a uniqueness decision** except through call
    pins and receiver borrow scopes (K4/K6), which become a mark bit;
  - **no hold is ever taken on an ownerless object** in the corpus.
- The payoff:
  - a 16-byte header instead of 32 bytes (−16 B per object; about −10 MB on
    `scan_split`, the one corpus program whose memory is above GC's);
  - one load for uniqueness and for death;
  - fewer count operations where loans become static borrows;
  - the end of the owner/hold role bug class.

**Order.** GC retirement goes first. It frees the shared header, removes the GC and GC-stress
columns from every validation matrix, and has no language impact. The one-count work runs
its measurement phase in parallel and its implementation after.

## 2. Common rules for every WP

- Work in your own worktree under `/home/epentland/ai/canopy/mylang-worktrees/`.
  - Claim it with `git worktree lock --reason "<who>: <branch>"`.
  - Never use the main checkout `/home/epentland/ai/canopy/mylang`: another session's
    uncommitted work lives there.
- Share `ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache`.
  - Keep `ZIG_LOCAL_CACHE_DIR`, `.mylang-cache`, `TMPDIR` and scratch inside your
    worktree.
  - Never share a `.mylang-cache` between different compiler builds.
- One build-heavy job at a time per lane. Never `pkill`/`killall` by pattern; kill only
  PIDs you started.
- **Gate** = the four CLAUDE.md steps, plus:
  - `tests/lang` in default and `--release`;
  - the Lox port build and tests (RC, QBE and LLVM);
  - `zig build test-rc-fuzz` with the current baseline;
  - `experiments/rc-perf-20260927/quick.py` dev size, every row within 1% of the previous
    accepted RC checkpoint.

  A lane that skips the Lox build has shipped a regression before (NUM-LITERAL-4 hint,
  2026-09-28).
- Every behavioural change needs a `// spec:` test and a SPEC.md bullet (Guardian).
  - Removed rules: delete the bullet and list it in the WP report.
  - Do not bypass the pre-commit hook.
- Report per WP: what changed, the deleted or converted tests by name, lines removed, gate
  logs, and the perf table.
- Nothing lands on `main` without the user's explicit OK.

## 3. Part G: retire the tracing GC

### 3.1 Facts (checked on 6df58b02; corrects the 2026-10-02 inventory)

| Claim in the 10-02 draft | Actual |
|---|---|
| 48 src files mention GC flags | 67 files. 96 `runtime_mode.enabled()` sites in 30 files, 3 `lowered()`, 11 `counting()` |
| 48 `pinCollector()` uses | 46 in 9 test files, plus 15 `runtime.set(.gc)` in 13 files and **39 `.gc_stress` test sites in 19 files that silently select GC** (`native_execute.zig:126`) |
| `qbe_frame_map.zig` is GC machinery | No. It maps call sites to return addresses for traces, and stays |
| The LLVM emitter carries GC lowering | About one reference (`myl_qbe_root_mark`, `qbe_build_llvm_runtime.zig:89`); it is GC-agnostic |
| `experiments/rc-review-20260928/repros/open-gc-*` are open | None reproduces on 6df58b02 under rc, `--gc-runtime` or `--gc-runtime --gc-stress`. Close them |
| `GC-*` SPEC bullets are collector rules | 13 of 29 are language rules (`GC-SOURCE-*`, `GC-GENERIC-*`, `GC-BOUNDARY-1`, `GC-CAPABILITY-1`). Keep them |

**What RC borrows from the GC today.**

| Machinery | Use under RC | After GC |
|---|---|---|
| 16-byte common header (mark word + descriptor) | Mark bits IMMORTAL, ARENA, SHARED, PINNED, LARGE, element count; bit 0 reused as DYING | Keep and rename. Part C reshapes it |
| `myl_native_heap` struct | RC reads `bytes`, `limit`, `exhausted`, `objects_live`, `region_depth`, `collections`, `rc`, `rc_cache`. Generated code freezes offsets 64, 112 and 5648 (`qbe_alloc.zig:107-111`) | Re-lay out the struct, bump the identity to `rc-v6`, and change the Zig constants in the same commit |
| GC allocator, segments, pools | Not used: RC has its own slab allocator (`native_rc_alloc.c`) | Delete |
| Memory budget | RC charges `heap->limit` itself; the RLIMIT guard sits in `native_heap.c:39-114` | Keep, moved |
| Descriptors | RC uses `fields`, `kind`, `rc_id`, `element`, `key`. `trace_fields`/`trace_mode` are read by value copy, COW and arena escape | Keep those. Delete `scan`, `scan_count`, `cell` and `myl_native_scan_flatten` |
| Roots, safepoints, frame root slots | None in generated RC code. **But the C library still pushes roots under RC**: about 170 `myl_native_root_push/pop` lines in 14 files, and the collector entry points are linked into RC binaries | Delete; a small RC size and instruction win |
| `findRoots` / `has_roots` | Also decides whether `%heap` is materialized for RC (`qbe.zig:2083`) | Reshape into a needs-heap flag |
| Liveness | `liveness.solve/extend` feed ownership and RC | Keep; delete `Roots` |
| `allocates`/`pure` facts | GC root protocol, plus RC `physicalIdentity`, cache keys and the interface fact. `firstPass` (`qbe.zig:1291`) lowers every function once just to compute them | Reshape. A cheaper analysis is a compile-time follow-up (G7) |
| Arenas | RC allocates through `myl_native_arena_alloc` and `rc_new_chunk` | Keep. Delete GC collect-on-pressure, stress, header scan and `heap->suspended` |
| Resource finalization | `myl_native_owned_drop` dispatches to `myl_rc_owned_drop` | Delete the GC path. Reword RC-TRAP-TEARDOWN-1, whose close order is currently defined as "same as under the tracing collector" |

**Legacy sharing (`class`/`Cell`) has no users in the repository** apart from:
- `tests/legacy` (3 files);
- two doc examples (`managed-memory.md:579`, `records-and-unions.md:59`);
- velocity idioms a38/a39, already `rejected-by-design`;
- historical experiments.

`eda-bench` has no class/Cell code and no legacy configs. Two things survive the removal:
- **The `class` lowering machinery.** Recursive-value boxes are managed records allocated
  through `qbe_alloc.cell()` with `_body` descriptors (`native_descriptors.zig:92-101`).
  Delete only the `class` surface and its GC inline path.
- **The diagnostics `E_VALUE_CLASS`/`E_VALUE_CELL`.** They point at records, recursive
  values and `pool.Handle`.

**In-flight branches.**
- `codex/differential-fuzz-20261002` (43 ahead of main; it contains the EDA merge candidate
  and its repairs) **adds new GC lowering**:
  - `qbe_record_paths.zig` (roots, `restoreRoots`, barrier);
  - `qbe_slot_transfer.zig`;
  - tests that loop over `.rc` and `.gc`.

  Land it before G3–G5. Deleting a few dozen extra lines is cheaper than rebasing the merge
  over a GC removal.
- `codex/lox-parity-20261003` (68 ahead) has two tests that loop over `gc_stress`. Either
  order is trivial.

### 3.2 Work packages

**G0. ADR and history (docs only; can start now).**
- Write `docs/adr/D10-rc-only.md`, superseding the GC-availability clauses of D3 and D9.
  Reasons:
  - RC is within about 7% of GC instructions on the corpus, with lower median memory;
  - value semantics makes the heap acyclic;
  - every lane pays for two runtimes.
- Record the final GC corpus numbers once, using the existing GC side of `quick.py`
  (`gc-cache.json`), plus the last fuzz receipts.
- Mark the `open-gc-*` repros non-reproducing.

**G1. Replace what only the GC provides (before any deletion; can start now).**
- **(a) An independent oracle for the fuzzer.** No "reference RC mode" exists, and no single
  switch could make one. Ownership optimizations sit behind about six choke points, and the
  RC certificates change the call ABI (borrowed and immortal returns, alternate entries),
  so a reference mode would need its own runtime identity.
  - Instead, port the independent Python expected-output model from
    `codex/differential-fuzz-20261002` (commit `95dd7cdd`; 107 seeds pass) into
    `experiments/rc-fuzz` as the baseline.
  - Compare RC QBE, RC `--release` (LLVM) and the model.
  - The proof-denial reference mode moves to Part C, which needs it anyway (C0).
- **(b) An RC check mode** (`--rc-runtime=check`), replacing `--gc-stress` as the
  memory-error stress tool:
  - poison and quarantine retired slots;
  - check the death and uniqueness invariants on every count operation;
  - optionally fill fresh payloads with a pattern.

  Today nothing detects a use-after-free in a compiled guest except the always-on
  `myl_rc_invariant` asserts; C-level ASan covers only unit tests.
- **Accept:**
  - 500 seeds against both the GC baseline and the new model, with identical divergence
    sets;
  - a sabotage set modelled on `experiments/edit-fuzz-20260930/sabotage.sh`, which must be
    caught by (a) or (b):
    - disable one COW check;
    - drop one owner early;
    - skip one transfer guard;
    - reintroduce RC-INTERVAL-ANCHOR-2's alias use-after-free;
  - `tests/lang` passes under check mode.

**G2. Remove legacy sharing.**
- Delete:
  - the frontend switch (`--legacy-sharing`, `MYLANG_VALUE_SEMANTICS=0`,
    `"value_semantics": false`), which becomes a clear error;
  - `value_semantics.enabled()` and its call sites in sema, origins, nominal_templates,
    cell_types, generic_bodies and view_cycles;
  - `runtime_contract.resolve()` and `runtime_mode.lowered()` special cases;
  - `test_support.LegacySharing` (about 55 sites in 25 files), `managed_cell_test.zig`,
    `tests/legacy` and the `test-legacy-sharing` lane;
  - the `managed-class-records` slug and the doc examples;
  - `values=` in `configName`, with a deliberate interface-key bump.
- Delete the legacy-only alias defenses:
  - `otherMutableParameter` (COW-FIELD-RETURN-1);
  - the any-other-`mut` refusal in `ownership_index_return.zig:67`.
- `aliasable()` in `qbe_rc_readonly_anchor.zig` is not gated on legacy. Prove it
  unreachable under MUT-EXCLUSIVE-1, with a test, before deleting it.
- Recheck RC-DEAD-FIELD-MOVE-1. It was written to match the GC's false
  `R_LIST_ITERATION_MUTATION`, and the repro now prints the right answer.
- **Accept:** gate, doctest, doc-coverage, EDA app (323 tests, 34/34 reference cases), Lox.

**G3. Remove the GC selection, flags and lanes.** The lowering stays, unreachable.
- Delete:
  - `Selection.gc`;
  - `--gc-runtime` and `--gc-stress` (in invoke, `native_execute`, `native_test_*`,
    `schematic/runner.zig:22-28`, `schematic/tests.zig:84`, `qbe_runtime.c:906-936`);
  - `MYLANG_RUNTIME=gc-v1`;
  - the `test-lang-gc` lane and the value-semantics GC lane;
  - the 74 `--gc-stress` goldens (60 in `qbe_native_cases.json`, 14 in `qbe_files.json`);
  - the GC choices in the oracle scripts, `scripts/affected_tests.py:510`, and the
    `run.py` BASELINE/STRESS lanes (replaced by G1).
- `--gc-runtime` and `MYLANG_RUNTIME=gc-v1` fail with "the tracing collector was removed;
  reference counting is the only runtime" for one release.
- Untagged historical manifests (`qbe_build.zig:916`) become invalid instead of decoding
  as GC.
- Set the `EmissionConfig.runtime` default (`qbe_fragments.zig:54`) to RC.
- **Convert, do not delete, program-meaning tests:**
  - every one of the 39 `.gc_stress` sites keeps its RC run;
  - meaning tests reached only through `runtime.set(.gc)` move to RC.
- **Delete** tests that assert roots, safepoints, barriers or stand-in lowering (most of
  `qbe_test.zig`'s `pinCollector` uses).
- The deterministic list comes from `.tmp/round2.patch` in
  `mylang-worktrees/claude-gc-delete-probe`: apply it, run `zig build test-compile`, and
  iterate.
- **Accept:**
  - gate green;
  - `tests/lang` count unchanged under RC;
  - every deleted Zig test listed by name with its reason.

**G4. Delete GC lowering.**
- Delete:
  - `qbe_roots.zig`, except the pure-callee list;
  - `qbe_cover.zig`;
  - `qbe_moves.zig`, which is planned only when RC is off, together with its
    QBE-MOVE-ELIDE-1 refusal;
  - `Roots` in `qbe_liveness.zig`;
  - the root, `restoreRoots`, barrier and `self.moves` sites;
  - the class windows and barrier in `qbe_alloc.zig`;
  - scan-plan and `.cell` emission in `native_descriptors.zig`.
- Collapse the 96 `enabled()` branches to their RC side.
- **Accept:** gate, plus **RC IL byte-identical** before and after on the corpus and on
  `tests/lang`. This is the check that nothing RC used was removed.
- Do not run G4 at the same time as perf lanes in `src/qbe*.zig`.

**G5. Delete the C collector.**
- Delete:
  - about 1,200 of `native_heap.c`'s 1,361 lines and about 250 of `native_heap.h`'s 566;
  - the library root pushes;
  - dead `native_value_copy.c`;
  - `native_cow.c/.h`, if deleting it confirms that no RC binary links it (none of the
    three sampled does).
- Collapse the 68 `myl_rc_enabled()` dispatches.
- Re-lay out the heap struct (`rc-v6`).
- **Port** the roughly 2,950 lines of tracing-heap C library tests to an RC heap (text
  dictionary, arena chunks, text index, collections, text views, text methods, regions,
  bytes, python, print, equal). Keep the budget and equality parts of
  `native_heap_test.c`.
- **Accept:**
  - `test-native-memory` and the gate;
  - corpus RSS and instructions no worse than the last RC checkpoint;
  - binary size reported.

**G6. Docs.**
- SPEC.md: delete about 16 collector-only bullets and mark the superseded ones in D10.
- Features: `guest-test-gc-stress` and `nonmoving-tracing-gc`.
- Limits: `gc`, `managed_lists`, `value_semantics`.
- Text: the 24 non-audit docs (led by `managed-memory.md`, `tooling/native-build.md` and
  D9), plus CLAUDE.md (8 mentions) and README (9).

**G7. Follow-ups (optional).**
- Replace `firstPass` with a cheap `allocates`/`pure` analysis; this is a compile-time win.
- RC-aware stand-in reuse.
- Measure the gate wall time before and after Part G.

**Part G acceptance (final report).**
- The CLAUDE.md gate is green with no GC lanes.
- Lox, the EDA app, the fuzzer (500 seeds against the model baseline) and the incremental
  oracles and edit tester all pass.
- The report gives lines removed per area (compiler, runtime C, tests, docs), the gate wall
  time before and after, and every deleted or converted test.

## 4. Part C: one count per RC object

### 4.1 Facts (checked on 6df58b02)

**Layout today:** `[owners u64][holds u64][mark u64][descriptor]`, a 32-byte prefix
(`native_rc.h:19-30`, ABI5 `rc-v5`). `retired_link` is in a union with the counts.

**What each count decides:**
- **Uniqueness reads only `owners`** (`native_rc_internal.h:368-378`,
  `qbe_rc_glue.zig:322-337`, `qbe_rc_element_take.zig:64`).
- **`holds` appears in exactly two decisions:**
  - death, which needs both counts at zero (`native_rc_internal.h:348-365`,
    `native_rc_walk.c:163`, `native_rc_scope.c:94`; glue loads the other count only on the
    last-token path);
  - `storage_extend`'s address-stability test, `holds == 0` (`native_rc_alloc.c:662`).

So "one count" does not change any uniqueness decision. It asks whether every hold can
become nothing (a static `+0` borrow), an owner (`+1`) or a mark bit, without changing
meaning or adding copies.

**Why the 2026-09-29 layout work kept two counts** (`docs/audits/wp-b3-layout-2026-09-29.md`):
- It listed four obstacles. This plan answers each:
  1. **A live view or iterator holds while the owner mutates in place.** Decisions D1
     (live-place iteration needs no token) and D2 (views cannot be stored).
  2. **An ownerless held payload (O0,H1).** The holder takes the dying owner's token
     instead, which gives (O1). The census found no hold ever *acquired* on an ownerless
     object in the corpus.
  3. **Receiver pins need a lifetime token.** Call pins become the PINNED bit, because
     MUT-EXCLUSIVE-1 keeps the caller's slot owning. Pending receivers need D3.
  4. **One total count cannot tell (O1,H1) from (O2,H0).** After D1–D3 the only holders
     left are K3 loans. The value-semantics rules forbid writing a source while its loan is
     live, and the census saw no loan-only flip in the corpus. C6 releases each converted
     owner at the last read.
- The 32-bit pair (ABI4) failed the perf gate. Restoring two 64-bit counts **still failed
  16 of 26 rows**, so width was not the main cause. The audit attributes the loss to the
  count-capacity admission protocol it shipped with:
  - whole-value pre-admission with rollback;
  - three COPY guards adding 16.2M instructions to Lox `load_frame`;
  - a loan path that grew from 18 to 26 instructions.
- Those guards are still on main (RC-GLUE-1, RC-COUNT-CARRY-1, RC-COUNTS-1).

**Hold kinds.** Static taxonomy from the review lane; dynamic numbers in 4.3.

| Kind | Producers | Why a hold | Holder sees owner's in-place writes? | One-count replacement |
|---|---|---|---|---|
| K1 iteration source | `qbe_rc_views.zig:132-145`, `qbe_rc_holds.zig:10-23`, `cow_plan.zig:298` | Keep the original header alive across rebinding without making the source look shared | **Yes, by design** (COW-ITERATION-IDENTITY-1), as in Python | D1 |
| K2 stored dictionary view | HOLD_POINTER shape (`native_rc.h:44-48`); `native_rc_transfer.c` `transfer_hold`/`replace_held`/`unique_held`; `box_detach_held`; codec held path | A view aliases its mapping | **Yes, by design** (DICT-VIEWS-1, RC-HELD-RECEIVER-1). Writes through `view.mapping` reach `mapping` only when nothing else shares it (`rc_view_receivers.my:5-18`), a value-semantics hazard | D2 |
| K3 operand/temp loans (LOAN role) | `qbe_rc_values.zig:84-95,228-246`, `qbe_rc_loans.zig:76-97`, `native_rc_values.c:193-238`, `native_rc_transfer.c:597-630` | A borrowed read whose static proof failed. Includes ownerless (O0,H1) fields of dying temporaries | No: VALUE-SEMANTICS-5/14 and MUT-EXCLUSIVE-1 forbid the write. Place-alias captures (RC-PLACE-ROLE-1) follow K1 | `+0` where proven. Otherwise **move the dying owner's token** ((O0,H1) becomes (O1), as RC-UNIQUE-FIELD-TAKE-1 does), released at the last read |
| K4 call pins on `mut` collection arguments | `qbe_cow.zig:357-379`, `native_rc_scope.c:139-208`, `qbe_runtime_rc.c:242-280` | Header lifetime and backing address stability | No (same object; MUT-EXCLUSIVE-1 means the caller's slot owns throughout) | **PINNED bit only**; no count |
| K5/K6 pending receivers (`a.b[i] = f(...)`, `xs[g()].append(...)`) | `qbe_cow.zig:902-951,1324-1335`, `native_rc_scope.c:298-386` | The write address must stay valid if a nested `mut` call replaces the containing entry | **Yes** (see below) | D3 |
| K7 transfer and rollback internals | `replace_held`, `box_detach_held`, `unique_held`, walk unloan | Consumers of K2/K3 | — | Removed with K2/K3 |
| K8 trap teardown, stats | `native_rc_alloc.c:584-592` | Accounting | — | Trivial |

**The pending-receiver window (K5), verified on main.** Today's results under RC, GC and
`--release` are identical to CPython's:

```text
values = [7, 8]
values[change(mut values)] = 5     # change appends 91 -> [5, 8, 91]
b = Box([1, 2])
b.items[rebind(mut b)] = 9         # rebind sets b.items = [55, 56] -> [55, 56]
```

In the second line the 9 goes to the orphaned old list, which only the hold keeps alive.
Python does the same, because it evaluates `b.items` before the subscript.

**Live iteration (K1), verified against CPython.** Mylang matches Python today:
- `for v in values: total += v; values[1] = 9` gives `total == 10`;
- rebinding `values = [7]` inside the loop keeps iterating the original (`total == 3`);
- `for o in vm.objects: mark(mut vm, o)` sees the callee's writes to later elements.

**The codex branch adds no new hold producers.** `codex/lox-parity-20261003` only adds
proofs that remove traffic, and is compatible.

### 4.2 Decisions for the user

**Accepted 2026-10-04:** the user accepted the recommended option for D1, D2, D3 and D4.
The alternatives stay in the table for the record.

| # | Decision | Recommended (accepted 2026-10-04) | Alternatives (rejected) |
|---|---|---|---|
| **D1** | Iteration semantics without a hold | **Live place.** When the source is a place rooted at a local or parameter (`xs`, `vm.objects`, `a.b[i].c`), the loop holds a reference to the slot, not a token, and re-reads the header on each step. Writes by the body or by `mut` callees stay visible, exactly as in Python, and growth is harmless. The length check still traps structural changes. A non-place source (call result, literal) is owned by the loop (O1). The loop snapshots at entry (O) only when the body rebinds the **root local**; the write-back idiom `wb = it.rt; f(mut wb); it.rt = wb` stays live. Add an `iteration_check` on every indexed collection along the path, so `del rows[0]` by a callee traps instead of silently switching rows. | **Snapshot (Swift).** Iterate the value at loop entry. This silently diverges from Python (the first example gives 3, not 10) and adds an O(n) copy per loop to the Lox `mark(mut vm, o)` idiom, unless an interprocedural proof shows current-index-only writes. **Keep a count for iteration only:** see the stopping rule |
| **D2** | Stored dictionary views | **Views cannot be stored.** `d.keys()`, `d.values()` and `d.items()` may appear only as iteration sources (lowered as D1 over the mapping place) or as immediate arguments (`len`, `in`, `list`, `set`, `sorted`). Storing one is a compile error with the fix-it `list(d.keys())`. | **Views become values:** a snapshot of the mapping, with `view.mapping[k] = v` writing the view's own copy. This is a silent divergence from Python |
| **D3** | The pending-receiver window | **MUT-EXCLUSIVE-4:** in an assignment or mutating call whose target place is rooted at R, a `mut` argument in the target's index/key expressions or in the right-hand side whose place overlaps the target path is `E_MUTATION_OVERLAP` (same overlap rules as MUT-EXCLUSIVE-1; Swift rejects these). Fix-it: `i = change(mut values); values[i] = 5`. With no globals, closures or walrus, nothing else can disturb the target during the window, so receiver scopes need **no token**. Inferred, to verify in C3: once such programs are rejected, evaluation order inside a write is unobservable, so lowering may resolve the place last and drop the pin too. | **Resolve the place after its operands:** no error and no token. It matches Python for `values[...]` but silently gives `[55, 9]` for the `rebind` line, where Python gives `[55, 56]` |
| **D4** | Count width and overflow | **One 32-bit count that saturates to sticky:** at 2^32−1 the object becomes IMMORTAL (it leaks; every path already treats IMMORTAL as uncounted and non-unique). An acquire is `add; jc slow`, with no capacity admission or rollback, which removes the guards that sank ABI4. | Keep exact refusal with rollback (the ABI4 cost) |

D1–D3 change behaviour only in rare programs, and almost always loudly: each case keeps
Python's answer, traps, or fails to compile. One silent case remains under D1: a `mut`
callee assigning a whole new value **of the same length** to a field-path iteration source.
Python has no exact analogue, because a mylang `mut` assignment acts like Python's
`xs[:] = ...`, which Python's iteration also sees. Today's named-snapshot result also
changes, to Python's answer. C1 counts the affected sites before any implementation.

### 4.3 Dynamic census

Measured by the census lane on 2026-10-03 (`claude/hold-census` at `1d3155f3`,
`experiments/hold-census-20261003/`):
- **Method.** Counters run only in counting builds. Every hold is tagged by kind; a
  "flip" is a uniqueness decision taken in place while `owners <= 1` and `holds > 0`,
  which a single total count would turn into a copy.
- **Production unaffected:** production `--rc-runtime` binaries are byte-identical to main
  for all 29 corpus binaries.
- **Coverage:** the corpus is QBE only, at full and dev size. `tests/lang` (1,495 test
  processes) and the Lox-port tests (65) were measured at dev size. LLVM was not measured.

| Kind | Hold acquires, corpus full size | Share | Programs | Flips (corpus) | Notes |
|---|---|---|---|---|---|
| K3 loans | 77M | 80.0% | 20 | 0 | Top sites are Lox `vm::invoke` vm.my:218/220, `vm::get_property` :350/:352, `vm::call_value` :177, `scan_split`, `text_ops`. Owners at acquire: 43M one, 34M two or more. 74M open a fresh hold epoch |
| K6 borrow scopes | 8.61M | 8.9% | 18 | 2 (+1,707 mixed with K4) | Half pins, half backing-storage holds. The only holds that refuse `storage_extend` (2–4 per Lox program) |
| K1 iteration sources | 5.52M | 5.7% | 26 | 0 | `raytrace`'s only RC traffic: 3.37M holds against 1 owner acquire. `alloc_churn` iterates 1M temporaries |
| K4 call pins | 5.18M | 5.4% | 11 | **5.18M** | All corpus flips. The Lox object table: the caller's pin in `heap::set_instance_field` covers `objects` (about 21k elements in binary_trees) while the callee writes in place. One total count would copy that list on every Lox field write. The hold is released at scope end and never read after the write |
| K2 views | 4 | — | 1 | 0 | `knucleotide` only |
| K5, K7, K8 | 0 | — | 0 | 0 | |

Per program, holds are:
- 50% of count operations on Lox `binary_trees`;
- 43% on `method_call`;
- 76% on Lox `strings`;
- 49% on `scan_split`;
- 0–1 holds on about 20 of the parity programs.

**Test suites at dev size.** `tests/lang` takes 0.31M holds (K6 0.20M, K3 78k, K4 38k,
K2 1.5k, K1 678). Its 19k flips are broader:
- single-kind flips: K4 6,280, K3 218, K6 192, K2 28, K1 23, K5 2;
- about 12k mixed, mostly K3+K6 and K3+K4.

Where the single-kind flips come from:
- **K2:** live views. The holder wants to see the in-place write, so one count breaks them;
  this is D2.
- **K1:** `iteration_identity`, `rc_nonheld_captures`, `rc_pin_elide`, `root_liveness`.
  These are D1.
- **K3:** `rc_writeback_moves` (`items = bag.items; items.append(i)` in a loop) and
  `rc_glue_values`. C6 must handle these without adding a copy.

**Ownerless objects.** No hold is ever acquired on an object with zero owners in the corpus:
- An object becomes ownerless only when its last owner drops under an existing hold, and it
  then dies at a hold release:
  - K1 1.0M (`alloc_churn`'s `for x in` a temporary);
  - K3 0.5M (`text_ops`, Lox `adjust_capacity`);
  - K1+K3 0.36M (Lox `trees`).
- At most 5 objects are ownerless at once in any program.
- Only `tests/lang` acquires holds on ownerless objects: 53 times, mostly view extracts and
  loans.

**Maximum counts.**
- Max owners on one object: 250,157 (`knucleotide`), so owners need more than 16 bits;
  32 bits are enough.
- Max holds: 20 in the corpus and 262 in tests (stored view copies in
  `rc_dictionary_views`).

**What this means for the plan.**
- **C2 is the only phase that touches corpus flips,** and it removes them by construction:
  a PINNED bit does not count, so uniqueness is unchanged. Every K4 and K6 capture also
  takes a **backing hold on the list or dictionary storage**, which doubles their traffic.
  C2/C3 replace it with the PINNED bit, checked by `storage_extend`.
- **C6 is the largest traffic item.** Converting loans to owners costs the same today, but
  each loan proven as a static borrow removes a pair of count operations. Lox VM rows
  should improve.
- **C4 removes `raytrace`'s 3.37M iteration holds outright,** because its sources are root
  locals.
- **Fallback 3 of the stopping rule (side table) is not viable at today's traffic.** It
  would need holds below about 0.1% of count operations, which they reach only after
  C2–C6.
- **Not measured:**
  - whether a holder reads after a flipped write; the census reports releases after the
    write as an upper bound, and the K4 releases are all scope ends;
  - the LLVM arm;
  - per-site attribution inside `tests/lang`, which is per file instead.

### 4.4 Work packages

Each C package is gated by:
- the common gate;
- 100 or more fuzz seeds against the G1 model baseline;
- `experiments/rc-review-20260928/repros`;
- new repros: both pending-receiver lines, iteration observing a later write, a write
  through a stored view, a `match` scrutinee temp across a write, and growth during an
  element borrow;
- a sabotage check (re-add or remove one token in one kind and confirm the fuzzer or
  repros catch it);
- `quick.py` dev and full, with every row within 1%.

Layout alone moves rows 1–3%, so attribute any row that trips with exact instruction
counts before rejecting.

| WP | Work | Needs | Size |
|---|---|---|---|
| **C0 Census and shadow modes** | The census counters and per-kind tags exist on `claude/hold-census` (4.3, RC-HOLD-CENSUS-1); land them, after the full gate, which that lane did not run. Add a **hold-as-owner shadow switch**, where every hold acquire and release goes to `owners`: failing guest tests are exactly the semantic dependences (expected K1, K2, K5), and the clone delta is the cost. Add the **proof-denial reference mode** deferred from G1: certificates denied at the choke points (`ownership.analyze`, `qbe.zig:1941-1978` certificates and finalize planners, per-site proofs, COW-PIN-ELIDE-1), with its own runtime identity. | Can start now | M |
| **C1 Decisions** | Diagnostic-only passes count D1/D2/D3 sites in `tests/lang`, the corpus, the Lox port, schematic and the EDA app. D1–D4 were accepted on 2026-10-04. The counts now size the migration and list the sites to fix; they no longer gate the decision. | C0 | S |
| **C2 Call pins** | Drop the hold from K4 call pins and their backing-storage holds; keep PINNED on the header and let `storage_extend` test it instead of `holds == 0`. This removes all 5.18M corpus flips by construction. First prove that RC-ELEMENT-BORROW-1 address borrows never span storage growth. | C0 | M |
| **C3 MUT-EXCLUSIVE-4** | Implement the rule, then remove K5/K6 holds (and the pin, if place-last lowering holds up). | D3 | M |
| **C4 Live-place iteration** | Place-source forms in `prelude_builtins.zig` desugars (`for`, `sum`, `any`/`all`, `zip`, `enumerate`); delete the `iterationOwner` hold paths (`qbe_rc_views`, `qbe_rc_holds.mayHold`, `cow_plan`, `ownership_classify`); make the iterated place count as read every iteration in `rc_field_transfer`; dereference in `qbe_loop_facts`; restate the element-borrow condition in `qbe_borrow.zig:130,632`; per-path `iteration_check`. `iteration_identity.my`'s named-snapshot test changes to Python's answer (10) | D1 | M–L |
| **C5 Non-storable views** | `E_VIEW_STORED` (or reuse an existing code) with fix-it. Delete HOLD_POINTER, `transfer_hold`, `replace_held`, `unique_held`, `box_detach_held`, the codec held path, and the LIVE-VIEW-* / RC-HOLD-VIEW-1 / RC-HELD-RECEIVER-1 bullets. Update the `dictionary_views` tests | D2 | L |
| **C6 Loans** | The largest traffic item (77M of 96M corpus holds; Lox `vm::invoke`, `get_property`, `call_value`). Static `+0` where proven. Otherwise move the dying owner's token and release it at the temp's last read. Delete the LOAN role and the runtime role dispatch (`qbe_rc_values.zig:211-246`, `myl_qbe_rc_drop_role`). Watch the C0 flip counter: an O held across a write would add a COW copy | C0 | M |
| **C7 Remove `holds`** | Death becomes `owners == 0`. Counting builds first assert `holds == 0` for one full gate cycle; then delete the field and the hold stats (ABI `rc-v7`) | C2–C6 | S |
| **C8 16-byte header** | word0 = high 32 bits count, low 32 bits flags (DYING, IMMORTAL, PINNED, SHARED, ARENA, LARGE) plus a 24-bit element count (slab objects need 17 bits; LARGE keeps its side header; arena objects are uncounted, so the high half holds their element count and the low bits their region depth); word1 = descriptor. Uniqueness and death become one load. Saturation per D4. Adapt slab offsets, inline allocation (`qbe_alloc.zig:155`), `qbe_rc_prefix.zig`, `qbe_rc_glue.zig:22-31`, literal images and arenas | C7, G5, D4 | L |

**Expected effect of C8:**
- −16 B per slab object; strides are multiples of 16, so the saving is exact.
- `scan_split` (660K small strings) goes from about 76 MB to about 65 MB, against GC's 66 MB.
  This is an estimate.
- `binary_trees` 16-byte nodes go from 48-byte to 32-byte strides.
- A 32-bit dense type id or an 8-byte header is not recommended yet: runtime and dictionary
  descriptors have no id, and 16-byte payload alignment would need ABI4's slot-offset trick.

**Stopping rule.** If a kind cannot be removed without a row above 1%, or with a semantic
change the user rejects, fall back in this order:
1. **Frame-local exception:** `unique iff owners − (this frame's live tokens on p) ≤ 1`, a
   static pointer compare. Valid only for holders that never cross a call.
2. **A narrow hold count in word0's spare bits** (about 8 bits, saturating-sticky). It keeps
   the 16-byte header, but every remaining hold site stays.
3. **A HELD mark bit plus a heap side table of hold counts.** Only if C0 shows holds at or
   below about 0.1% of count operations.

A plain save/restore "loaned" bit is sound only for strictly LIFO holders on one object, and
operand loans relocate between temps (RC-LOAN-RELOCATE-1), so do not use one without a proof.

## 5. Order and lanes

**Scope change, 2026-10-05 (the user accepted it).** A new compiler core is being built with
its own runtime and one count from day one. The plan is `docs/audits/new-core-plan-2026-10-05.md`
on `claude/runtime-levers-plan`; this split is revision 5 of
`docs/audits/runtime-language-levers-2026-10-04.md`.

**Continue:**
- Part G in full;
- C1;
- C3's checker rule (MUT-EXCLUSIVE-4);
- C4's front-end half: live-place desugaring, `iteration_check`, and updating
  `iteration_identity.my`;
- C5's checker half (`E_VIEW_STORED`).

**Paused:**
- C0 beyond what C1 needs;
- C2, C6, C7 and C8;
- the old-core RC halves of C3, C4 and C5.

The order below still applies to the parts that continue.

```
now:        G0 (docs) | G1 (model oracle + RC check mode) | C0 (census + shadow + reference mode)
after EDA merge lands (codex/differential-fuzz-20261002 or its successor):
            G2 -> G3 -> G4 -> G5 -> G6        (one lane; G4/G5 not alongside src/qbe*.zig perf lanes)
after C0:   C1 (site counts; D1-D4 accepted 2026-10-04) ; C2 and C6 (no language change) may run beside G2/G3
after G5:  C3, C4, C5 (separate lanes; C4 and C5 share the iteration lowering, so land C4 first)
then:       C7 -> C8
```

- Part G before Part C's implementation, for three reasons:
  - G removes the GC and GC-stress columns from every C validation run;
  - G frees the mark word;
  - G does not depend on any language decision.
- C2 and C6 touch `src/qbe_rc*` and `native_rc*`, which G4/G5 also edit. Run them beside
  G2/G3 only; rebase them after G5.
- Keep the Lox port and the EDA app in every lane's gate; each WP report states their pass
  counts.

## 6. Evidence index

| What | Where |
|---|---|
| GC deletion probe (round 1: 85 errors; round 2: 185 errors in 72 files) | `mylang-worktrees/claude-gc-delete-probe/.tmp/round{1,2}.{patch,log}` (branch `claude/gc-delete-probe`, uncommitted, locked) |
| Hold census (instrumentation, scripts, raw JSON, summaries) | `claude/hold-census` at `1d3155f3`: `experiments/hold-census-20261003/{README.md,results,results-full}` |
| Pending-receiver and growth probes | session scratchpad `onecount/{pending,grow}.my` (reproduce from the snippet in 4.1) |
| Earlier GC-retirement draft (superseded by Part G) | `~/ai/canopy/evidence/eda-merge-review-20261002/agent1-merge-fixes-and-gc-retirement.md`, Part 2 |
| Two-count rationale and ABI4 results | `docs/audits/rc-future-performance-2026-09-28.md` §1; `docs/audits/wp-b3-layout-2026-09-29.md`; `experiments/wp-b3-layout-20260929/prefix/` |
| Independent fuzz model | `codex/differential-fuzz-20261002` commit `95dd7cdd` |
