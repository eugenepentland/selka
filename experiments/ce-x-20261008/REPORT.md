# CE-X report: copy elimination merged, qualified and timed (2026-10-08)

**Who did what.**
- **The CE-X agent** (opus-lane) qualified the first part of the merged tree. It wrote the tools: `ce.py`, `tables.py`, `identity.py`, `part1a.sh`, `part1b.sh`, `timing-prep.sh`, `part3.sh`, `feasible.py` and `parity_locked.py`.
- **Why the coordinator took over.** While the agent waited on its own background jobs, the harness kept forcing it to hand back. So the coordinating Claude session told it to stand down and ran the rest, using:
  - the agent's scripts;
  - `run-rest.sh`, which waits, runs the strict Part 1 checks, then Part 2 and Part 3;
  - `lox6.sh`;
  - `summarize.py`.
- **This file** was written by the coordinator from the evidence in this directory.

**Code.** Branch `claude/copy-elim` at `41931120d`:
- CE-A is fast-forwarded in at `525d86273`;
- CE-B is merged at `87e0421fd`.

The merge resolved two conflicts:
- `countedMemory`: CE-B's `countedAt` now honours CE-A's views switch.
- `MemoryState.uses`: restored, with CE-A's in-out fields grouped into `InOutCalls`.

No merge fix was needed after that. Nothing was merged into `main` or pushed.

**Compilers (both ReleaseFast).**
- Final: `~/.cache/mylang/ce-final-41931120/bin/mylang`, sha256 `ed975fde…`.
- Base, the tree before the wave: `~/.cache/mylang/ce-base-65a14aeb/bin/mylang`, sha256 `8c420c78…`.

## Result: the CE exit is met

