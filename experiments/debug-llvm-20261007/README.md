# Debug LLVM measurements, 2026-10-07

These are the starting measurements for package DL
(`docs/audits/debug-llvm-plan-2026-10-07.md`).

**Inputs.** The S4 spike's synthetic programs, emitted by `mylang-core` built from
`8918de74` (S3 Wave B base). They are the files `syn4800-debug.ll` (about 192k source
lines, 122 MB of LLVM text) and `syn120-debug.ll` (about 4.8k lines), from the
`claude-new-core-s4-design` worktree's `.mylang-cache/s4/work/`. The emitter has changed
since then, so DL measures again at the S4 exit.

**`syn4800-debug-O0-time-report.txt`:**
- **The command:** `taskset -c 12 zig cc -c -O0 syn4800-debug.ll -ftime-report`.
- **The result:** 22.5 s in all, 22.8 s wall with the report's overhead. The spike
  measured 14.2 s on CPU 10 without the report.
- **Front end (parsing the text): 4.5 s.** "Optimizer" 1.6 s, of which `AlwaysInlinerPass`
  is 1.4 s. Machine code generation 16.5 s.
- **Within code generation:**
  - X86 DAG→DAG instruction selection 4.9 s (FastISel fell back);
  - assembly printer 2.3 s;
  - Live DEBUG_VALUE analysis 1.5 s;
  - fast register allocator 1.1 s.

**`syn120-fastisel-missed.txt`:**
- **The command:** `zig cc -c -O0 syn120-debug.ll -Rpass-missed=sdagisel`.
- **The result,** normalized: every FastISel failure is one of two patterns.
  - **Vector bit tricks:** `bitcast <N x iN> to iN` plus a `cttz`/`ctlz` call, from inlined
    lookup helpers.
  - **First-class aggregates:** `insertvalue` into `{ptr, i64}` or `{i64, ptr, ptr}`, and
    calls that pass an aggregate by value.
- **The effect:** three of the six functions in every synthetic module fall back to
  SelectionDAG.
