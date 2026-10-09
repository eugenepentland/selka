# CE2-X report: the second copy-elimination wave, merged, qualified and timed (2026-10-08)

**Who did this.** The coordinating Claude session did the integration, qualification and timing, and wrote this file. The two lanes were opus-lane agents:
- CE2-A, field effects: `claude/ce2-effects`, report `93250a5b3`;
- CE2-B, results and arguments in place: `claude/ce2-results`, report `53766513d`.

**Code.** Branch `claude/copy-elim-2`.
- **CE2-A:** fast-forwarded to it.
- **CE2-B:** merged at `655f1a265`, with the merge fixes below.
- **`main`:** merged at `93547d310`. That brought in `1edeef830`: the item-5 test runner and the NEW-CORE-CE-RECORDS-6 hotfix.
- **Then** `2141c4f6b` turned sret sharing off (see "Run 1").

**Compilers** (ReleaseFast):
- final `~/.cache/mylang/ce2-final-2141c4f6` (sha256 `cac3d272…`);
- base, the CE-X compiler: `~/.cache/mylang/ce-final-41931120` (`ed975fde…`).

Nothing is merged into `main` or pushed.

## Result: the CE2 exit is met

**Correctness.** Every gate is green on `2141c4f6b` (see Gates).

**Bytes copied against CE-X:**
- Lox: 51.3 GB → **7.33 GB (−85.7%)**;
- EDA: 3.47 GB → **1.08 GB (−68.9%)**;
- parity: unchanged at 155 MB;
- the rows: unchanged at 875 MB, because sharing is off.

**Against VP3 this morning:** Lox 1.28 TB → 7.3 GB (−99.4%), EDA 40.7 GB → 1.08 GB (−97.3%).

**Wall time**, final against the CE-X compiler, in the same session on CPU 10:

| corpus | final ÷ CE-X | CE-X vs Zig ReleaseFast | **final vs Zig ReleaseFast** | final vs Zig ReleaseSafe | final vs Rust | final vs Go |
|---|---:|---:|---:|---:|---:|---:|
| Lox VM, 13 cells | **0.487** | 6.24× | **3.04×** | 2.00× | 2.08× | 2.07× |
| Lox tree-walker, 13 cells | **0.949** | 1.80× | **1.71×** | 1.03× | 1.28× | 1.25× |
| EDA, 34 designs | **0.954** | 1.32× | **1.26×** | 1.15× | 1.14× | 0.47× |
| parity, `my` arm, 27 programs | 1.019 (noise; see below) | 1.11× | 1.13× | 0.93× | 1.15× | — |
| 46 rows, median of 3 | **0.9997** | — | — | — | — | — |

- **Slower rows:** none beyond noise.
- **Two row medians above 1.03 (`binary_search`/64 and `sort_records`/4096):** both have byte-identical LLVM under the CE-X and CE2 compilers (see "Identical-code review").
- **The day so far, Lox VM:** 28.4× Zig this morning, 6.6× after CE, **3.0×** now.
- **The day so far, EDA:** 1.82× → 1.33× → **1.26×**.

## Integration

**Merging CE2-B onto CE2-A** (`655f1a265`). Each lane passed every gate on its own; the combination did not, until these fixes.

- **A wrong answer from the two lanes together** (NEW-CORE-CE2-MERGE-1).
  - **The mechanism:** CE2-B's sret sharing registers a by-value argument as an in-out final value, and CE2-A's `writtenRegions` then took the callee's empty `mut` summary as what the call writes.
  - **The symptom:** in `s = rotate(s, j); kept = s`, `kept` shared a home that the call overwrote. CE2-B's fixture printed `252 966 966 966` instead of `747 179 179 966`.
  - **The fix:** `writtenRegions` now narrows only for a `mut` (owned) parameter.
  - **The test:** a new focused test fails without the fix. It was checked both through the CLI and through the test harness.
- **CE2-B's `%ret` overlap check (`clash`)** now uses `interferesWhole`, the per-value form, as CE2-B's report asked. CE2-A's per-field regions are offsets within one shared home, and say nothing about another class at another offset in `%ret`.
- **Guardian's seven-field limit:** `Input` gained CE2-A's `effects` and CE2-B's `results`, so CE-A's `ret_home` moved into `Results.home`.
- **A renamed field:** CE2-A moved `Planner.dense` to `Planner.places.dense`, and CE2-B's one use of it was updated.
- **`count_test`:** `bump` now lends its element to `bumped` (CE2-B step 2), so the 400-byte copy is counted at `bumped`'s `record_set`.
- **Textual conflicts:**
  - `own.zig` and `root_test.zig` had additions on both sides at one place; both were kept;
  - in `emit_llvm.zig`, CE2-B's `planMemory` split was kept, with CE2-A's `.effects`.

