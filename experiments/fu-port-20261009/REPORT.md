# FU-PORT: the F/U integration on `main` after the syntax redesign (2026-10-09)

**Who.** An opus-lane agent did the port. Its tool refused report files, so the coordinating Claude session wrote this file from the agent's final message, after checking the receipts:
- `logs/gate-1.log`: 91/91 steps, 2242 tests;
- `logs/gate-final.log`: 91/91 steps;
- `qualify-port-final/` and `main-conformance/`: both 1516/4/0;
- `fuzz50-port-migrated3/` and `fuzz50-main-migrated/`: qualified, 9/9 kinds.

**Where.** Branch `claude/fu-port`, head `24a48c29c`. It is `claude/fu-x`, `80f1d6ce5`, with `main` `e23651f6a` merged (`b0f5bee76`, no textual conflicts) and the migration added (`a46365913`). Not merged into `main`, not pushed.

**`main` moved on, and the port followed it.** `main` became `8a2fccd2f`, the frontend follow-through, 16 commits. The coordinator merged it into the port and ran the gates again (see "Re-merge" below). `main` was then fast-forwarded to `b51a43b76` on 2026-10-09.

## What the port did

**Optimized debug.** Since `76ac7370a`, `--optimize-debug` runs the release Core passes, so U1's and F2's passes now run there too.
- The facts are computed over the whole program before the per-module split, and cached units are keyed by their exact text.
- The lanes' passes have no release-only conditions.
- Both lanes' test files now also run every fixture under `--optimize-debug` and `--verify-facts --optimize-debug`. test-core passes 591/591.

**Migration to the new syntax** (`mylang fix` edits, plus hand edits):

| what | `mylang fix` | by hand |
|---|---:|---|
| `test/core/{u1,f2}_*.my` | 394 | 4 |
| sources embedded in the lane tests | 110 | 0 |
| Lox `ports/mylang` | 1,865 | 36 |
| EDA `src/` | 6,322 | see below |

- **Assertions.** They changed only where the redesign moved trap columns or dropped module prefixes. No program output changed.
- **EDA hand edits:**
  - `mylang.json` moved to `src/`;
  - `Unit` records renamed, because `Unit` is now built in;
  - byte-literal conditionals hoisted;
  - 17 `?` became `try`.

**Four `mylang fix` defects found in `main`:**
1. **It silently produces wrong answers.** It rewrote `int(s)` to `parse_int(s)` inside a function that is itself named `parse_int`, which made the function call itself without end.
2. Union-variant migration collides with the type-spelling edits and produces broken lines.
3. A nested comprehension comes out mangled.
4. Byte-literal conditional arms are typed as fixed arrays. This may be a checker issue rather than a fixer one.

## Gates (Debug compiler `01cd16a0…`; nothing under `src/` changed after `a46365913`)

| gate | result |
|---|---|
| Guardian, test (91/91), fmt-check | pass |
| `qualify_merge` | test-core 591 passed; conformance **1516/4/0** in debug and in release. `main` `e23651f6a`'s own compiler gives exactly the same result and the same 12 PROBLEM lines. The redesign renamed 2 tests and added 4 `tests/lang/frontend_*` files with no frozen reference. Those files pass on the port in every mode. |
| frozen fuzz 9×50 | The frozen generator writes old-syntax programs, which every compiler since the redesign rejects, `main`'s included. Through a `mylang fix` migrating wrapper (`tools/mylang-migrating`), all 9 kinds PASS for the port and for `main`. |
| Lox (migrated copy) | 974/974; port tests 65/65 |
| EDA (migrated copy) | 34/34 goldens; 310/310 tests |
| parity `.expected` | 45/45 |

## Does the timing carry over? Yes

**Emitted LLVM.** For 85 of 94 programs (44 of 45 parity, 41 of 47 rows), the port's code for the new-syntax source equals `fu-final-x`'s code for the old source. FU-X's CPU-10 timing therefore carries over unchanged.

