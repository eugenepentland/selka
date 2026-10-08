# Pre-VP3 profiles, 2026-10-08

These profiles retargeted VP3 (plan §4.1). They were taken by the coordinating Claude
session before the package started, on the 2026-10-08 benchmark binaries. The perf data
files were not kept; the commands below reproduce them.

## Binaries

- **Lox:** `mylang-worktrees/claude-bench-newcore/.mylang-cache/bench/lox/.tmp/lox-bench/cache/mylang-release/lox-release`.
  This is the ReleaseFast compiler at `9c24997e` (main `5a6b501d` plus the
  NEW-CORE-TAKE-READS-1 fixes). Scripts and sizes are under `.../bench/lox/bench/`.
- **EDA:** `eda-bench-wt/claude-eda-bench-newcore/.cache/release/mylang/eda-sch`
  (`mylang build --release`, main `5a6b501d`).

## Commands

All runs used CPU 14 (an E-core), never the timing CPUs 2, 3, 10 or 11. They measure where
samples fall, not time.

```console
# Lox VM, fib at N = 27 (0.62 s)
taskset -c 14 perf record -F 4999 -o vm-fib.data lox-release --engine=vm fib27.lox
# Lox tree engine, properties at N = 100000 (1.84 s)
taskset -c 14 perf record -F 4999 -o tree-props.data lox-release --engine=tree props.lox
# EDA, rds3+flat (0.36 s), run from the eda-bench root
taskset -c 14 perf record -F 25000 -o eda.data eda-sch --model golden/cases/rds3+flat/model.sexp \
    --project-dir golden/projects/designs --out-dir OUT --flat
# EDA call chains, on a P-core
taskset -c 4 perf record -F 20000 --call-graph lbr -o eda-lbr.data eda-sch ...
python3 classify.py vm-fib.data 6        # share of samples by instruction kind
python3 classify.py tree-props.data 14
perf report -i eda.data --stdio --sort symbol
```

`classify.py` classifies each sampled instruction in the top symbols:
- vector moves count as record or aggregate copies;
- `inc` and `dec` on memory, and `add`/`sub` of 1 on memory, count as count updates;
- `cmp` against `0xffffffff` counts as the count's saturation check.

It weights each symbol by its share of samples.

## Results

| Program | Copying records and buffers | Count updates (incl. saturation check) |
|---|---|---|
| Lox VM, fib | 57.8% (vector moves in `vm::run`, which is 95% of samples) | 5.1% |
| Lox tree, properties | 35.1% of all samples (top 14 symbols cover 79.7%) | 3.7% |
| EDA, rds3+flat | about 44% in the runtime: `myl_core_free_block` 17%, glibc `__memmove_avx_unaligned_erms` (`rep movsb`) 15%, `myl_core_dict_copy` 6.6% plus `reference_at` (its child walk) 7.2%, `block_alloc` 2.8%, `myl_core_list_copy` 1.6% | about 2.5% |

**EDA call chains (LBR).**
- `kicad_sch_verify::check` → `kicad_sch_textbox::scan` holds 14% of samples itself.
- About 6 points of the `memmove` come from `realloc` ← `myl_core_list_grow` inside that
  scan.

**Caveat.** These are single short runs: about 3,000 samples for the Lox VM, about 9,000
for the Lox tree engine, and a few hundred for EDA. Percentages are good to a few points.
