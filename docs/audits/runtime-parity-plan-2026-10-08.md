# Runtime parity after copy elimination: the plan to 1.1× (2026-10-08)

**Status.**
- Written by the coordinating Claude session at the user's request ("write up the plan and have an agent start getting the measurements").
- Wave PM (measurement) runs now. The waves after it are sketched here, and PM's data will finalize them.
- **Base:** `claude/copy-elim-2` `2141c4f6b`, the CE2 integration with sret sharing off. CE2-X's re-run qualifies and times it, and it merges into `main` on the user's go.

## 1. Where it stands

These are CE2-X's first timing pass. It ran on CPU 10 under the lock, with medians of the paired runs. Its "new" compiler had sret sharing on. Sharing changes only the rows' `record_pass` and attributes, so the re-run's numbers will replace these.

| | vs Zig ReleaseFast | vs Zig ReleaseSafe | vs Rust | vs Rust with overflow checks |
|---|---:|---:|---:|---:|
| parity, 27 programs, geomean | 1.12× | **0.93×** | 1.15× | 1.03× |
| parity programs at or under 1.1× | 16 of 27 | 18 of 27 | 12 of 24 | 13 of 24 |
| EDA, 34 designs | 1.25× | 1.14× | 1.13× | — |
| Lox tree-walker, 13 cells | 1.62× | **1.00×** | 1.26× | — |
| Lox VM, 13 cells | 2.96× | 1.98× | 2.02× | — |
| the 46 rows | — | about 0.4× | about 0.56× | — |

**Over 1.1× against Zig ReleaseSafe:**
- `matmul` 2.66;
- `text_ops` 2.51;
- `knucleotide` 2.07;
- `str_build` 1.76;
- `nbody` 1.71;
- `scan_split` 1.40;
- `sieve` 1.16;
- `bytes_scan` 1.15;
- `sort_quick` 1.11.

**Over 1.1× against Rust with overflow checks:**
- `str_build` 2.04;
- `knucleotide` 1.72;
- `sort_builtin` 1.68;
- `nbody` 1.49;
- `matmul` 1.46;
- `sort_quick` 1.38;
- `calls` 1.35;
- `text_ops` 1.34;
- `sieve` 1.32;
- `intloop` 1.22;
- `fib` 1.14.

**Variant arms:** `fannkuch_redux` `my-array` is 3.27× Zig ReleaseFast and `my-tuned` 2.72×. They were 0.87× and 0.96× on the old core.

**Copies are no longer the main cost.** Since VP3 this morning, Lox bytes copied went from 1.28 TB to 7.3 GB and EDA's from 40.7 GB to 1.08 GB. The Lox VM now copies 27 bytes per dispatch, against 6,394 this morning.

## 2. Targets

The user decided on 2026-10-04 (L1) to gate on Zig ReleaseSafe, the same safety contract: mylang keeps bounds checks, overflow checks and counts. Zig ReleaseFast and plain Rust are the stretch.

- **Gate:**
  - every parity program, EDA and the Lox tree-walker at or under 1.1× of both Zig ReleaseSafe and Rust with overflow checks;
  - the Lox VM at or under 1.5× of Zig ReleaseSafe.
- **Stretch:**
  - the parity geomean at or under 1.0× Zig ReleaseFast;
  - EDA at or under 1.1× Zig ReleaseFast;
  - the Lox VM at or under 1.5× Zig ReleaseFast.
- **No language change for speed.** Facts stay optimizer-only, the rule from the values-and-keys plan: the compiler uses what it can prove, and the programmer writes nothing new.

## 3. What is left: five levers (hypotheses for PM to measure)