**Merging `main`** (`93547d310`). One conflict, in `returnFrom`. The conservative hotfix gave way to CE2-B's precise `Plan.staged`. The hotfix's regression test stays, and its spec bullet now describes the precise rule.

## Run 1 found a regression, and sret sharing was turned off

The first full timing pass, with sharing on and the compiler at `93547d310`, is kept in `run1-sharing-on/`.
- **The regression:** the rows' `record_pass` was **1.152 at size 64 and 1.191 at size 4096 in all three batches**, although its copies fell to 0.
- **The cause:** a callee that shares its by-value parameter's memory with `%ret` is defined without `noalias` on both. LLVM must then interleave the twelve field loads and stores of `State(f0=s.f1, …)` in order, instead of moving them with wide loads and stores, so the one 96-byte copy per call was cheaper.
- **The fix:** `2141c4f6b` sets `emit_homes.steps.share_sret = false`. The planner code stays behind the switch, and NEW-CORE-CE2-RESULTS-5's test and spec bullet now state the off behaviour.
- **Run 2:**
  - `record_pass` is **0.999 and 1.000**;
  - `invocation/tree`, 1.026 in run 1 with consistent rounds, is 1.015 with overlapping rounds.
- **Run 1's other numbers** were essentially the same as run 2's: Lox VM 0.485, tree-walker 0.954, EDA 0.948, parity 1.001.

## Gates

| gate | result | evidence |
|---|---|---|
| `zig build test --summary all` | 88/88 steps, 2093 tests passed | `logs/gate.log.gz`, `logs/part1a.log` |
| `zig build fmt-check` | exit 0 | `logs/fmt-check.log` |
| `qualify_merge.py` | qualified; full conformance with leak and fact verification: **debug 1518/0/0, release 1518/0/0** | `qualify-run2/`, `logs/part1a-qualify2.log` |
| frozen fuzz 9×200 | all 9 kinds qualified (1,800 cases) | `fuzz200-summary/`, `fuzz200-cases.tar.gz` |
| Lox conformance, both engines, normal and gc-stress | **974/974** | `logs/part1b.log` |
| Lox port tests | 65/65 | `logs/lox-port-tests.log` |
| EDA `mylang test src` | 310/310 | `logs/eda-tests.log` |
| counting on vs off, goldens, parity `.expected` | 0 cells differ or are uncounted (Lox 48, EDA 34, parity 4, rows 46) | `logs/run-final.log` |
| final vs CE-X compiler, plain output | identical: Lox 48, EDA 34, parity 4, rows 46 | `results/identity.json` |
| test-core | 502/0, after both merges and the switch | — |

**Process notes.**
- **Conformance re-run:** run 2's first attempt crashed on run 1's leftover temp directory, `.mylang-cache/s5/integration-qualify/qualify`, before testing anything. It was re-run under a fresh evidence name (`qualify-run2`).
- **The Lox harness root:** a copied Lox tree needs `.tmp/lox-bench`, which the harness uses to find its root. Its absence failed the first set of timing builds, which were redone.
- **The fuzz command logs:** 64 MB per run, kept out of the commit in `.mylang-cache/cex/fuzz200-run{1,2}-full`.

## Copies: CE-X final → merged

`tables.py`, with the tables in `analysis/` and `logs/tables.out`:

| corpus | CE-X | CE2-A final | CE2-B final | **merged** | change |
|---|---:|---:|---:|---:|---:|
| Lox, all patterns | 51.32 G | 12.30 G | 46.35 G | **7.33 G** | −85.7% |
| Lox P2 | 7.73 G | 9.22 M | 7.73 G | 9.22 M | −99.9% |
| Lox P4 | 27.47 G | 1.94 G | 27.47 G | 1.94 G | −92.9% |
| Lox P7 | 5.34 G | 6.40 M | 5.33 G | 4.97 M | −99.9% |
| Lox P3 | 4.67 G | 4.67 G | 1.66 G | 1.66 G | −64.5% |
| Lox P9 | 2.76 G | 2.76 G | 1.07 G | 1.07 G | −61.5% |
| EDA, all patterns | 3.47 G | 3.46 G | 1.08 G | **1.08 G** | −68.9% |
| EDA P7 | 2.11 G | 2.11 G | 2.63 M | 1.32 M | −99.9% |
| parity | 154.91 M | 154.91 M | 154.91 M | 154.91 M | 0 |
| rows | 875.07 M | 875.07 M | 512.13 M | 875.07 M | 0 (sharing off) |

