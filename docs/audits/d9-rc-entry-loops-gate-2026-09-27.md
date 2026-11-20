# Joined entry and loop checkpoint

Frozen source `4e5c0cd6` passes the complete correctness gate. It joins
incoming record-field reads `fb4a19a9`, raw borrowed/immortal helper entries
`0aaf0ddb`, and fast-loop operand isolation `ee6e44e3` through real two-parent
merges, following the `368f0357` checkpoint.

| Check | Result |
|---|---|
| Debug compiler install | 19/19 steps |
| Main gate | 94/94 steps; 2,404 executed tests passed |
| QBE gate | 51/51 steps; 458/458 tests passed |
| Native build gate | 29/29 steps |
| Formatting | 2/2 steps |
| Whole-tree Guardian | 88 checks passed |
| Forced counted RC, QBE | 1,049 assertions across 179 programs |
| Forced counted RC, LLVM O3/full LTO | 1,049 assertions across 179 programs |

Both RC sweeps have zero failures, skips, cached verdicts, dropped files or
unloaded files. Source and HEAD stayed frozen throughout validation. The main
gate's raw total includes 24,587 shard skips; the executed count above excludes
them. Exit-zero Zig failed-command footers remain preserved in the raw logs.

An earlier install failed after the orchestrator removed inactive Zig cache
objects while leaving hash metadata referencing them. Clearing the remaining
inactive cache corrected the install; no source change was needed. The failed
install receipts and explanation are retained alongside the successful gate.

The immutable Debug compiler SHA-256 is
`52bff2acf09f3d0ef3739c707ea7e570c789d26cbc938b6a0a5615fed5133738`.
The [archive](../../experiments/d9-rc-entry-loops-gate-20260927/README.md)
contains summaries, raw logs, terminal statuses, compiler identity, drivers
and a verifier. Its `verify.py --live` also checks the immutable compiler.

The three isolated slices establish these instruction ratios against accepted
GC, using their separate documented bases:

| Workload | QBE | LLVM | Meets both 1.3× caps |
|---|---:|---:|---|
| Byte scanning, full 8 MiB × 16 | 1.105132× | 1.075882× | Yes |
| Lox binary trees, unchanged N10 | 20.239218× | 32.779326× | No |
| Schematic fixture | 11.143407× | 16.535304× | No |
| Schematic changed net | 11.120358× | 16.575372× | No |
| Schematic changed value | 11.117023× | 16.819194× | No |

See the [loop operand report](d9-rc-loop-operand-isolation-2026-09-27.md),
[incoming record report](d9-rc-caller-field-read-implementation-2026-09-27.md)
and [borrowed entry report](d9-rc-borrowed-readonly-entry-2026-09-27.md).
These are isolated measurements, not measurements of this combined compiler.
A fresh diagnostic of 30 non-Lox programs plus full Lox binary trees is in
progress. The unchanged 43 programs per backend, instruction geomean at most
1.0×, every row at most 1.3× and lower median peak RSS remain required for
acceptance. GC remains the default; main and devspeed are unchanged.
