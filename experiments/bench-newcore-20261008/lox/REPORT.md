# Lox benchmark on the new core, 2026-10-08

## Summary

The first attempt stopped at the correctness check. A new-core defect made the interpreter quadratic in the size of the Lox heap: appending to or writing a list field of a `mut` record copied the whole list. Three compiler commits on `claude/bench-newcore` fix it (NEW-CORE-TAKE-READS-1):

| commit | what it fixes |
|---|---|
| `fc62d626` | A field read earlier in the same function no longer stops the take, and the read and the write-back may sit in different blocks, as an index's negative-index branch puts them. |
| `63fd137e` | Every field a record's write-backs replace can be taken, not just the first, and repeated reads of one field in one block are merged, which covers nested `h.marker.marks.append(x)`. |
| `9c24997e` | A part of an earlier read may still be used after the write-back, because it holds its own count (promotion). |

**Qualification of the three commits:**
- full gate: 88/88;
- conformance against the frozen old-core answers: 1,518/0/0 at debug and release, with leak and verify (`../fix/qualify-take/`);
- frozen fuzz: 9 kinds × 50, all pass.

With the fix, all 26 script × engine cells print the expected output. 20 of them finish at the benchmark's sizes; 6 still run for more than 150 s and are left out of the timed run (below).

## Runtime: 20 cells, new core `9c24997e`, 3 rounds on CPU 10

| | mylang ÷ Zig ReleaseFast | mylang ÷ Rust | mylang ÷ Go | Zig ReleaseSafe ÷ Zig ReleaseFast |
|---|---:|---:|---:|---:|
| tree engine (10 scripts) | **6.08×** | **4.59×** | 4.78× | 1.60× |
| VM engine (10 scripts) | **28.4×** | **19.5×** | 20.4× | 1.43× |
| peak RSS (20 cells) | 3.1× | 1.2× | | |

Per-script ratios are in `results/runtime-summary.md`. Spread across rounds is a median of 3–4% per cell. There were no quiet-waits, and load fell from 4.6 to 0.9.

**Earlier runs, for comparison.** They used the old core and a different mylang port, so they are not like-for-like:

| run | tree ÷ Rust | VM ÷ Rust |
|---|---:|---:|
| 2026-09-23: old core, class-based port | 5.7× | 6.6× |
| 2026-10-03: old core, optimized class-based port | 4.24× | 2.78× |
| 2026-10-08: new core, value-semantics port | 4.59× | 19.5× |

**Why the VM engine is slow.** The VM is uniformly 20–30× slower than Zig on every script, and a profile puts 95% of the time in `vm::run` itself, with no list copies. The value-semantics port writes the whole call frame back into `rt.frames` on every instruction (`rt.frames[rt.frame_count - 1] = frame`). A `CallFrame` holds the function record and two lists, so each write-back is a full record store with count updates on its lists. The class-based ports needed no write-back. The parity suite's nbody (an element-field store per field update) is in the same family.

**Cells left out** (each ran longer than 150 s at its timed size):
- binary_trees, tree and VM;
- trees, tree and VM;
- instantiation, VM;
- method_call, tree.

Two causes are known:
- **instantiation VM:** `call_value` matches on `rt.objects[ref]` and uses the class after `heap.allocate(mut rt, ...)`. The ownership pass then promotes the whole `rt.objects` list read, not only the class value. The list is shared during the allocation, so each instantiation copies it.
- **binary_trees and method_call on the tree engine** were already very slow on the old core with this port (52 s and 142 s at small sizes). That points to the port as well as the compiler.

## Compile ladder: medians of 3

| port:profile | cold | cold, primed | no-op | hub comment | leaf body | hub body | hub interface |
|---|---:|---:|---:|---:|---:|---:|---:|
| mylang:release | 9.45 s | 3.88 s | 0.01 s | 0.12 s | 0.12 s | 0.12 s | 0.12 s |
| mylang:debug | 5.62 s | 0.37 s | 0.01 s | 0.11 s | 0.13 s | 0.11 s | 0.11 s |
| zig:release | 74.03 s | 12.99 s | 0.02 s | 12.30 s | 12.28 s | 12.34 s | 12.47 s |
| zig:debug | 59.06 s | 0.88 s | 0.02 s | 0.29 s | 0.33 s | 0.29 s | 0.29 s |
| rust:release | 0.66 s | 0.66 s | 0.02 s | 0.64 s | 0.64 s | 0.62 s | 0.64 s |
| rust:debug | 0.48 s | 0.48 s | 0.02 s | 0.17 s | 0.16 s | 0.16 s | 0.16 s |
| go:release | 2.17 s | 0.40 s | 0.10 s | 0.18 s | 0.18 s | 0.17 s | 0.18 s |
| go:debug | 1.68 s | 0.31 s | 0.10 s | 0.18 s | 0.17 s | 0.20 s | 0.18 s |

