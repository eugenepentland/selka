You are fixing a **wrong-answer bug** in mylang's new compiler core: a write to an element of a shared inner list, inside a loop, changes another variable that shares that inner list. Value semantics forbid that. Work autonomously to the exit, then stop and report.

## Where everything is

- **Your worktree** (locked, yours alone): `/home/epentland/ai/canopy/mylang-worktrees/claude-main-ce`, branch `claude/fix-row-cow`, based on `main` `cafe7fea7`. It has warm caches from an earlier wave; treat `.mylang-cache/` as stale. Do all work and builds here. Read other worktrees only.
- **Read first:** `CLAUDE.md`, then the repros in this directory (`experiments/fix-row-cow-20261009/`).

## The bug

`f.my` (debug and release give the same output):

```python
def main(out: Stream) -> int:
    a = [[1, 2], [3, 4]]
    ka = a[1]
    a[1][0] = a[1][0] * 2
    out.print("readwrite-const", a[1][0], ka[0])     # 6 3   correct
    b = [[1, 2], [3, 4]]
    kb = b[1]
    for i in range(2):
        b[i][0] = 7
    out.print("loop-write", b[1][0], kb[0])          # 7 7   WRONG, must be 7 3
    c = [[1, 2], [3, 4]]
    kc = c[1]
    for i in range(2):
        c[i][0] = c[i][0] * 2
    out.print("loop-readwrite", c[1][0], kc[0])      # 6 6   WRONG, must be 6 3
    d = [[1, 2], [3, 4]]
    kd = d[1]
    i = 1
    d[i][0] = d[i][0] + 10
    out.print("var-readwrite", d[1][0], kd[0])       # 13 3  correct
    return 0
```

**The other repros:**
- `c.my`: the float form of the loop write. Prints `8.0 8.0` in debug and release; it must print `8.0 4.0`.
- `b.my`: the same loop inside a `scale(c: mut list[list[float]], n: int)` callee.
  - Correct in debug (`8.0 4.0`).
  - Wrong in release (`8.0 8.0`), where `scale` is inlined into `main`.
  - Lane F1 found this one.
- `d.my`: `b.my` with two calls. It prints `16.0 16.0` in release; it must print `16.0 4.0`.

**What is known:**
- The direct loop form is wrong in every new-core compiler the coordinator tried, back to the S5 merge (`5a6b501d`). So it is not caused by the copy-elimination waves (CE, CE2) or by lane F1.
- Constant or straight-line indexes are correct; only loops are wrong.

**Likely area:**
- `src/core/own.zig` (uniqueness and copy-on-write decisions, and `withParametersCounted` after inlining);
- loop-related rules that hoist or drop the uniqueness test on the inner list: slice loops, `elements.zig`, `stores.zig`, `fuse*.zig`, `facts.zig`'s list facts;
- whatever proves the rows of a locally built list unique.

The rule must account for an element having been read out and retained (`ka = a[1]` gives the row a count of 2) before the loop. Find the actual cause and fix it at the source.

## Exit

1. **Every repro prints the correct output** in debug, release and release with `--verify-facts`, under the leak check. Add them as regression tests.
2. **Search for siblings, and fix or prove each one.** Write adversarial tests for related shapes:
   - the aliased element read out before the loop, inside the loop, or through a `mut` callee;
   - `xs[i][j] = v`, `xs[i].field = v`, `xs[i].items[j] = v`, `xs[i].append(v)`, `xs[i] += …`;
   - `d[k][j] = v`, and records holding lists;
   - comprehension-built lists, lists filled by `append`, and `mut` parameters, inlined and not;
   - nested loops, `while` loops, `break`/`continue`, and early return;
   - the alias created in a different iteration;
   - text and bool lists.

   Run each in debug and release. Report every shape tried and its result, before and after.
