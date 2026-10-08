# CE2-A report: field effects (2026-10-08)

**Who wrote this file.** An opus-lane agent did the lane. Its tool refused report files,
so the coordinating Claude session wrote this file from the agent's final message. The
coordinator first checked these receipts:

| receipt | file |
|---|---|
| gate 88/88 steps, 2073 tests | `logs/gate.log` |
| qualified on source `52277f2c`; test-core 482/0/0; full conformance debug and release 1518/0/0 | `qualify-ce2a/` |
| fuzz: all 9 kinds qualified | `fuzz50-summary/` |
| Lox conformance: VM 246/246 and tree 241/241, in normal and gc-stress modes | `logs/lox-conformance.log` |
| Lox port tests 65 passed | `logs/lox-port-tests.log` |
| EDA tests 310 passed | `logs/eda-tests.log` |
| counting on and off: 0 cells differ (Lox 48, EDA 34, parity 4, rows 46) | `logs/run-final.log` |

**Where the work is.** Branch `claude/ce2-effects`, tip `8a1266215`, based on
`claude/copy-elim-2` `9f9667b1b` (main `3e210ffba` plus the CE2 plan). Nothing was merged or
pushed.

## Result: every exit target met

**Lox, bytes moved:**
- **All patterns:** 51.32 G → **12.30 G (−76.0%)**.
- **P2+P4:** 35.20 G → 1.95 G (−94.5%, against an exit of −70%).
- **The frame stores at `vm.my:433` and `:534`:** 22.2 G → **0** (exit: 2 G or less).
- **The named P2 sites:** about −100% (exit: −90%).

**Lox VM `fib(27)`:** 257.4 → **22.7 bytes per dispatch**.

**Other corpora:** EDA 3.47 G → 3.46 G, parity and the rows unchanged. CE2-A targeted Lox.

## Commits

| step | commit | what |
|---|---|---|
| 1 | `334c527ab` | New `src/core/effects.zig`: for each function and parameter, the field paths it may read and, for a `mut` parameter, may write. It is transitive over direct calls, a least fixed point over recursion, and treats indirect, `extern` and runtime calls as reading and writing everything. Results that answer `True` or `False` next to `mut` parameters also record each answer's writes and whether it is possible. `NEW-CORE-CE2-EFFECTS-1`. |
| 2 | `a2b5eaff9` | Per-field interference in `emit_homes.zig`. A `record_set` that shares its record's home writes only its field; an in-out call's final value writes only where the callee's summary says. Summaries are computed once per module (`emit_llvm.Analysis.effects`, `pipeline.zig`). `EFFECTS-2`. |
| 3+4 | `d61dab09f` | New `src/core/stores.zig`, run from `own.function` before copy-on-write (`own.Options.effects`, `passes.zig`). It removes dead element stores, sinks partly dead ones, and narrows element stores to the fields that changed. `EFFECTS-3`, `-4`. |
| 4b | `02eb7eb36` | `own.zig` store rule `takeThrough`: a write-back takes its field over from an earlier record through updates of other fields (`wb = it.rt; it.returned = pop(mut wb); it.rt = wb`), the shape of `interpreter.my:667` and `heap.my:106`. `EFFECTS-5`. |
| 4c | `6c89e2910` | A construction whose one use is a whole-element store in a later block is built straight into the element (`analyzeMemory`, `list_set` consumers). `EFFECTS-6`. |
| — | `c3bef3bd6`, `e9cb3d3ed` | Unused helpers removed; more tests (an "only answers False" summary, union elements). |
| fix | `3a7771f19` | `stores.zig` `replaceUse` rewrote a call's callee index when it equalled the replaced value's index, so a sunk store could retarget a call. The Lox `driver_tests` build found it: the Debug compiler's IR verifier, and a hang with ReleaseFast. All counts and gates were rerun after the fix; the loop test now has a call on the return path. |
| evidence | `52277f2cf`, `8a1266215` | Harness, tools and evidence (7.6 MB). |

## Bytes moved per pattern: CE-X final → CE2-A final

**Lox (24 cells)**

