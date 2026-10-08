# CE2-B report: results and arguments in place (2026-10-08)

**Who wrote this file.** An opus-lane agent did the lane. Its tool refused report files,
so the coordinating Claude session wrote this file from the agent's final message. The
coordinator first checked these receipts:

| receipt | where |
|---|---|
| gate 88/88 steps, 2067 tests | `logs/gate.log` |
| qualified on source `21cb7759`; test-core 483/0/0; full conformance debug and release 1518/0/0 | `qualify-ce2b/` |
| fuzz 9×50 qualified on `21cb7759`, `source_unchanged` | `fuzz50-summary/matrix.json` |
| Lox conformance: VM 246/246 and tree 241/241, normal and gc-stress | `logs/lox-conformance.log` |
| Lox port tests 65 passed | `logs/lox-port-tests.log` |
| EDA tests 310 passed | `logs/eda-tests.log` |
| counting on and off: 0 cells differ, 0 EDA golden mismatches, parity matches `.expected` | `logs/run-final.log` |

**Where the work is.** Branch `claude/ce2-results`, tip `e8b009514`, based on
`claude/copy-elim-2` `9f9667b1b`. Nothing was merged or pushed. The evidence is 3.5 MB.

## Exit status

| exit item | result |
|---|---|
| EDA total ≤ 1.5 GB (CE-X: 3.47 GB) | **met: 1.08 GB (−68.8%)** |
| EDA `sexpr_*` P7 −90% | **met: 2.10 GB → 0** |
| `heap::sweep` P3 −90% | **met: 3.02 GB → 0** (`heap.my:361`, `:362`) |
| rows `record_pass` P1 −90% | **met: 363 MB → 0** |
| Lox P7 at `vm.my:264`/`:268`, `interpreter.my:668` −90% | **not in this lane.** These copies are not declared results but in-out final moves paired with CE2-A's P2 copies, which CE2-A removes (see below). |
| EDA P6 at `sexpr_parser.my:225` −90% | **not met: step 4 not implemented,** because it is unsafe in the current ABI (see below) |
| no other pattern up | met; two small rises are measurement artifacts |
| every gate | all pass on `21cb77595` |

## A wrong answer on `main`, fixed in step 1

```mylang
def pick(k: int, flag: bool) -> Pair:
    w = make_pair(k)
    if flag:
        return w
    return Pair(x=w.y, y=w.x)
```

`w` lives in `%ret` because one path returns it whole. The swapped return stored `w.y` over
`w.x` before reading `w.x`. CE-X's compiler printed `p.y = (10 … 14)`, while the pre-CE compiler
`65a14aeb` prints `(1 … 5)`.

Step 1 checks every `ret`'s stores against the values living in `%ret`. A `ret` that would
overwrite a value it still reads builds its result in a temporary first (`Plan.staged`).
NEW-CORE-CE2-RESULTS-2.

The coordinator put a conservative hotfix for the same bug on `main` (`1edeef830`,
NEW-CORE-CE-RECORDS-6). It stages every `ret` in a function whose `%ret` holds another value.
This lane's precise version replaces it at the merge.

## Commits