3. **No performance regression from the fix where no alias exists.** The fix must still prove the rows unique when nothing retained one; matmul's `c` is the key case.
   - Measure instructions and cycles on all 45 parity programs. Also measure the 4 Lox cells and 2 EDA designs that wave PM used: `experiments/parity-measure-20261008/tools/prof.sh`, and lane F1's tools at `/home/epentland/ai/canopy/mylang-worktrees/claude-ce2-results/experiments/f1-facts-20261009/tools/` (`parity.py`, `lane.py`).
   - Use `perf stat` on CPU 8, interleaved with the base.
   - Report any program above 1.01× in instructions, with the reason.
4. **Every gate passes** (below).

## Gates (every one must pass on your final commit)

A wrong answer is never acceptable.
1. **Build and repository gates:** `zig build` (Guardian), `zig build test --summary all` and `zig build fmt-check`.
2. **Conformance** against the frozen S5 references, debug and release, with leak and fact verification: **1518/0/0**.
   - Run `python3 experiments/new-core-s5-20261007/tools/qualify_merge.py --shards 64 --compiler zig-out/bin/mylang --install install --evidence <a fresh directory inside experiments/>`.
   - Never reuse an evidence basename.
   - Move that evidence under your evidence directory afterwards.
3. **Frozen fuzz 9×50:** `experiments/new-core-s5-20261007/tools/fuzz_matrix.py --references experiments/new-core-s5-20261007/references/fuzz-v1.json.gz --new <a copy of your Debug zig-out/bin/mylang> --cases 50 --evidence <dir below experiments/> --jobs 3`. All 9 kinds PASS. It needs a clean tracked tree.
4. **Lox:**
   - Copy `/home/epentland/ai/canopy/mylang-worktrees/claude-copy-elim/.mylang-cache/lox` into your `.mylang-cache/lox`, without its `.tmp/`, then create `.tmp/lox-bench/tmp` in your worktree root.
   - `python3 harness/lox_bench.py conformance --binary <your plain release lox binary> --engine both --stress -j 4` from your Lox copy: **974/974**.
   - The port's own tests, `mylang test .` in `ports/mylang`: **65/65**.
5. **EDA:**
   - Copy `/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore/mylang` into `.mylang-cache/eda-src`.
   - All 34 cases' outputs byte-identical to the goldens.
   - `mylang test src --jobs 4 --max-frames 30000 --max-steps 4000000000 --max-memory 2G --cache-dir <yours>`: **310/310**.
6. **Parity:** every program's output equals its `.expected`.

**Guardian rules:**
- every behavioural line under `src/` needs a test with `// spec: TAG` and a `SPEC.md` bullet; use `NEW-CORE-ROW-COW-*`;
- at most 7 struct fields and 6 parameters;
- `///` on every `pub` declaration;
- no import cycles;
- no type-size ratchet growth.

## Rules

- **Builds** go through `scripts/build-slot.sh`. The machine is shared with another agent (lane S1); at most four build-heavy processes in total.
- **CPUs:** never run heavy work on CPUs 2, 3, 10 or 11 (use `taskset -c 0,1,4-9,12-19`). Take perf measurements only on CPU 8, and never take wall time on CPU 10.
- **Caches and `TMPDIR`** stay inside your worktree, never in `/tmp`.
- **Never end your turn to wait for background work.** Run long steps in the foreground, with a timeout of up to 600000 ms, and split anything longer.
- **Never kill processes by pattern** (`pkill -f`). Kill only PIDs you started.
- **Evidence** goes in `experiments/fix-row-cow-20261009/`. Keep it under 10 MB.
- **Commits** go on `claude/fix-row-cow`, with messages ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never merge into `main`, never push, and never touch another worktree or branch.
- **Stop and report** if:
  - the fix needs a language-level decision;
  - Guardian needs a ratchet acceptance;
  - a gate fails for a reason outside your change.
- **Your final reply** must contain the full report:
  - the root cause, with file and line, and since when;
  - the fix;
  - each sibling shape and its result before and after;
  - the performance table;
  - every gate receipt;
  - remaining limits.