| pattern | CE-X final | CE2-A final | change |
|---|---:|---:|---:|
| P1 | 304.92 k | 304.92 k | 0 |
| P2 | 7.73 G | 9.22 M | −99.9% |
| P3 | 4.67 G | 4.67 G | 0 |
| P4 | 27.47 G | 1.94 G | −92.9% |
| P6 | 19.53 M | 19.53 M | 0 |
| P7 | 5.34 G | 6.40 M | −99.9% |
| P8 | 3.30 G | 2.85 G | −13.5% |
| P9 | 2.76 G | 2.76 G | 0 |
| P13 | 23.00 M | 23.36 M | +1.6% (noise) |
| **all** | 51.32 G | **12.30 G** | **−76.0%** |

**Lox all patterns, by step:**

| step | bytes |
|---|---:|
| CE-X final | 51.32 G |
| 2 | 44.19 G |
| 3+4 | 21.20 G |
| 4b | 15.28 G |
| 4c | 12.29 G |
| final | 12.30 G |

**EDA (34 designs):** 3.47 G → 3.46 G.
- P2: 1.37 M → 58 k.
- P8: −17%.
- P7: 2.11 G, unchanged. That is CE2-B's target.
- **P1: +1.31 MB.** This is a reclassification at one site. In `kicad_sch_compose::collect_field`, a 272-byte update is now in place (P2 −1.31 MB), but greedy coalescing then needs a loop-phi copy of the same bytes (P1 +1.31 MB). P1+P2 together go from 4.47 MB to 4.16 MB.
- **P11: +1.1 kB.** Harness noise: output paths are 2 characters longer in this worktree.

**Parity:** unchanged at 154.91 M. **The rows:** unchanged at 875.07 M.

**About Lox P13.** It is realloc moves, which depend on heap layout. A rerun of the unchanged base compiler gave −4.0% against CE-X's own numbers, so the +1.6% is within that noise.

## Targets (Lox)

| site | CE-X final | CE2-A final |
|---|---:|---:|
| P4 `vm.my:433` | 11.09 G | 0 |
| P4 `vm.my:534` | 11.09 G | 0 |
| P2 `vm.my:254` | 3.56 G | 0 |
| P2 `interpreter.my:667` | 2.96 G | 0 |
| P2 `heap.my:106` | 1.19 G | 7 k |
| P4 `vm.my:135` | 815 M | 444 M (only the 48-byte `function` field is copied now) |
| P4 `heap.my:210` | 587 M | 0 |
| P4 `heap.my:124` | 1.50 G | 1.50 G (a by-value `Obj` parameter stored into the list) |

**What happens to the dispatch loop now:**
- The end-of-step store (`:534`) is sunk onto the return path only. The loop path keeps only its bounds check.
- The step's first store (`:433`) is sunk into the handlers that need it. Where it remains, it stores only `frame.ip`.
- The stores before `call_value`, `invoke` and `invoke_from_class` are narrowed to `ip`.

**What remains per dispatch on `fib(27)`:** 22.7 bytes, of which:
- P3: 14.7 bytes, the frame reloads at `vm.my:503` and `:525`;
- P8: 4.0 bytes;
- P4: 4.0 bytes.

## Observation points

**Dead and sunk stores (step 3).** The element is observed by:
- any element read of the list, except a read nothing uses, which is only a bounds check;
- a `return`;
- a call whose summary's reads overlap the list's path;
- an `extern`, runtime or indirect call;
- storing the list into a record that is not put back, a construction, or another list;
- any other use.

A store at the same element (same raw index, same list length) ends the walk.

**A trap is not an observation point.**
- Traps end the process: `myl_core_trap` exits through `os_exit`.
- Test trials run in forked children (`NEW-CORE-TEST-BATCH-1`), so the parent's state never sees a trial's stores. Nothing in-process catches a trap.
- A trap's report names only the site, the index and the length, never element contents.
- A removed store keeps its bounds check where it was, so an out-of-range index traps at the same place with the same message. This is tested.

**Narrowing (step 4).** The proof walks the stored value back to where it was read or last stored:
- through record updates, and through `mut` calls by their write summaries;
- along each phi edge, under the branch conditions that lead to it.

A call that answered `True` contributes only its "returns `True`" writes. That keeps Lox's error paths, where `runtime_error` resets `frame_count`, off the loop path.

## Gates

**Source.** The code is at `3a7771f19`.
- `fuzz_matrix.py` needs a clean tree, so its summary records `52277f2c`; the compiler source is identical.
- `qualify_merge` refused the usual evidence name, because the previous wave left a temporary directory in this worktree's cache. It ran under `qualify-ce2a`.