| step | commit | what |
|---|---|---|
| 1 | `4a72931e7` | A value that a `ret` stores inside the returned value (or the value a view of it lies in) gets a home at that place in `%ret`. It must fit, share no bytes with a value in `%ret` it clashes with, and no `ret` may overwrite it before reading it. Code: `emit_homes.zig` (`Home.ret_at`, `retStores`, `Planner.buildInRet`) and `emit_llvm.zig` (`storeAtRet`, staged returns). NEW-CORE-CE2-RESULTS-1..3. |
| 2 | `1609c84a4` | A list element over four words is passed to calls where it lies, as its slot's address. Conditions: its uses are in its own block and are by-value arguments of internal calls, part loads or retains; the calls take no `mut` parameter that holds a block; and nothing in between writes, frees or moves a list. Code: `emit_llvm.zig` (`lentElements`, `lendable`, `lendsTo`, `keepsLists`) and one line of `emit_homes.classify`. NEW-CORE-CE2-RESULTS-4. |
| 3 | `29820c9a0` | `sret` sharing. A callee that has nothing living in `%ret` before a `ret`, and no `ret` that reads its parameter after overwriting it, is emitted without `noalias` on that parameter and on `%ret`. Direct same-unit calls then treat that argument like an in-out one, so `s = advance(s, x)` shares one home. Code: `Planner.shareable`, `planMemory`, `sharedCalls`, `sharedArgument`, `shareCandidate`, `defineLine`. NEW-CORE-CE2-RESULTS-5. |
| 4 | — | not implemented |
| 5 | `e59e40d08` | `own.zig`: a field taken for a `mut` call survives a call that only borrows the record, when that call runs in the read's block before every use of the taken value (`Taking.borrowsFirst`). NEW-CORE-CE2-RESULTS-6. |
| 6 | `a7d78b685` | `xs[i].items.append(v)`, `.pop()` and `xs[i].items[j] = v` become a transferred `list_get_field` followed by a `list_set_field` that releases nothing. Code: `elements.zig` `rewriteFieldUpdate`, and the `flags.zig` transfer marks. NEW-CORE-CE2-RESULTS-7. |
| tests | `2c8eb96b9`, `21cb77595` | `?` propagation; a callee that may not share. CE-B's test that expected `xs[i].tags.append` to stay a whole-element store now expects one `list_set_field`. |
| evidence | `e8b009514` | Counters, tables and gate receipts. |

## Bytes moved per pattern: CE-X final → CE2-B final

**Lox (24 cells):** 51.32 G → **46.35 G (−9.7%)**.
- P3: 4.67 G → 1.66 G (−64.5%).
- P9: 2.76 G → 1.07 G (−61.5%).
- P8: −7.4%.
- P2, P4 and P7 are unchanged; they are CE2-A's.
- P13: +1.1%, noise.

**EDA (34 designs):** 3.47 G → **1.08 G (−68.8%)**.
- P7: 2.11 G → 2.63 M.
- P3: 673.58 M → 397.98 M (−40.9%).
- P6: 477.60 M, unchanged.
- P11: +1,080 B, an artifact.

**Parity:** unchanged at 154.91 M.

**Rows:** 875.07 M → **512.13 M (−41.5%)**.
- P1: 362.94 M → 0.
- P9, P13 and P14 are unchanged.

**Totals after each step:**

| after step | Lox | EDA | rows |
|---|---:|---:|---:|
| 1 | 51.31 G | 1.36 G | 875 M |
| 2 | 48.05 G | 1.08 G | 875 M |
| 3 | 48.05 G | 1.08 G | 512 M |
| 5 | 46.35 G | 1.08 G | 512 M |
| 6 | 46.35 G | 1.08 G | 512 M |

**Target sites:**