- **Every gate passes on the merged tree.** Details are in [Gates](#gates).
- **Bytes copied, from VP3's base to the merged compiler:**
  - Lox: 1.28 TB → 51.3 GB (**−96.0%**);
  - EDA: 40.7 GB → 3.47 GB (**−91.5%**);
  - parity: 63.2 GB → 155 MB (**−99.8%**);
  - the 46 rows: unchanged.
- **Wall time, final ÷ base, measured in the same session on CPU 10:**

| corpus | final ÷ base | base vs Zig ReleaseFast | **final vs Zig ReleaseFast** |
|---|---:|---:|---:|
| Lox VM (10 cells) | **0.229** (4.4× faster) | 28.95× | **6.62×** |
| Lox tree-walker (10 cells) | **0.279** (3.6× faster) | 6.02× | **1.68×** |
| EDA (34 designs) | **0.784** | 1.70× | **1.33×** |
| parity, `my` arm (27 programs) | **0.910** | 1.23× | **1.12×** |
| 46 rows (median of 3 batches) | **0.999** | — | — |

- **No Lox cell or EDA design is slower.**
- **No parity arm is slower beyond noise.** The largest readings are:
  - dict_count: +2.0% by ratio and +5.2% by wall, with overlapping CIs;
  - binary_trees: +2.9% by ratio but −1.7% by wall.
- **No row is slower than 1.03× beyond noise.** The worst median of three batches is 1.012.
- **The six Lox cells that could not finish in 150 s this morning now finish.** They run at 1.8–2.0× Zig on the tree-walker and 4.9–5.6× Zig on the VM.

## Gates

All gates ran on `41931120d`.

| gate | result | evidence |
|---|---|---|
| `zig build test --summary all` | 88/88 steps; 2054 tests passed (19202 skipped are other shards'); 126.8 s | `logs/gate.log.gz` |
| `zig build fmt-check` | exit 0 | `logs/fmt-check.log` |
| `qualify_merge.py --shards 64` | qualified; test-core 463/0/0; full conformance with `--leakcheck --verify`: **debug 1518/0/0, release 1518/0/0** | `qualify/` |
| frozen fuzz 9×200 against `fuzz-v1` | all 9 kinds PASS: 1,800 cases, 0 mismatches | `fuzz200-summary/`, `fuzz200-cases.tar.gz` |
| Lox conformance, both engines, normal and gc-stress | **974/974**: VM 246 + 246, tree 241 + 241 | `logs/part1b.log` |
| Lox port tests | 65/65 | `logs/lox-port-tests.log` |
| EDA `mylang test src` | 310/310 | `logs/eda-tests.log` |
| counting on against off, goldens, parity `.expected` | 0 cells differ or are uncounted: Lox 48, EDA 34, parity 4, rows 46 | `logs/run-final.log` |
| final against base, plain output | identical: Lox 48/48, EDA 34/34, parity 4/4, rows 46/46 | `results/identity.json` |

**About the fuzz evidence.** The 64 MB of fuzz command logs are not committed. They are in `.mylang-cache/cex/fuzz200-full`, which is ignored. The per-kind summaries and all 1,800 generated sources are committed.

## Copies (Part 2): VP3 → merged

`tables.py` built these, with the full tables in `analysis/tables.json` and `logs/tables.out`. Each lane's own final is shown too. The merged compiler is better than either lane alone, because each lane removed patterns the other did not touch.

| corpus | VP3 (base) | CE-A final | CE-B final | **merged** | change |
|---|---:|---:|---:|---:|---:|
| Lox, all patterns | 1.28 T | 188.89 G | 1.11 T | **51.32 G** | −96.0% |
| Lox P1+P2+P7+P8 | 1.09 T | 16.36 G | 1.08 T | 16.36 G | −98.5% |
| Lox P3+P4+P5 | 72.61 G | 59.62 G | 32.15 G | 32.15 G | −55.7% |
| Lox P9 | 112.14 G | 112.14 G | 2.76 G | 2.76 G | −97.5% |
| EDA, all patterns | 40.73 G | 6.86 G | 35.89 G | **3.47 G** | −91.5% |
| parity, all patterns | 63.16 G | 63.15 G | 154.91 M | **154.91 M** | −99.8% |
| rows, all patterns | 875.16 M | 875.07 M | 875.16 M | 875.07 M | −0.0% |

| highlight | VP3 | merged |
|---|---:|---:|
| Lox VM `fib(27)`, bytes per dispatch | 6,394 | **257** |
| nbody, bytes per step | 12,600 | **0** |
| EDA rds3+flat, all patterns | 3.67 GB | **239 MB** |
| EDA rds3+flat, `overlaps_of` | 1.34 GB | 7.3 MB |
| Lox VM `instantiation`, N/2 → N | ×3.60 (quadratic) | **×1.94 (linear)** |
| Lox tree `instantiation`, N = 10,000 | 87.9 GB | 245 MB |
| `str_build`, out-of-line buffer appends | 16,000,000 | 25 |

**Top 10 functions still copying.** All ten are in Lox.

| # | function | bytes | share of Lox | top site |
|---:|---|---:|---:|---|
| 1 | `vm::run` | 24.62 G | 48.0% | P4 `vm.my:433` `list_set` (11.09 G): the frame write-back |
| 2 | `interpreter::execute` | 5.97 G | 11.6% | P2 `interpreter.my:667` `record_set` (2.96 G) |
| 3 | `vm::read_string` | 4.91 G | 9.6% | P7 `vm.my:268` `ret` (2.45 G) |
| 4 | `heap::sweep` | 4.52 G | 8.8% | P3 `heap.my:361` `list_get` (1.51 G) |
| 5 | `vm::read_constant` | 2.22 G | 4.3% | P7 `vm.my:264` `ret` (1.11 G) |
| 6 | `table::set` | 1.85 G | 3.6% | P9 `table.my:84` `list_copy` (1.85 G) |
| 7 | `interpreter::evaluate` | 1.84 G | 3.6% | P8 `interpreter.my:346` `list_get_field` (1.84 G) |
| 8 | `heap::allocate` | 1.54 G | 3.0% | P4 `heap.my:124` `list_set` (1.50 G) |
| 9 | `vm::call` | 1.26 G | 2.5% | P4 `vm.my:135` `list_set` (814.70 M) |
| 10 | `heap::set_env_slot` | 768.89 M | 1.5% | P4 `heap.my:210` `list_set` (586.64 M) |

## Wall time (Part 3)

### Protocol

**Common to every run:**
- Every timed process ran on CPU 10 under `cpu10.lock`, one step at a time.
- No build ran while the lock was held: the binaries were built beforehand by `timing-prep.sh` and `ce.py`.
- Base and final were measured in the same session, between 17:22 and 18:07 UTC.

**Per corpus:**
- **Lox:** one `measure.py runtime` run, 3 rounds, with both mylang compilers as interleaved, rotated ports alongside Zig, Zig ReleaseSafe, Rust and Go. `LOX_PREBUILT=1` (the patch is in `tools/measure.py.prebuilt.diff`).
- **EDA:** `runtime.py`, 10 rounds, 6 binaries interleaved.
- **Parity:** `bench_parity.py run`, 9 rounds, 2 warm-ups. `parity_locked.py` takes the lock only for the timing passes.
- **Rows:** `measure_all46.py`, 3 batches of 7 interleaved rounds each, measuring cycles. "Old" is base and "new" is final.

**Changes from the brief:**
1. **Lox base and final run in one session as two ports**, rather than two runs. This was the agent's choice, which the coordinator approved: it measures both compilers closer together and times Zig, Rust and Go once.
2. **Builds stay out of the lock.** The Lox harness uses prebuilt binaries, and the parity harness takes the lock only after its build phase.
3. **Cuts the user approved, to finish sooner.**
   - The base compiler was not rerun on the six Lox cells it could not finish in 150 s this morning.
   - The base parity run timed only the `my*` arms; `zig-fast` is always kept for the ratios. The other reference arms were timed once, in the final run.
4. **Added:** a 3-round timed run of those six cells, with the final compiler against Zig, Rust and Go (`tools/lox6.sh`). The feasibility pass found each of them now finishes in 0.25–5.6 s.

### Lox (`results/lox-summary.md`, `results/lox-runtime.{md,json.gz}`)

| cell | final s | base s | final ÷ base | final ÷ Zig | base ÷ Zig | final ÷ Rust | final ÷ Go |
|---|---:|---:|---:|---:|---:|---:|---:|
| closures/vm | 3.943 | 18.574 | 0.212 | 5.13 | 24.16 | 4.10 | 4.06 |
| equality/vm | 7.646 | 23.653 | 0.323 | 8.29 | 25.66 | 7.04 | 6.76 |
| fib/vm | 4.123 | 19.421 | 0.212 | 6.50 | 30.60 | 4.75 | 5.45 |
| invocation/vm | 5.931 | 25.503 | 0.233 | 7.49 | 32.22 | 3.95 | 4.40 |
| method_call/vm | 5.625 | 23.346 | 0.241 | 6.26 | 25.97 | 4.18 | 4.48 |
| properties/vm | 4.528 | 21.876 | 0.207 | 5.76 | 27.81 | 3.35 | 3.80 |
| string_equality/vm | 6.300 | 25.580 | 0.246 | 13.21 | 53.62 | 7.73 | 6.29 |
| strings/vm | 2.379 | 10.820 | 0.220 | 4.60 | 20.91 | 4.30 | 3.68 |
| zoo/vm | 5.124 | 25.322 | 0.202 | 5.89 | 29.10 | 3.43 | 4.05 |
| zoo_batch/vm | 4.521 | 21.283 | 0.212 | 6.10 | 28.71 | 3.74 | 4.32 |
| closures/tree | 0.362 | 0.907 | 0.398 | 1.92 | 4.82 | 1.36 | 1.48 |
| equality/tree | 0.315 | 0.964 | 0.327 | 1.63 | 4.99 | 1.57 | 1.91 |
| fib/tree | 0.155 | 0.449 | 0.346 | 1.53 | 4.43 | 1.08 | 1.29 |
| instantiation/tree | 0.160 | 7.353 | **0.022** | 1.21 | 55.52 | 1.14 | 0.83 |
| invocation/tree | 0.546 | 1.549 | 0.352 | 1.28 | 3.64 | 1.18 | 0.88 |
| properties/tree | 0.529 | 1.263 | 0.419 | 1.62 | 3.87 | 1.38 | 1.14 |
| string_equality/tree | 0.467 | 1.285 | 0.363 | 3.28 | 9.02 | 1.28 | 2.83 |
| strings/tree | 0.156 | 0.377 | 0.415 | 1.80 | 4.33 | 1.29 | 1.41 |
| zoo/tree | 0.546 | 1.523 | 0.359 | 1.56 | 4.34 | 1.23 | 1.07 |
| zoo_batch/tree | 0.473 | 1.317 | 0.360 | 1.60 | 4.45 | 1.28 | 1.08 |

**Geomeans.**
- **VM:** final ÷ base 0.229; final against Zig 6.62×, Zig ReleaseSafe 4.52×, Rust 4.48×, Go 4.63×.
- **Tree-walker:** final ÷ base 0.279; final against Zig 1.68×, Zig ReleaseSafe 1.07×, Rust 1.27×, Go 1.30×.
- **Base matches this morning.** Base ÷ Zig is 28.95× on the VM and 6.02× on the tree-walker; this morning's report had 28.35× and 6.08×.

**Noise.**
- The spread across the three rounds, (max − min) ÷ median, reached about 20% on some final VM cells.
- The harness paused twice, for 36 s each, waiting for CPU 10 and its sibling to go quiet.

**The six cells skipped this morning** (`results/lox-feasible.json`, `results/lox-six-runtime.{md,json.gz}`). Every run passed its output check.

| cell | this morning | final, median of 3 | Zig | final ÷ Zig | final ÷ Rust | final ÷ Go |
|---|---|---:|---:|---:|---:|---:|
| binary_trees/tree | did not finish in 150 s | 0.240 s | 0.122 s | 1.97 | 1.53 | 1.29 |
| trees/tree | did not finish | 0.255 s | 0.144 s | 1.77 | 1.54 | 1.28 |
| method_call/tree | did not finish | 0.532 s | 0.280 s | 1.90 | 1.61 | 1.23 |
| binary_trees/vm | did not finish | 2.614 s | 0.518 s | 5.05 | 3.95 | 3.22 |
| instantiation/vm | did not finish | 1.997 s | 0.405 s | 4.93 | 3.08 | 2.53 |
| trees/vm | did not finish | 5.485 s | 0.985 s | 5.57 | 3.91 | 4.11 |

### EDA (`results/eda-summary.md`, `results/eda-runtime.json.gz`)

All outputs were verified.

| binary | vs Zig ReleaseFast | vs Zig ReleaseSafe | vs Rust | vs Go | peak RSS |
|---|---:|---:|---:|---:|---:|
| base | 1.70× | 1.58× | 1.55× | 0.63× | 52.9 MiB |
| **final** | **1.33×** | **1.24×** | **1.22×** | **0.49×** | 52.5 MiB |

Final ÷ base:
- **Geomean:** 0.784. All 34 designs are faster.
- **Most improved:** rds3+flat 0.496, cyclops-digital-pcb 0.606, cyclops-kband-pcb 0.675, straps-base 0.680.
- **The six least improved:**
  - poe-pd-flyback-tps23757 0.889
  - rds3-rf-selector 0.876
  - barracuda-via-fence 0.849
  - black-canyon+flat 0.847
  - rf-switch-eval 0.836
  - cyclops-kband-breakout 0.836

The full per-design table is in `results/eda-summary.md`.

### Parity (`results/parity-summary.md`, `results/parity-{final,base}.json.gz`)

| program (`my` arm) | base ÷ Zig | final ÷ Zig | final ÷ base |
|---|---:|---:|---:|
| nbody | 9.01 | **1.70** | **0.188** |
| str_build | 3.86 | **2.22** | **0.575** |
| matmul | 4.06 | 4.08 | 1.004 |
| knucleotide | 2.35 | 2.34 | 0.998 |
| sieve | 1.58 | 1.58 | 1.004 |
| geomean, 27 programs | 1.234 | **1.123** | **0.910** |

**Other arms:**
- `text_ops my-tuned`: 0.881.
- `bytes_scan my-wrapping`: 0.949.
- The remaining arms range from 0.976 (`fannkuch_redux my-array`) to 1.029 (`binary_trees my`). The arms above 1.015 are covered in "Reading the parity numbers".
- The geomean over all 44 `my*` arms is 0.904.
- `binary_trees_recursive` has no Zig arm, so it has no ratio.

**Reading the parity numbers.**
- **The harness exits 1 for both runs.** That verdict comes from `bench/parity/thresholds.json`, whose baselines come from an earlier compiler; for example, str_build's is 1.17×. Base misses them as well, so this says nothing about CE.
- **sieve** reads 1.35× Zig in this morning's report but 1.58× for both compilers here, so the change is between the two sessions, not caused by CE.
- **Raw wall times are not comparable with this morning.** Zig's own times are about 40% lower now. Only same-session ratios are compared.
- **scan_count**'s 0.676 is an artifact: its `zig-fast` reference was noisy in one run (the CI is 0.80–1.40), and its raw wall ratio is 1.008.
- **dict_count** reads 1.020 by ratio and 1.052 by wall, but its CIs overlap and it is a 24 ms program. It is within noise, and listed here so it is not missed.
- **binary_trees** reads 1.029 by ratio but 0.983 by wall. `my-arena` reads 1.020 by ratio and 0.977 by wall.

### The 46 rows (`results/rows-summary.md`, `results/all46-{1,2,3}.json.gz`)

**Overall.**
- All three batches are valid.
- New ÷ old geomeans: 0.9990, 0.9974, 0.9976. The median of the three is 0.9986.
- **No row's median exceeds 1.03.** The worst median is `alloc_retained`/4096 at 1.012.

**Single batches above 1.03.** Each one is contradicted by the other two batches, which is the second-batch confirmation the brief asks for:

| row/size | batch 1 | batch 2 | batch 3 |
|---|---:|---:|---:|
| `option_handle`/64 | 1.036 | 0.957 | 0.957 |
| `string_equal`/64 | 1.009 | 0.982 | 1.032 |
| `sort_records`/4096 | 1.011 | 0.899 | 1.035 |

The run-to-run cycle counts are bimodal on both compilers (for example `option_handle`/64 at 36–40 M cycles), which reads as layout or frequency noise.

**Biggest gains:** `json_transform` 0.956/0.958, and `option_handle`/64 0.957.

The counters predicted no change. The rows' remaining copies are patterns CE does not target:
- dict and set growth in `dict_update`, `dict_update_str` and `set_dedup` (P14, 458 MB);
- `record_pass`'s by-value argument, returned through `sret` (P1, 363 MB, all at `row_record_pass.my:48`), a known CE-A limit.

## Remaining limits

From the counters:

1. **Lox VM element write-backs in `vm::run`:** P4, 23 GB, which is 45% of what Lox still copies.
   - The largest site is the frame write-back at `vm.my:433` `list_set` (11.1 GB). `rt.frames[k] = frame` copies the 88-byte frame, because the local `frame` is a separate value.
   - This is the clear next target, and the main reason the VM is still 6.6× Zig while the tree-walker is at 1.7×.
2. **P7 and P2 where `mut` arguments meet a declared result.** These are `vm::read_string`, `vm::read_constant` and `return Ok(token)`-style results: Lox 4.9 G + 2.2 G, EDA P7 2.11 G. Removing them needs homes inside `%ret`.
3. **Per-value interference.** `interpreter::execute` has P2 4.15 G, and its largest site is `interpreter.my:667` (2.96 G). Interference is tracked per value, not per field.
4. **`heap::sweep`** P3/P4 4.5 G, and **`table::set`** P9 1.85 G (`table.my:84` `list_copy`).
5. **The rows' `record_pass`:** a by-value argument whose `sret` result cannot share the argument's home.
6. **`list_set_field` covers record-field chains only.** `xs[i].items.append(v)` still copies the element out and back.

**Pre-existing issues seen during the lanes, not caused by CE:**
- `mylang dump-ir` overflows the stack on EDA's recursive types (`print.typeName`).
- A `facts.shape` general-protection flake, once, in a busy test-core run.
- The replay key gained a `counters` member, so existing replay records miss once.

## Files

- **Tools:**
  - `tools/`: the agent's scripts, plus `run-rest.sh`, `lox6.sh` and `summarize.py`.
  - `tools/summarize.py` regenerates `results/*-summary.md` from the evidence.
- **Raw counters:** `raw/final/*.json.gz`, read by `tables.py` together with the VP3 and lane data.
- **Driver logs:** `logs/run-rest.log` and `logs/lox6.log`, with timestamps for every step.
