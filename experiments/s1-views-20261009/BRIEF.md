You are implementing lane **S1 ("substring views")** of mylang's runtime-parity plan, in the new compiler core. Work autonomously to the lane exit, then stop and report. A second agent is implementing lane F1 ("aliasing and overflow facts") in parallel in another worktree. Stay inside your owned areas (below).

## Where everything is

- **Your worktree** (locked, yours alone): `/home/epentland/ai/canopy/mylang-worktrees/claude-vk-vp3`, branch `claude/s1-views`, based on `main` `cafe7fea7`. That base is the new core with both copy-elimination waves (CE, CE2) and wave PM's check counters. The worktree was reused from an earlier lane, so it has warm build caches; treat anything under `.mylang-cache/` as stale.

  Do all work and builds here. Read other worktrees only.
- **Read first:**
  1. `CLAUDE.md`.
  2. The plan, `docs/audits/runtime-parity-plan-2026-10-08.md`: §8 (the finalized lanes; authoritative for your lever, exit and ownership) and §6 (gates).
  3. Wave PM's report, `experiments/parity-measure-20261008/REPORT.md`: "Where mylang's extra instructions go" (knucleotide, scan_split, text_ops, EDA), the knucleotide ladder, and PM-4 lever 2.
  4. The ladder itself, `experiments/parity-measure-20261008/ladders/knucleotide.c`. Rung 0 is today's code transcribed to C; rung 1 is views (hash and compare in place, allocate only on insert); rung 2 inlines the short-key compare. It shows exactly what the ideal emitted code does.
  5. The wall-time confirmation, `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/experiments/parity-confirm-20261009/REPORT.md` (commit `e1e9600a5`, not in your base).
  6. `docs/tooling/counters.md`: `--counters` builds and `mylang cost ENTRY --counters FILE.json`, including allocation counts.
  7. The code that already exists for borrowed text keys:
     - `src/core/emit_dict_span.zig`: inline borrowed text-key probes, used today only for clean, index-less dictionaries;
     - `src/core/fuse_dict.zig`: pure probes of identical dictionary/key SSA values share a dominating lookup;
     - `src/core/fuse_text_split.zig`: private whitespace-split loops borrow their dictionary lookup keys from the source;
     - the `str_view` IR type and `dict_find` with a span operand in `src/core/ir.zig`;
     - plus `src/core/emit_text.zig`, `build_text.zig`, `emit_dict.zig`, `build_dict.zig`, `src/core/runtime/core_text.c` and `core_dict.c`.

## The shape you are removing

`bench/parity/suite/knucleotide.my`:

```python
def frequencies(seq: str, k: int) -> dict[str, int]:
    counts: dict[str, int] = {}
    for i in range(len(seq) - k + 1):
        key = seq[i:i + k]
        counts[key] = counts.get(key, 0) + 1
    return counts
```

Today each position:
- materializes `seq[i:i+k]`: an allocation, a copy, and an ASCII re-scan of bytes whose parent is already known ASCII;
- probes the dictionary once (the get and the set are already fused), calling `str_eq`;
- frees the slice.

PM measured:
- materialization 43% of instructions;
- allocation and free 12%;
- hash and compare 19%.

The dictionary itself is not the problem.

## The measured bounds (PM, then confirmed as wall time on CPU 10)

| program | ladder rung | cycles ÷ rung 0 (PM) | wall ÷ rung 0 (CPU 10) | today ÷ Zig ReleaseSafe | after |
|---|---|---:|---:|---:|---:|
| knucleotide | 1: views, allocate only on insert | 0.441 | 0.470 | 2.07 | 0.97 |
| knucleotide | 2: + short-key compare inlined | 0.366 | 0.387 | | 0.80 |

Rung 0 is 8% faster than mylang in wall time.

## Your work, in this order (measure after each step)

1. **A slice used as a dictionary key is a view.** For `d.get(s[i:j], …)`, `s[i:j] in d`, `d[s[i:j]]` (read), and the fused get-then-set update above:
   - hash and compare the key in place in `s`'s bytes;
   - materialize a fresh `str` only when the update inserts a new entry.

   Extend the existing borrowed-span machinery (`str_view`, `dict_find` with a span, `emit_dict_span.zig`, `fuse_dict.zig`) rather than building a parallel path. That includes lifting the "clean, index-less dictionaries" restriction where it can be done soundly; if it can't, say why. The view must not outlive `s`, and `s` must not change while the view is live: value semantics makes this a question of SSA liveness.