**Highlights:**
- **Lox VM `fib(27)`:** 257 → **27 bytes per dispatch**. VP3 this morning was 6,394.
- **EDA rds3+flat:** 239 MB → 103 MB.

**Top sites still copying:**

| site | bytes |
|---|---:|
| `vm::run` P3 frame reloads (`vm.my:525`, `:503`) | 1.63 G |
| `interpreter::evaluate` P8 `list_get_field` (`interpreter.my:346`) | 1.60 G |
| `heap::allocate` P4 (`heap.my:124`, a by-value `Obj` stored into the list) | 1.50 G |
| EDA `parse_list` P6 (needs a payload-destination ABI) | 445 M |
| `compiler::emit_byte` P9 | 486 M |

## Wall time (run 2)

The protocol is CE-X's:
- **Lox:** one `measure.py runtime` run, 3 rounds, with both mylang compilers as interleaved ports alongside Zig, Zig ReleaseSafe, Rust and Go. All 26 cells; the CE-X compiler finishes the six that did not finish this morning.
- **EDA:** `runtime.py`, 10 rounds, six binaries.
- **Parity:** 9 rounds and 2 warm-ups, final with every arm, then base with the `my*` arms.
- **Rows:** `measure_all46.py`, three batches.

Per-cell tables are in `results/{lox,eda,parity,rows}-summary.md` (`tools/summarize.py`).

**Lox:**
- No failed runs; the harness waited twice for quiet CPUs.
- **VM:** final ÷ CE-X between 0.28 (`string_equality/vm`) and 0.60.
- **Tree-walker:** between 0.92 and 1.015.

**EDA:**
- final ÷ CE-X 0.954;
- all 34 designs faster (0.932–0.988);
- outputs verified;
- peak RSS 52.5 MiB for both.

**Parity:**
- final ÷ CE-X 1.019 on the `my` arm, and 1.016 over all 44 arms.
- **Arms above 1.03 by ratio:**

  | arm | by ratio | by wall |
  |---|---:|---:|
  | `scan_count` | 1.56 | 1.23 |
  | `text_ops` (`my`, `my-tuned`) | 1.06–1.07 | 1.23 |
  | `binary_trees` (`my`, `my-arena`) | 1.07–1.09 | 0.92–0.94 |

- **`text_ops` and `scan_count` are noise:** their generated LLVM is identical under the CE-X, run-1 and run-2 compilers. They were 0.997 and level in run 1. This run shared the machine with the PM measurement agent, and these two programs are memory-bound.
- **`binary_trees` is noise:** its ratio and wall time disagree in direction.

**Rows:**
- median-of-3 geomean 0.9997;
- `record_pass` 0.999 and 1.000.

**Identical-code review.** The two rows whose median is above 1.03 compile to byte-identical LLVM under the CE-X compiler, the run-1 compiler and the run-2 compiler.

| row | median | batches | reading |
|---|---:|---|---|
| `binary_search`/64 | 1.038 | 1.037, 1.038, 1.039 | **Code placement.** S5's rule for this row is an "identical-code/layout-noise review". The binaries differ only in the bundled runtime, which `main`'s test runner changed, and that moves the hot loop. |
| `sort_records`/4096 | 1.076 | 1.076, 1.244, 0.978 | **Noise.** The batches are spread far apart. |

## Remaining limits and next steps

- **The next plan is `docs/audits/runtime-parity-plan-2026-10-08.md`**, on `claude/parity-measure`. Its wave PM, measurement and attribution, is running.
- **Copies left:** Lox VM frame reloads (1.6 G); `heap.my:124` (1.5 G); `list_get_field` P8 in the interpreter (2.1 G); EDA P6 (0.44 G, needs a payload-destination ABI).
- **sret sharing is off.** Redo it so the callee keeps `noalias`, for example by loading every field before storing any.
- **Code layout:** `binary_search` shows that layout alone moves a row by about 4%. A function-alignment policy would make the rows steadier. This is the 10-04 finding on `string_search`.