| site | before | after |
|---|---:|---:|
| EDA P7 `sexpr_tokenizer.my`, all sites | 1.33 G | 0 |
| EDA P7 `sexpr_parser.my`, all sites | 769.61 M | 0 |
| Lox P3 `heap.my:361` | 1.51 G | 0 |
| Lox P3 `heap.my:362` | 1.51 G | 0 |
| rows P1 `row_record_pass.my:48` | 362.94 M | 0 |
| Lox P9 `table.my:84` | 1.85 G | 154.03 M (−91.7%) |
| Lox P7 `vm.my:264` / `:268` / `interpreter.my:668` | 1.11 / 2.45 / 1.77 G | unchanged (CE2-A's) |
| EDA P6 `sexpr_parser.my:225` | 444.83 M | 444.83 M |

**Highlights:**
- **EDA rds3+flat:** 238.96 M → 103.34 M (−56.8%).
- **EDA `sexpr_*` functions:** `next`, `next_in`, `next_token`, `parse_node`, `read_atom`, `read_number` and `read_string` all go to 0. `parse_list` is unchanged at 476 M (P6 + P13).

**The two rises are artifacts.**
- **Lox P13** is at `heap.my:66`, a `realloc` move that depends on heap layout. CE-X's own binary gave 70,592 and then 201,696 bytes on two runs (`logs/p13-noise.txt`).
- **EDA P11** is `support_strs::path_join`, copying output paths that are two characters longer in this worktree.

## Why the Lox P7 targets did not move in this lane

These copies are in-out final moves, not declared results.
- **`read_constant`:** its `Value` is two words and returns in registers. The 88-byte copy at its `ret` is `frame`'s final value, moved back from the copy that `read_byte(mut frame)` had to receive because a view of `frame.function` is read after the call. Interference is per value in this lane.
- **`interpreter::execute`:** the same pattern, 296 bytes.
- **The pairing:** each P7 copy pairs with one of CE2-A's P2 targets with equal bytes. CE2-A's final counts show 0 at `vm.my:254`, `:264`, `:268` and `interpreter.my:667`, `:668`, so these fall at the merge. CE2-X should confirm it.

## Step 4 (EDA P6) was not implemented

- **The copy:** `children.append(child)` pushes `child`, the `Ok` payload view at `X+8` of `parse_node`'s `sret` result `X`.
- **The layout:** `X` is 144 bytes: the 56-byte `Result`, the 56-byte tokenizer final value, and the 32-byte diagnostic.
- **Why building in the slot fails:** it would put `X`'s tag word over the previous element's last word (or the list header), and `X`'s other fields past the slot.
- **What a safe form needs:** a new ABI that passes a union payload's destination separately from its tag, for every function returning a union with a payload over four words, with every caller and indirect call. It also needs the list reserve and its copy-on-write test moved ahead of the call.
- **Every other P6 site** in the corpora pushes a by-value parameter or an `Option` payload already in the caller's memory. Constructions pushed directly were already built in the slot by CE-A.

## Step 5: what shared `table::set`'s list

- **The main cause** was `heap::set_global`:

  ```mylang
  __wb = rt.globals
  table.set(mut __wb, name, string_hash(rt, name), item)
  rt.globals = __wb
  ```

  `string_hash` borrows `rt` after the read, so `own.zig` retained the field instead of taking it, and every `set` copied the entries list (625,006 copies in `strings/vm`). This is fixed: 1.85 G → 154 M.
- **The remaining 154 M:** `vm::set_property` and the interpreter's field sets copy an instance out of `rt.objects`. The element keeps sharing the fields table, and `string_hash(rt, …)` and `peek(rt, …)` read `rt.objects` in between. Removing that copy needs effect summaries, not a copy-on-write decision.
- **Other Lox P9 sites are genuinely shared:** `emit_byte` (the chunk lives in both `p.compilers` and `rt.objects`, 486 M), `set_env_slot` (182 M) and `resolve_expr` (238 M).

## Step 6

No corpus site uses this shape on a list element:
- EDA's `units[unit].pins.append` is a dictionary element;
- Lox's `locals.pop()` copies only 792 B in total.

The fixture covers it: 300 appends across growth, a shared list, a kept field, and pops.

`xs[i].seen[k] = v`, a dictionary update on an element's field, still copies the element.

## Gates (all on `21cb77595`)

| gate | result |
|---|---|
| `zig build` (Guardian) | 88 checks; the whole-tree check passes on every commit hook |
| `zig build test --summary all` | **88/88 steps**, 2067 tests passed |
| `zig build fmt-check` | exit 0 |
| `qualify_merge.py --shards 64` | qualified: test-core **483/0/0**; full conformance with `--leakcheck --verify`: **debug 1518/0/0, release 1518/0/0** |
| frozen fuzz 9×50 | **qualified**: all 9 kinds, 6,450 comparisons, 0 mismatches, `source_unchanged` |
| Lox conformance, both engines, normal and gc-stress | **974/974** |
| Lox port tests | **65/65** |
| EDA `mylang test src` | **310/310** |
| EDA goldens | **34/34**, counting and plain builds |
| parity `.expected` | **4/4** |
| counting on against off | identical on all 132 cells |

**Process notes:**
- **An earlier full gate** on `2c8eb96b9` failed exactly one test: CE-B's assertion that `xs[i].tags.append` is not a field store, which step 6 deliberately changes. `21cb77595` updated that test, and the rerun is green. The old log is at `.mylang-cache/ce2/old-evidence/gate-run1.log`.
- **The first fuzz run** reported "not qualified" only because a tracked test file was edited while it ran; every kind passed. It was rerun on the clean final commit.
- **The first qualify attempt** collided with a stale temp directory from an earlier lane. That directory was removed, and the run used the evidence name `qualify-ce2b`.
- **Compiler for the Lox, EDA and parity runs:** the step-6 ReleaseFast compiler. Only tests and SPEC text changed after it.

## Tests

`src/core/ce2_results_test.zig` (NEW-CORE-CE2-RESULTS-1..7, with `SPEC.md` bullets) and
`test/core/ce2_results.my`. They run in debug, release and release `--verify-facts` under the
leak check, plus a trap run, against the pre-CE compiler's (`65a14aeb`) outputs.

**Results built in `%ret`:**
- early returns of other shapes, and `Err` paths;
- `?` propagation;
- a payload returned again under another error type;
- snapshots of a `mut` cursor;
- swaps and duplicated halves next to a `mut` record;
- a value rebuilt while an earlier one is still read;
- a result carried around a loop with an early `Err`;
- the CE-A swap bug;
- a trap between building the result and returning it.

**Lent elements:**
- `is_free(objs[i])` and `cost(objs[i])`;
- `grow(mut h, h.items[0])`, which must copy;
- a callee that writes its by-value parameter;
- a slot overwritten before the call;
- a shared list.

**`sret` sharing:**
- a rotate loop, which shares;
- `flip` and `swap`, which must not share;
- `keep_x`, which may share;
- `bumped`, which does not share;
- an argument still live after the call;
- `both(s, s)`;
- an indirect call through a list of function values.

**`table::set`:**
- a borrowing call before the `mut` call;
- a borrowing call that keeps the table;
- a read after the `mut` call;
- a snapshot taken before the first update.

**Element-field containers:**
- appends across growth;
- pops;
- a shared list;
- a kept field.

## Touches outside the lane's areas (for the merge)

**`emit_homes.zig`** (CE2-A owns interference):
- `Input.results`, `Plan.stage`, `Plan.shared` and `Home.ret_at`;
- `classify` skips lent elements (one line);
- `plan` calls `buildInRet` and `shareable` after `embed`.

**Integration caution:** `clash` and `disjointInRet` assume `interferes` stays at least
per-value conservative between two different classes that overlap in `%ret`. If CE2-A's
per-field interference relaxed `interferes` itself, the `%ret` overlap check must keep the
per-value form.

**`emit_llvm.zig`:**
- `listSetField`: one line skips hold/release when `flags.transferredSlot` applies;
- `analyzeMemory` was split into `prepareMemory`, `planMemory` and `nameHomes`;
- the `define` line is printed after planning (`defineLine`), so a shareable callee can drop `noalias`.

**`own.zig`:** `takeReplaced` calls `borrowsFirst`.

**CE-B's files:**
- `elements.zig`: `rewriteFieldUpdate`;
- `flags.zig`: transfer marks for `list_get_field`/`list_set_field`;
- one expectation in `ce_lists_test.zig`.

## Remaining limits

1. **EDA P6 (445 M):** see "Step 4".
2. **Lox P7 (5.3 G):** in-out final moves paired with CE2-A's P2 copies; they should vanish at the merge.
3. **Lox P9 (1.07 G):** data really shared between a local and an element of `rt.objects` or `p.compilers`.
4. **Lent elements need every use in the read's block.** A `for x in xs:` body that uses `x` across blocks still copies, which is most of EDA's remaining 398 M of P3.
5. **`sret` sharing** applies only to callees with nothing living in `%ret` before a `ret` and no in-out parameter, called directly from the same unit. A sharing callee never shares with its own callees.
6. **Element-field containers:** one field deep, list elements only. Dictionary elements and `xs[i].seen[k] = v` still copy.
7. **Staged returns** add a temporary and one copy, only in functions that have the CE-A bug's shape.

**Kept on disk, not committed:**
- `.mylang-cache/ce2/prefix-step6/bin/mylang` (the final ReleaseFast compiler);
- `.mylang-cache/ce2/fuzz-compiler/mylang` (the Debug compiler, sha256 `7f5d71a9…`);
- `.mylang-cache/ce2/fuzz50-full` (16 MB);
- `.mylang-cache/ce2/raw-steps`.