| gate | result |
|---|---|
| `zig build` (Guardian) | 88/88 checks on every commit |
| `zig build test --summary all` | 88/88 steps, 2073 tests passed |
| `zig build fmt-check` | exit 0 |
| `qualify_merge.py --shards 64` | qualified; test-core 482/0/0; full conformance with leak and fact verification: **debug 1518/0/0, release 1518/0/0** |
| frozen fuzz 9×50 | all 9 kinds pass |
| Lox conformance, both engines, normal and gc-stress | **974/974** |
| Lox port tests | **65/65** |
| EDA goldens | 34/34 byte-identical |
| EDA `mylang test src` | **310/310** |
| EDA built with the Debug compiler (IR verifier on), debug and release | no errors |
| parity | 4/4 equal to `.expected` |
| counting on against off | identical on all 132 cells |

## Tests

`src/core/ce2_effects_test.zig` (`// spec: NEW-CORE-CE2-EFFECTS-1..6`, six `SPEC.md` bullets) and
the fixture `test/core/ce2_effects.my`. The fixture runs in debug, release and `--verify-facts`
under the leak check, against the base compiler's output.

They cover:
- `break`, `continue` and early returns;
- frames read through callees: a trace, an error report that resets the count, an indirect call;
- a list that grows or is replaced between load and store;
- calls that push frames;
- counted fields, changed and unchanged;
- nested records;
- unions: a payload stored back, a case replaced;
- a callee that writes the very field a view holds, and one that writes a disjoint field;
- recursion and mutual recursion in the summaries;
- a trap on an element read, and a store whose index runs past the list;
- write-backs where the record is copied, or read by a call, in between.

## Touches outside the lane's areas (for the merge)

**`own.zig`:**
- new `takeThrough` and `clearThrough`, which extend `takeFields`;
- `Options.effects`;
- `run` computes the summaries when none are given.

**`emit_llvm.zig`:**
- `analyzeMemory`'s fusion test, one condition for `list_set` consumers;
- `Analysis.effects`, which `render` computes when it is null;
- `emit_homes.plan` receives the summaries.

CE2-B's call, return and parameter lowering is unchanged. In-out passing now follows `homes.holds` more often, because interference is per field.

**Elsewhere:**
- `passes.zig` and `pipeline.zig` compute the summaries;
- `effects.usersOf` is public.

**Tests outside the lane's own files:**
- `test/core/counters.my`: `bump` now copies through a by-value call, because its old shape is narrowed and copies nothing.
- `src/core/count_test.zig`: one assertion now names `bumped`.

**Overlap with CE2-B:**
- Step 2 also removed most Lox P7 (5.34 G → 6 M), including `vm.my:264`, `:268` and `interpreter.my:668`, because final values now share their argument's home.
- Narrowing skips stores paired with a read that took the slot's owner (`flags.transferredSlot`), so `xs[i].items.append(v)` stays CE2-B's. Not skipping them caused a double free (`m_list_methods`), which the full test-core run caught.
- `heap::sweep`'s store at `heap.my:363` is now built in the element. Its P3 reads (`:361`, `:362`) are CE2-B's.

## Remaining limits

- **`heap.my:124`** (1.5 GB) stores a by-value `Obj` parameter into the list. The copy is needed unless the caller builds it in place.
- **Frame reloads** at `vm.my:503` and `:525` (P3, 1.5 GB). This is CE2-B's area.
- **One EDA P1/P2 reclassification** caused by greedy coalescing order.
- **Budgets:**
  - 20,000 proof steps per store;
  - sinking only into single-predecessor successors;
  - index identity only through record-field or value indices plus a constant.
- **Narrowing covers record elements only.** Union elements gain only from the cross-block construction step.
- **Compile time was not measured.** Summaries are computed once per pass run and once per emission.

**Top 10 sites still copying, all corpora:**
1. Lox P9 `table.my:84`: 1.85 G
2. Lox P8 `interpreter.my:346`: 1.84 G
3. Lox P3 `heap.my:361`: 1.51 G
4. Lox P3 `heap.my:362`: 1.51 G
5. Lox P4 `heap.my:124`: 1.50 G
6. Lox P3 `vm.my:525`: 815 M
7. Lox P3 `vm.my:503`: 661 M
8. EDA P7 `sexpr_tokenizer.my:270`: 583 M
9. Lox P8 `interpreter.my:265`: 519 M
10. Lox P9 `compiler.my:153`: 486 M