2. **No ASCII re-scan** when a slice of a string already known ASCII is materialized: the flag is inherited. This helps every remaining materialized slice.
3. **Inline the short-key compare.** For keys up to 16 bytes, compare inline (word loads plus a length check) instead of calling `str_eq` or `memcmp`. Ladder rung 3 shows that inlining the span hash adds nothing, so skip it unless your measurements disagree.
4. **If time remains: read-only slices as views.** For example `len(s[i:j])`, `s[i:j] == t`, `s[i:j].startswith(...)`, or a slice passed to a parameter that only reads it. Measure on `bench/parity/suite/text_ops.my` and the EDA designs (text materialization is 10–12% of EDA's instructions, against Zig's 2%). Split pieces (`str.split`) belong to lane S2; leave them.

If a step can't be made safe, revert it, keep the others, and say why.

**Exit** (plan §8, S1):
- knucleotide ≤ 1.0× Zig ReleaseSafe. Measure this yourself as cycles; see "Measuring".
- At most 0.05 allocations per position in `frequencies`, on insert only (counting build).
- Nothing else slower than 1.03× in instructions or cycles beyond noise. That covers every parity program, 4 Lox cells and 2 EDA designs.
- Every gate below passes.

## Ownership

**You own:**
- string slicing and substring lowering;
- dictionary lookup and insert with text keys: `emit_dict.zig`, `emit_dict_span.zig`, `fuse_dict.zig`, `build_dict.zig`;
- `str_view`;
- the runtime's string and dictionary functions (`src/core/runtime/core_text.c`, `core_dict.c`).

**F1 owns:**
- TBAA metadata and every access's TBAA tag in `emit_llvm.zig`. Don't add or change tags; new accesses use the existing generic tags, and F1 will retag them at integration;
- element-store emission (`listSet`, `list_set_field`, `elements.zig`, `stores.zig`);
- `facts.zig`;
- integer arithmetic lowering.

If you must touch one of their functions, make the smallest change you can and list it in your report. Don't edit `src/` outside `src/core/`.

## Measuring (counts and cycles on your own CPU; the coordinator measures wall time on CPU 10 later)

- **Your measurement CPU is 6.** Use `taskset -c 6` and interleave the arms. PM's `experiments/parity-measure-20261008/tools/pstat.py` and `ladder.py` take `--cpu`. The machine is shared, so cycles are only comparable inside one interleaved run. Instruction counts are exact.
- **Reference binaries** (Zig ReleaseSafe/ReleaseFast, Rust with and without overflow checks): `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.tmp/pm/parity/work/bin/<program>.<arm>`, with arms listed in `../arms.json`. Read-only; copy them if you need them elsewhere.
- **Programs:** `bench/parity/suite/knucleotide.my`, `text_ops.my`, `bench/parity/lib/scan_*.my`, and all other parity programs for the no-regression check.
- **Lox and EDA:**
  - Lox: copy `/home/epentland/ai/canopy/mylang-worktrees/claude-copy-elim/.mylang-cache/lox` into your `.mylang-cache/lox`, without its `.tmp/`, then create `.tmp/lox-bench/tmp` in your worktree root; the harness looks for it.
  - EDA: copy `/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore/mylang` into `.mylang-cache/eda-src`.
  - `experiments/ce2-x-20261008/tools/` shows how CE2-X built and ran them; PM's `experiments/parity-measure-20261008/tools/prof.sh` shows its 4 Lox cells and 2 EDA designs.
- **Report:**
  - before and after instructions, cycles and allocations;
  - knucleotide's ratio against Zig ReleaseSafe;
  - the knucleotide inner loop's LLVM after;
  - text_ops and EDA instruction changes.

## Gates (every one must pass on your final commit; run them before declaring the exit)

A wrong answer is never acceptable.
1. **Build and repository gates:** `zig build` (Guardian), `zig build test --summary all` and `zig build fmt-check`.
2. **Conformance** against the frozen S5 references, debug and release, with leak and fact verification: **1518/0/0**.
   - Run `python3 experiments/new-core-s5-20261007/tools/qualify_merge.py --shards 64 --compiler zig-out/bin/mylang --install install --evidence <a fresh directory inside experiments/>`.
   - Never reuse an evidence basename: a reused name crashes on a stale `.mylang-cache/s5/integration-qualify/<name>/tmp`.
   - Move that evidence under your evidence directory afterwards.