**The harness's four edits do not change the program's code.**
- The four edits are:
  - a comment;
  - two behaviour-neutral rewrites;
  - an unused new function.
- On the new core, content-keyed units and program replay serve them in about 0.12 s, even for a release build.
- A release edit that does change code recompiles the whole program. At 48k lines that took 51 s in S5's dev-loop measurement.

**Against 2026-09-23 (old core):**
- release rebuild after an edit: 4.6–5.0 s → 0.12 s;
- debug rebuild after an edit: 0.52–0.57 s → 0.11–0.13 s;
- cold primed debug build: 14.4 s → 0.37 s.

## Unit tests (63 per port)

| port | cold | cold, primed | cached | forced | after the hub-body edit |
|---|---:|---:|---:|---:|---:|
| mylang | 7.40 s | 1.34 s | 0.08 s | 0.77 s | 0.44 s |
| zig | 59.99 s | 0.97 s | 0.03 s | 0.06 s | 0.37 s |
| rust | 0.63 s | 0.63 s | 0.03 s | – | 0.19 s |
| go | 3.15 s | 0.73 s | 0.06 s | 0.18 s | 0.17 s |

Against 2026-09-23 (old core), cold primed went from 11.35 s to 1.34 s, and after the hub-body edit from 0.35 s to 0.44 s.

## Protocol

- **Compiler:** `~/.cache/mylang/bench-newcore-9c24997e/bin/mylang`, a ReleaseFast build of branch `claude/bench-newcore` at `9c24997e` (main 5a6b501d plus the three fix commits).
- **Toolchains** (the same as 2026-09-23): zig 0.17.0-dev.1683+5ceec001b, rustc/cargo 1.98.1, go 1.27.0.
- **Benchmark tree:** copied from `mylang-worktrees/codex-s4-lox-value-semantics/benchmarks/lox`. The harness, sizes, scripts, expected outputs and the Zig, Rust and Go ports are byte-identical to `bench/lox-20260922`; only `ports/mylang/` differs (the S4 value-semantics port).
- **mylang `bench.json`:**
  - `release` = `mylang build main.my --release -o {cache}/lox-release --cache-dir {cache}/mylang`;
  - `debug` = the same without `--release`;
  - the old `release-qbe` and `release-safe` profiles are dropped.
- **Runtime:** `measure.py runtime --ports mylang,zig,rust,go --profiles release,zig:release-safe --rounds 3 --cpu 10`.
  - It ran under `flock cpu10.lock`, 09:39–09:56 UTC.
  - Deviation: `LOX_SKIP` (`measure.py.diff`) leaves out the six cells above. The 2026-09-23 run used CPU 11 and 4 rounds.
- **Compile ladder and tests:** `measure.py compile` and `measure.py tests`, 3 rounds on CPUs 0–1, 4–9 and 12–19.
  - Both ran under `flock bench-compile.lock` through a build slot, 09:56–10:51 UTC, with load about 1.
- **Feasibility pass** (`feasible.py`): every cell at its timed size, one run each, 150 s timeout, on a loaded machine. It found the six cells that do not finish.

## Files

- **Reports and summaries:**
  - `results/runtime-summary.md`: the per-script tables;
  - `results/*/runtime.md`, `compile.md`, `tests.md`: the harness's own tables.
- **Raw data:** `results/*/*.json.gz`.
- **Run scripts:** `stageB.sh` and `stageB.log` (the run); `run.sh` (the first attempt); `feasible.py`; `measure.py.diff`; `bench.json`, `bench.json.diff`, `prime-mylang.json`.
- **First attempt's diagnosis:** `probe/` and `repro/`.
