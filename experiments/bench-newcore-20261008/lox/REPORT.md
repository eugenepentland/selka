# Lox benchmark on the new core, 2026-10-08: stopped at the correctness check

No runtime, compile-ladder or unit-test numbers were taken. The new-core build of the Lox port prints correct output, but its run time grows **quadratically** with the Lox heap. So it cannot finish at the timed sizes:
- `binary_trees` on the tree engine at N=10 was still running after more than 10 minutes. Zig ReleaseFast takes 0.16 s.
- `zoo_batch` on the tree engine did not finish within 600 s even at the smoke size N=2. Zig takes 0.03 s.

## Cause: a list append through a field of a `mut` record parameter copies the list

**Profile.** A `perf` profile of `binary_trees` on the tree engine at N=4 puts about 87% of samples in list copying and freeing (`probe/perf-newcore-binary_trees-tree-n4.txt`):

| symbol | share |
|---|---:|
| `reference_at` (under `myl_core_free_block`) | 28.2% |
| `myl_core_list_copy` | 26.9% |
| `myl_core_free_block` | 18.1% |
| libc memcpy | 14.3% |

**Where the copies come from.** They are called from `heap::allocate`, `heap::set_env_slot`, `interpreter::set` and `interpreter::enter_function`. All four write into `rt.objects`, a `list[Obj]` field of the `mut Runtime` parameter.

**Minimal repros** (`repro/`, new core, `--release`):

| repro | N=10,000 | N=40,000 | N=80,000 |
|---|---:|---:|---:|
| `field_append.my`: `rt.objects.append(i)`, `rt: mut Runtime`, `objects: list[int]` | 0.01 s | 1.35 s | 6.7 s |
| `lox_shape.my`: as above with `list[Obj]` plus a slot write-back | 0.76 s | 19.4 s | |
| `lox_shape.my`, append only | 0.56 s | 10.8 s | |
| `param_append.my`: `xs.append(i)`, `xs: mut list[int]` | 0.00 s | 0.00 s | |

- **The old core is linear** on the same program: `lox_shape.my` takes 0.02 s at N=40,000.
- **A new-core debug build is just as slow**, so this is not an optimizer artifact.
- **The Core IR** (`repro/field_append.core-ir.txt`) shows why. `main::allocate` reads the list with `record_get list[i64] param0, field0` and runs `list_push` while `param0` still holds the list. The list is therefore shared at the push, and the push copies it.

The parity suite's nbody regression (1.99× → 8.97× Zig, with 315 `memcpy` call sites in `advance`) looks like the same family: a write through a field of a record held in a list or a `mut` parameter.

## Correctness at the smoke size

- **Output:** every new-core run that finished printed exactly the oracle output.
- **Allocation and GC counts:** its `[stats]` counts matched the old core, Zig and Rust on all 26 script×engine cells.
- **One timeout:** the exception is `zoo_batch` on the tree engine, which hit the 600 s timeout.

## The port is slow on the old core too

The value-semantics port that S4 migrated to, the only one the new core accepts, is already very slow on the old core:
- the tree engine runs `properties`, `method_call` and `zoo_batch` at roughly 8,000–10,000× Zig at the smoke size;
- `binary_trees` on the tree engine takes 52 s at N=8, against Zig's 0.03 s.

The 2026-09-23 class-based port ran the tree suite at 7.5× Zig, but the new core rejects it (`heap.my:20:14: error[E_VALUE_CLASS]`). The S4 migration was qualified on conformance, unit tests and build times, never on interpreter run time. So the port needs a runtime review as well as the compiler fix.

Smoke-size wall seconds, measured on a loaded machine with runs in parallel. These are not timing quality; read the new/old columns.

| script | VM: new core | VM: old core | VM new/old | tree: new core | tree: old core | tree new/old |
|---|---:|---:|---:|---:|---:|---:|
| binary_trees | 30.7 | 0.07 | 446× | 255.8 | 9.87 | 26× |
| closures | 1.53 | 0.02 | 72× | 9.52 | 8.35 | 1.1× |
| equality | 1.82 | 0.04 | 49× | 1.48 | 0.02 | 93× |
| fib | 0.37 | 0.01 | 40× | 0.91 | 0.41 | 2.2× |
| instantiation | 126.9 | 0.07 | 1,947× | 372.3 | 0.06 | 6,012× |
| invocation | 1.13 | 0.05 | 23× | 340.9 | 0.11 | 3,102× |
| method_call | 6.79 | 0.14 | 49× | 471.6 | 142.1 | 3.3× |
| properties | 2.87 | 0.13 | 22× | 310.1 | 76.0 | 4.1× |
| string_equality | 3.95 | 0.19 | 20× | 6.13 | 0.05 | 118× |
| strings | 0.33 | 0.01 | 27× | 0.46 | 0.01 | 52× |
| trees | 0.26 | 0.01 | 30× | 1.15 | 0.36 | 3.2× |
| zoo | 0.59 | 0.02 | 29× | 12.97 | 7.62 | 1.7× |
| zoo_batch | 8.39 | 0.37 | 23× | >600 (timeout) | 302.0 | >2× |

The old core in this table is `$HOME/.cache/mylang/s4-wave0-20261006/mylang-s4-pin/bin/mylang` (a16a324e), the pin the S4 port was qualified with.

## What was checked

- **Copy:** the benchmark tree was copied from `mylang-worktrees/codex-s4-lox-value-semantics/benchmarks/lox` (Codex's worktree, unmodified).
- **Unchanged since 2026-09-23** (byte-identical to `bench/lox-20260922`):
  - the harness, `bench/` and `SPEC.md`;
  - the corpus and `harness/prime/{go,zig}`;
  - the Zig, Rust and Go ports.
- **Changed:** only `ports/mylang/` differs, from the S4 value-semantics migration.
- **`bench.json` for the new core** (`bench.json`, `bench.json.diff`, `prime-mylang.json`):
  - `release` = `mylang build main.my --release -o {cache}/lox-release --cache-dir {cache}/mylang`, and `debug` is the same without `--release`.
  - The output moved because `build` does not create the parent directory of `-o`.
- **Edit anchors:** all four exist exactly once in every port.
- **Builds:** every profile of every language builds.

## Next

1. **Fix the compiler**: an append or element write through a field of a `mut` record parameter, or of a record held in a list, must not copy the list. Then rerun the four repros and the parity suite's nbody.
2. **Review the port's runtime**, which is also super-linear on the old core.
3. **Then run stage B**: `RUN_STAGE_B=1 ./run.sh` (runtime on CPU 10 under `cpu10.lock`, 5 rounds; compile ladder and tests under `bench-compile.lock`).

## Files

- `bench.json`, `bench.json.diff`, `prime-mylang.json`
- `run.sh`: stage A was done; stage B is gated.
- `summarize.py`: produces the per-script ratios and geomeans; checked against the 2026-09-23 JSON.
- `probe/`: `probe.py`, `smoke.json`, the perf profile.
- `repro/`: `field_append.my`, `lox_shape.my`, `param_append.my`, `field_append.core-ir.txt`.

The run was made by a benchmark agent. The coordinator wrote this file from the report the agent returned as text.