3. **Frozen fuzz 9×50:** `experiments/new-core-s5-20261007/tools/fuzz_matrix.py --references experiments/new-core-s5-20261007/references/fuzz-v1.json.gz --new <a copy of your Debug zig-out/bin/mylang> --cases 50 --evidence <dir below experiments/> --jobs 3`. All 9 kinds must PASS. It needs a clean tracked tree.
4. **Lox:**
   - `python3 harness/lox_bench.py conformance --binary <your plain release lox binary> --engine both --stress -j 4` from your Lox copy: **974/974**;
   - the port's own tests, `mylang test .` in `ports/mylang`: **65/65**.
5. **EDA:**
   - all 34 cases' outputs byte-identical to the goldens;
   - `mylang test src --jobs 4 --max-frames 30000 --max-steps 4000000000 --max-memory 2G --cache-dir <yours>` in your `eda-src`: **310/310**.
6. **Parity:** every program's output equals its `.expected`.
7. **Counting:** counting on and off give the same output on every program you count.

**Every transformation needs regression tests,** including adversarial ones:
- **Inserts:**
  - a key inserted, then the source string changed or rebound, then the key read back; the stored key must be its own copy;
  - the same slice used as a key in two dictionaries.
- **Keys:**
  - non-ASCII text, and slices that split a multi-byte character, so Python's indexing semantics hold;
  - empty slices;
  - slices at the end of the string;
  - out-of-range slice bounds, which clamp as in Python.
- **Lookups:**
  - a key equal to an existing key but from a different source;
  - keys of exactly 8, 15, 16 and 17 bytes, for the inline compare;
  - dictionaries with deletions or an index, if you lift that restriction;
  - a view live across a call that might change the dictionary;
  - `break` and early return between the probe and the insert.

Put them in `test/core/*.my` and/or the core's Zig tests.

**Guardian rules:**
- every behavioural line under `src/` needs a test with `// spec: TAG` and a `SPEC.md` bullet; use `NEW-CORE-S1-*`;
- at most 7 struct fields and 6 parameters;
- `///` on every `pub` declaration;
- no import cycles; new files reachable from `guardian.toml` roots;
- no type-size ratchet growth.

## Rules

- **Builds** go through `scripts/build-slot.sh` (see `CLAUDE.md`). The machine is shared with other agents, with at most four build-heavy processes in total.
- **CPUs:**
  - never run heavy work on CPUs 2, 3, 10 or 11 (use `taskset -c 0,1,4-9,12-19` for runs);
  - take perf measurements only on CPU 6;
  - never take wall time on CPU 10.
- **Caches and `TMPDIR`** stay on disk inside your worktree, never in `/tmp`. Disk is tight, so delete scratch you no longer need.
- **Never end your turn to wait for background work.** The harness treats a turn that ends while you wait as the end of your run. Run long steps in the foreground, with a timeout of up to 600000 ms, and split anything longer into parts.
- **Never kill processes by pattern** (`pkill -f`). Kill only PIDs you started.
- **Evidence** goes in `experiments/s1-views-20261009/`: logs, before/after JSON (gzipped if large), and scripts. Keep it under 10 MB.
- **Commits:** one per step on `claude/s1-views`, with messages ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never merge into `main`, never push, and never touch another worktree or branch.
- **Stop and report** if:
  - a wrong answer cannot be fixed;
  - Guardian needs a ratchet acceptance;
  - a gate fails for a reason outside your change;
  - you would need more than a minimal change in F1's areas.
- **Your final reply** must contain the full report:
  - each step's commit;
  - before and after instructions, cycles and allocations, with knucleotide's ratio against Zig ReleaseSafe;
  - the no-regression table: every parity program, the Lox cells and the EDA designs;
  - every gate receipt;
  - why each view is safe: its lifetime and its source;
  - any touches in F1's areas;
  - remaining limits.

  Also write `experiments/s1-views-20261009/REPORT.md`. If the tool refuses the file, the reply is enough.
