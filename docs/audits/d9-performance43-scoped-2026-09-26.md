# D9 joined scoped-receiver performance, 2026-09-26

The complete historical 43-key set passes the stage 3 instruction limits on
QBE but fails on LLVM. All 86 output/SVG comparisons pass. This frozen
diagnostic precedes the indexed setter and global-table hash-hoist work;
it does not establish final default acceptance.

| Backend | Instruction geomean | Programs above 1.3× |
| --- | ---: | --- |
| QBE | 1.029279234 | None |
| LLVM | 1.071343974 | lox/vm/binary_trees 1.612312×, lox/vm/closures 1.443576×, lox/vm/method_call 1.448107× |

The set is exactly 27 historical parity keys, three schematic inputs and
13 Lox VM scripts per backend. It excludes the supplemental recursive-tree
variant and tree interpreter. The baseline is exact `60b668cf`, value mode
off, using the original recorded binaries and compiler SHA
`48427e9ac1c01b74e60d1b4c098c8fc149a6b5fef3c07e110c7fb4ba16cbb545`.
The candidate compiler source is `b6328bcd`, Debug, SHA
`7509c8733b37eaef9da45e06ef6ca41b6048f236664e3aa7727e23d45964f32d`.
Guest source is `d7f4cf85`, including pure-box reads, scoped nested receivers,
correct assignment RHS handling, scalar instance/class readers and late closure
publication. Compiler code is identical between those source commits.

The harness uses `pc.py`'s historical sizes and flags, explicitly enables
value semantics on candidate builds, pins instruction measurements to CPU 2,
and alternates baseline/candidate order over three samples. Every reported
ratio uses median instructions. LLVM uses O3 and full LTO. Schematic declared
provider functions are emitted separately per side. Compiler, source, provider,
binary and IL hashes, exact build commands and raw output/perf observations
are retained in [measurements](evidence/d9-performance43-scoped.json) and
[build evidence](evidence/d9-performance43-scoped-builds.json).

A separate profiling command accidentally rewrote metadata in the shared
baseline LLVM Lox executable. The harness stopped at its SHA assertion before
measuring those bytes; 61 completed samples were retained. The exact original
binary was recovered and verified, then all 58 baseline executables were copied
into private scratch and checked against their recorded hashes. The remaining
25 samples completed without changing the compiler, guest source or flags.
No altered-baseline sample contributes to the table. Recovery evidence is
`d9-nested-cow/.tmp-nested/method-profile/recovery.log`; the retained harness,
partial result, resumed log and private baseline live under this worktree's
`.tmp-perf43-scoped/`.

The compiler combination independently passed its four-step gate and
110 newly executed stressed receiver cases plus 44 exact switch-off IL checks.
Later indexed work has its own gate and evidence; neither those later tests
nor projected improvements replace the complete final sweep.
