# Faster debug code generation through LLVM: package DL, 2026-10-07

Status: **ready for Codex after the S4 exit.** It is one package, about 6–10 hours. It
changes only debug builds; release output stays byte-identical. The user asked for it on
2026-10-07, as the cheap step before deciding on a custom debug back end.

## Launch instruction (for Codex)

> After the S4 exit report, implement package DL of
> `docs/audits/debug-llvm-plan-2026-10-07.md` (branch `claude/debug-llvm-plan`) on
> `codex/debug-llvm`, created from the S4 exit commit, merging `claude/debug-llvm-plan`
> first. Follow the S4 plan's §7 rules, including "How much qualification". Never merge
> into `main` and never push. Finish with DL's report (§6) and stop.

## 1. Why

**Debug builds are the edit loop.** Under S4-1a, `mylang test` and `build` without
`--release` emit one codegen unit per module. A one-function edit recompiles that module's
unit with LLVM `-O0`.

**What a debug edit costs.** These are projections from the S4 spike; S4-X measures the
real numbers.

| | 48k lines | 192k lines |
|---|---|---|
| Check | ≤ 0.45 s | about 1 s or more |
| Core pipeline, whole program | 0.3 s | 1.35 s |
| LLVM `-O0` on the changed unit | 0.3 s | 0.7 s |
| Link | 0.03 s | 0.05 s |

LLVM is about a quarter to a third of a debug edit, and nearly all of a cold debug build.

**Where LLVM `-O0` spends its time.** This is the 192k-line spike program, 122 MB of text,
22.5 s on one core (`experiments/debug-llvm-20261007/`):

| Step | Time | Share | Cause in our output |
|---|---:|---:|---|
| Parsing the text | 4.5 s | 20% | about 635 bytes of LLVM per source line |
| DAG instruction selection | 4.9 s | 22% | FastISel gives up on two patterns (below) and falls back to SelectionDAG |
| Assembly/object printer | 2.3 s | 10% | |
| Live DEBUG_VALUE analysis | 1.5 s | 7% | We emit no variable locations, only `DISubprogram` and `DILocation`, so this is pure overhead |
| AlwaysInliner | 1.4 s | 6% | 9 `alwaysinline` helpers (`emit_llvm`, `emit_dict`, `emit_dict_span`, `emit_number`) |
| Fast register allocator | 1.1 s | 5% | |

**The two FastISel failures,** both in debug code:
1. **Vector bit tricks:** `bitcast <N x iN> to iN` followed by `cttz` or `ctlz`, from
   inlined lookup helpers.
2. **First-class aggregates:** `insertvalue` and `extractvalue` on `{ptr, i64}` and
   `{i64, ptr, ptr}`, and calls that pass or return an aggregate by value.

In the 4.8k-line sample, three of every module's six functions fall back.

## 2. Scope

**In:**
- the emitter's debug-mode output (`src/core/emit_*.zig`, debug paths only);
- the debug `zig cc` flags in `src/core/driver.zig`;
- the runtime helpers a debug build calls instead of inlining.

**Out:**
- **Release builds.** Their `.ll` must stay byte-identical (§5).
- **Core IR.** `ir.zig` stays frozen.
- **A custom back end.** DL's report says whether one is still worth it (§6).

## 3. Steps

Each step is one commit with its own before/after measurement. Keep a step only if it
pays: at least 3% of debug LLVM time, or a simpler emitter, with every gate in §5 green.
Revert a step that doesn't pay, and give it one line in the report.

1. **Baseline at the S4 exit.**
   - Take `-ftime-report` for the 48k and 192k synthetic programs (S4's
     `gen_program.py`), debug, one process on CPU 10.
   - Take the FastISel fallback inventory (`-Rpass-missed=sdagisel`, normalized as in the
     evidence README) over:
     - the synthetic programs;
     - the 46 rows;
     - the five applications;
     - the Lox port and the EDA slice.
   - Also record the debug edit loop and the debug test-execution times listed in §5.
2. **Make debug code FastISel-selectable.**
   - **Aggregates:** in debug builds, pass and return them through memory, or as separate
     scalars. One rule for every program function. Calls into the C runtime keep the C ABI.
   - **Vector bit tricks:** use the scalar or out-of-line form of those helpers.
   - Then fix whatever the inventory shows next, largest first.
   - **Target:** no fallback in the rows, applications and ports. Any that remain are
     listed with their reason.
3. **No forced inlining in debug.** The `alwaysinline` helpers become ordinary internal
   functions in debug builds; release keeps `alwaysinline`.
4. **Line tables only.**
   - Mark the debug compile unit `emissionKind: LineTablesOnly`, and measure Live
     DEBUG_VALUE analysis.
   - Trap and error-trace text must stay byte-identical: the runtime reads `.debug_line`
     and subprogram names.
5. **Unwind tables.** Measure debug units without asynchronous unwind tables. Keep this
   only if traps, traces, the leak checker and any native unwinding the runtime does all
   behave the same.
6. **Less text.**
   - Shorter local value names, and no redundant instructions in debug output.
   - Measure parse time, and keep only what does not slow debug execution beyond §5.

## 4. Owns

- `src/core/emit_*.zig`, debug paths only;
- the debug flags in `src/core/driver.zig`;
- the runtime helper functions debug builds call (`src/core/runtime/`);
- evidence under `experiments/debug-llvm-<date>/`.

## 5. Gates

**Release is untouched.**
- Release `.ll` is byte-identical before and after for the 46 rows, the five
  applications and the conformance corpus.
- So the 46-row timing gate holds by construction, and timing is not rerun.

**Debug is correct:**
- `test-core`;
- conformance at 0 mismatches in every mode, with the leak and verify sweeps;
- trap and error-trace output byte-identical;
- 50 fuzz cases per kind with S3's `fuzz_matrix.py`;
- the Lox and EDA test suites green.

**Faster to compile.** On the 48k and 192k synthetic programs, CPU 10, report:
- debug LLVM time for the whole program in one process;
- debug rebuild after a one-function edit.

If the whole-program debug LLVM time drops by less than 10%, stop and report.

**Not slower to run.** Debug execution time of the conformance suite and of the Lox and EDA
test suites, compile time excluded, may rise by at most 10%. Report the net effect on
edit-then-test: the rebuild after a one-function edit plus running the affected tests.

**S4's rules** for evidence size and qualification tools apply (S4 plan §7).

## 6. Report

- each step: kept or reverted, with its measured effect;
- the before/after `-ftime-report` tables;
- the remaining FastISel fallbacks;
- the debug edit loop and test-execution numbers;
- **a recommendation on a custom debug back end.**
  - Estimate how much of a debug edit and of a cold debug build LLVM still takes after DL.
  - The custom back end (Core IR → x86-64 machine code, ELF objects, DWARF line tables)
    was estimated on 2026-10-07 at 40–80 hours, plus maintaining two back ends.
  - It is worth building only if LLVM still dominates cold builds or first-time test runs.
