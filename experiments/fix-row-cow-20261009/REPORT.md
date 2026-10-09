# Fix: a shared row written through a nested loop store (2026-10-09)

**Who wrote this file.** An opus-lane agent made the fix. The coordinating Claude session wrote this file from the agent's final report, after checking the gate receipts:
- `gates/zig-build-test-beb95a978-rerun.log`: 88/88 steps, 2098 tests.
- `qualify-beb95a978/summary.json`: qualified on `beb95a978`. Conformance 1518/0/0 in debug and in release.
- `fuzz-beb95a978/matrix.json`: qualified and complete; all 9 kinds pass.
- `shapes-after.txt`: 78 of 78 runs correct.

**Where.** Branch `claude/fix-row-cow`, based on `main` `cafe7fea7`.

| commit | what |
|---|---|
| `0054e1097` | brief and repros |
| `5b6f20d41` | the fix, tests and SPEC bullets |
| `beb95a978` | moves the guest tests to `test/core` |
| `9a3c4c46b` | gate receipts and performance evidence |

## The bug

```python
b = [[1, 2], [3, 4]]
kb = b[1]
for i in range(2):
    b[i][0] = 7
# kb[0] became 7; it must stay 3
```

The same happens with a `mut list[list[...]]` callee that is inlined into a loop-shaped caller, which is why `b.my` and `d.my` were wrong only in release. Verify builds already trapped `R_CORE_FACT`, so the fact verification was right and the premise was wrong.

## Root cause

The bug is in `exclusiveChildren` in `src/core/own.zig`. It was added in S4 commit `d5d4cbb40` (2026-10-06), before the S5 merge `5a6b501d`, so every new-core build on `main` has it.

For `b[i][j] = v`, the builder detaches `b`, takes row `i` out of it, updates the row, and stores it back. `staticallyUnique` runs the row update in place, with no count test, whenever `exclusiveChildren` says the fresh outer list's rows are unique. That proof missed two ways a row gets a second owner:

1. **A promoted row read.** The check was `class == .owned`. A borrowed read that ownership promotes to its own count (`kb = b[1]`, kept across the loop) has class `borrowed` with `promoted = true`, so it passed.
2. **A push or store into an outer list that may be shared.** With `snap = b; b.append(row)`, the push copies `b`, and the copy shares every row with `snap`. The walk followed the push without checking that it ran in place.

## Fix

- **Promoted reads:** `a.counted(...)` now blocks the proof for an owned *or* promoted read (NEW-CORE-ROW-COW-1).
- **Push and store links:** each must have run in place. Its list must be counted, not live after the update, and `staticallyUnique` at the update (NEW-CORE-ROW-COW-2).

No language decision was needed.

## Sibling shapes

- **The programs:** 26 shape programs, in `shapes/`, each run in debug, release and verify.
- **Base:** 37 of 78 runs correct.
- **Fix:** 78 of 78 correct.
- **Which shapes were wrong before:**
  - aliases before the loop, through callees, and through inlined `mut` parameters;
  - `xs[i].append(v)` and `xs[i][j] += v`;
  - comprehension-built and appended lists;
  - `while` loops, `break` and `continue`;
  - text, bool and float rows;
  - three levels of nesting;
  - an outer list shared while it is built.
- **Already correct before:** records with list fields, `d[k][j]`, aliases created in another iteration, and slices.
- **Per-run detail:** `shapes-before.txt` and `shapes-after.txt`.

## Performance

**Nothing changes where no alias exists.**
- The LLVM text and the executables are byte-identical to base for all 45 parity programs (release and debug, 90 of 90), Lox and EDA.
- matmul's `c` still gets 20 in-place updates and 0 tests.
- `perf stat` on CPU 8 gives instructions 1.0000 on all 53 cells. Cycles are 0.993–1.013, which is noise between identical binaries.

**Where a row really is retained,** the update now runs a count test and copies the row when it is shared. That is the cost of the correct answer.

## Tests

- **`src/core/row_cow_test.zig`:**
  - two IR tests, at debug ownership and after the release passes;
  - one end-to-end test: `test/core/row_cow.my` against `row_cow.expected` in three modes under the leak check, plus 8 guest tests in `test/core/v_row_cow.my`.
- **All three fail without the fix.**
- **Spec:** NEW-CORE-ROW-COW-1 and -2.

## Gate receipts (on `beb95a978`)

| gate | result |
|---|---|
| Guardian | 88/88 |
| `zig build test --summary all -Dtest-rerun=true` | 88/88 steps, 2098 tests |
| `fmt-check` | pass |
| `qualify_merge` | qualified: test-core 507/0; conformance 1518/0/0 in debug and in release |
| fuzz 9×50 | all 9 kinds pass |
| Lox | 974/974; port tests 65/65 |
| EDA | 34/34 goldens, counting on and off; 310/310 tests |
| parity | 45/45 equal `.expected` |

## Limits and open points

- **The guest tests are in `test/core`, not `tests/lang`.** `qualify_merge` reports PROBLEM for a `tests/lang` file without a frozen S5 reference.
- **The proof ignores position.** A promoted read anywhere in the function disables the untested update for that outer list. No benchmark is affected.
- **Two gate runs each failed one step, both outside this change:**
  - The CLI property test timed out at 209 s while the fuzz matrix shared the machine. It passes alone.
  - **The Debug compiler segfaulted once** in `facts.shape`'s `@memset(order, …)` (`src/core/facts.zig:220`), reached from `fuse_text_split` during `mylang test tests/ported --release --verify-facts`. This runs before ownership. Reruns passed, and the cause is unknown. A crash in `@memset` of a freshly allocated slice suggests memory corruption, so it needs its own investigation.