1. **Checks that block optimization.**
   - **What:** bounds and overflow checks in inner loops. They add instructions and stop vectorization.
   - **Evidence:**
     - `fib` is level with Rust with overflow checks (0.90×), so its gap to unchecked Rust is overflow checks.
     - The 2026-10-04 ideal-C ladder on `integer_math` went from 1.9× Rust to 0.3–0.5×, once a single fact (the list elements' range) let the checks and the floor-division fix-ups go.
   - **Likely programs:** `matmul`, `sieve`, `nbody`, `intloop`, `sort_*`, `calls`, `fib`, and the Lox VM's stack.
2. **Header reloads.**
   - **What:** each list access reloads the data pointer and length, because LLVM cannot prove that nothing else changed them. Value semantics guarantees that a list the loop does not write does not change. `noalias`, TBAA scopes or `invariant.load` metadata could carry that guarantee to LLVM.
   - **Evidence:**
     - `matmul` runs 2.6× Zig's instructions at an IPC of 2.03, against Zig's 3.19.
     - The 10-04 audit saw the length, data pointer and kind reloaded every iteration.
3. **Uniqueness tests and count updates.**
   - **What:** every list store and append tests uniqueness first.
   - **Evidence:**
     - `str_build` has 16 M inline tests, and is 2.0× Rust with overflow checks.
     - The Lox VM tests and counts on every push and pop.
   - **Hypothesis:** most of the VM's 2× over Zig ReleaseSafe comes from these.
4. **Strings and dictionaries.**
   - **What:** substrings and split pieces are allocated, and hashing and probing may be slow.
   - **Evidence:**
     - `knucleotide` (2.1× Zig ReleaseSafe) uses substring keys.
     - `text_ops` (2.5×).
     - `scan_split` (1.4×) has 9× Zig's cache misses and 8× Zig's memory.
     - EDA's remaining gap is mostly parsing: each design takes 28–80 ms.
5. **Regressions and leftovers:**
   - the fixed-array variants (`fannkuch` `my-array` and `my-tuned`; their IR has 29 `memcpy` and 19 `memmove`);
   - the Lox VM's frame reloads (P3 1.6 GB) and `heap.my:124` (P4 1.5 GB);
   - EDA's push (P6 0.44 GB; needs a payload-destination ABI);
   - sret sharing, done again without dropping `noalias`: load every field, then store.

## 4. Wave PM: measurement and attribution (now; one agent, about 6–10 h)

Branch `claude/parity-measure`, worktree `mylang-worktrees/claude-parity-measure`. Evidence goes in `experiments/parity-measure-20261008/`.

**PM-1. Counters for check traffic.** Extend `--counters` (`docs/tooling/counters.md`, `src/core/emit_count.zig`, `count_runtime.zig`) so that a counting build also records, per function and per site:
- bounds checks executed;
- overflow checks executed;
- division and shift checks;
- uniqueness tests, which already exist; also report them per instruction retired.

Retains and releases already exist; report them per instruction too.

The ordinary build must not change: check that the generated LLVM is identical with counting off. Spec tags `NEW-CORE-COUNTERS-6…`.

**PM-2. Profiles.**

Programs:
- the Lox VM: `fib`, `string_equality`, `invocation`, `method_call`;
- the Lox tree-walker: `invocation`, `equality`;
- EDA: `rds3+flat` and `labstation`;
- every parity program over 1.1× in §1, plus `fannkuch` `my-array`.

For each program:
- **Compare with the references:** `perf stat` (instructions, cycles, IPC, branch misses, L1/LLC misses) for mylang against Zig ReleaseSafe, Zig ReleaseFast and Rust (and Rust with overflow checks where it exists), from the same benchmark harnesses' binaries.
- **Find the hot code:** `perf record` and `perf annotate` of the hottest functions.
- **Classify the extra instructions:** checks, count traffic, uniqueness tests, header reloads, calls, allocation, hashing, other. Use PM-1's counters plus annotation.

**PM-3. Ideal-C ladders** for four kernels:
- the `matmul` inner loop;
- one Lox VM step (`OP_GET_LOCAL`, `OP_ADD`, push and pop);
- `knucleotide` counting;
- `scan_split`.

Each rung adds one fact or transformation, built with `zig cc -O3` and checksummed against the mylang output. The rungs:
- bounds checks gone, or hoisted;
- overflow checks gone;
- header loads hoisted;
- uniqueness test hoisted;
- count traffic gone;
- views instead of allocations.

That gives each lever's upper bound on that kernel.

**PM-4. The ranked table and the wave plan.** For each lever:
- the programs it moves, and the measured upper bound;
- where the needed fact comes from;
- the estimated work;
- the wave.

Then propose the lane split for waves F, U, S and R (§5), with exits.

**Measurement rules:**
- **No wall-time timing on CPU 10 while CE2-X runs** (until its report). After that, take wall time only through the CPU-10 lock, and only to confirm a ladder rung.
- **Attribution uses instruction counts and perf events** on one fixed P-core (CPU 8 suggested). Interleave the arms, and treat cycles as relative within one run: the machine is shared.

**Exit:** PM-1 lands with the CE gates. PM-2 through PM-4 are in the report, with the ranked table.

## 5. The waves after PM (to be finalized from PM's table)

| Wave | Levers | Likely targets | Rough size |
|---|---|---|---|
| F, facts | 1, 2: range facts that drop or hoist bounds and overflow checks (loop versioning where needed); header invariance metadata | `matmul`, `sieve`, `nbody`, `intloop`, `sort_*`, `calls`, `fib`, Lox VM stack | 2 lanes, 12–20 h each |
| U, uniqueness and counts | 3: hoist uniqueness tests out of loops; drop retain/release pairs that borrow inference misses | `str_build`, Lox VM, `nbody` stores, `bytes_scan` | 1–2 lanes, 10–16 h |
| S, strings and dictionaries | 4: substring and split views; hashing and probing; small strings stored inline | `knucleotide`, `text_ops`, `scan_split`, `sort_builtin`, EDA parsing | 2 lanes, 12–20 h each |
| R, regressions and leftovers | 5 | `fannkuch` arrays, Lox frame reloads, EDA P6, sret sharing | 1 lane, 8–12 h |

Each wave runs like CE and CE2: lanes in their own worktrees, then a coordinator integration (X). The integration covers the CE gates, fuzz 9×200, counters, and CPU-10 timing against the previous integration. Its exit is that nothing is slower than 1.03× beyond noise.

## 6. Gates (every lane and merge)

- **Repository:** `zig build` (Guardian), `zig build test --summary all` and `zig build fmt-check`.
- **Conformance:** 1518/0/0 in debug and release, with leak and fact verification (`qualify_merge.py`).
- **Fuzz:** the frozen matrix, 9×50 per lane and 9×200 at the integration.
- **Lox:** 974/974 and the port tests (65).
- **EDA:** 34 goldens and 310 tests.
- **Parity:** output equal to `.expected`.
- **Counting:** the same output with counting on and off.
- **Wrong answers are never acceptable.** CE2-X's merge found one from two individually correct lanes (NEW-CORE-CE2-MERGE-1), so every merge runs the gates again.

## 7. Order and expected time

**Order:**
1. PM (now).
2. Then F and S in parallel; they touch different code.
3. U.
4. R, alongside any of them.

**Expected time:**
- PM: 6–10 h.
- F, U, S and R together: about 60–100 lane-hours, about 3–5 days of wall time at two to four lanes. That is an estimate until PM's table.