**Where the code differs.** The rest differ only where the redesign changed codegen or sources:
- `list_filter`, `lox_eval`, `result_propagate`, `tagged_stack`: the port equals newest `main` exactly in the functions F/U leaves alone;
- `text_ops`'s `strings::repeat`;
- 104 Lox functions and 37 EDA functions, the same sets that differ between the two `main`s;
- `json_transform` and `union_find`, which `main` itself no longer builds.

**No lost change and no interaction:** nothing F/U leaves alone differs between the port and newest `main`, and no F/U change is lost.

**Instructions on CPU 8** (port ÷ newest `main`, against FU-X ÷ old `main`). They agree to within 0.1% in every targeted cell:

| cell | port ÷ main | FU-X ÷ old main |
|---|---:|---:|
| sort_quick | 0.758 | 0.757 |
| sieve | 0.743 | 0.739 |
| nbody | 0.693 | 0.693 |
| str_build | 0.483 | 0.482 |
| list_append_sum | 0.941 | 0.941 |
| Lox vm/fib | 0.832 | 0.832 |
| Lox vm/invocation | 0.885 | 0.885 |
| Lox vm/method_call | 0.858 | 0.858 |
| Lox vm/string_equality | 0.623 | 0.623 |
| Lox tree/equality, tree/invocation | 0.944, 0.976 | 0.944, 0.976 |
| EDA, 34 designs | 0.994 | 0.993 |

## For future timing

- **Migrated Lox copy:** `claude-main-ce/.mylang-cache/lox`. `ports/mylang-base` points at `main-e23651f6`.
- **Migrated EDA copy:** `claude-main-ce/.mylang-cache/eda-src`. Its `mylang.json` is in `src/`.
- **Compilers:** `.mylang-cache/compilers/port-a4636591` and `main-e23651f6`, both ReleaseFast.
- **Tools:** `experiments/fu-port-20261009/tools/` holds `fix_loop.py`, `mylang-migrating`, `llvm_identity.py`, `llvm_functions.py`, `instructions.py` and `outputs.py`.

## Re-merge with `main` `8a2fccd2f` (coordinator, 2026-10-09)

**Commits on `claude/fu-port`:**
- `a57541cc4`: merge of `main` `8a2fccd2f`. The merge was clean.
- `9e97801f6`: the gate driver, `tools/remerge-gates.sh`.
- `b51a43b76`: formatting fixes. `main`'s new `.my` formatting gate (`scripts/check_my_format.py`) wanted the nine U1 and F2 fixtures in canonical layout. `mylang fmt` removed only blank lines, 4 per file. F2's 14 asserted trap locations moved up by the removed lines, and `f2_index_test.zig` follows them.

`main` was fast-forwarded to `b51a43b76`. The receipts are in `logs/remerge/`, `qualify-remerge/` and `fuzz50-remerge/`:

| gate | result |
|---|---|
| `zig build test --summary all` | 94/94 steps, 2288 tests (`gate2.log`) |
| `.my` format and `fmt-check` | 761 checked, 0 failures (`fmt2.log`) |
| `qualify_merge` | conformance 1516/4/0 in debug and in release; the same four mismatches as `main`'s own |
| Lox | 974/974; port tests 65/65 |
| EDA | 34/34 goldens; 310/310 tests |
| parity `.expected` | 45/45 |
| frozen fuzz 9×50, through `tools/mylang-migrating` | all 9 kinds PASS |

**The first gate run failed only 2 of `tests/test_migrate_embedded.py`'s 12 tests** (`gate.log`, 91/94).
- They failed because that run's `TMPDIR` lay inside the worktree, and it affects `main` the same way.
- With `TMPDIR` outside the checkout, all 12 pass, which is what `gate2.log` shows.
- The tests were fixed on `claude/fix-embedded-tmpdir`.
