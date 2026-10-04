# LLVM-only bounded floor remainder, 2026-10-04

Source `df09fb4bcb57a58080543cda693554906d90105e` is a three-file successor to
`5e97db47f08f667d97419abafd098df263a2aec3`. It keeps the previously reviewed
magnitude/bias proof and LLVM lowering unchanged. QBE returns before allocating
a temporary, then uses its original signed literal-divisor recipe. The shared
optional planner metadata remains; no guard, admission or fallback changes.

This backend choice follows the archived5e repeated12% QBE nested-large cost.
That diagnosis found changed stack offsets and a16-byte larger frame, with
unchanged nested arithmetic/register sequence and unchanged native routines.
It supports a backend cost decision; no microarchitectural cause is claimed.
The full5e source, static and timing archive is retained separately in
`experiments/runtime-goal110-bounded-rem-20261004`, commit
`bdcfac1e8751982fd4ac1dafdc3f93e21d94bdc5`.

The final source passed58 focused tests and88 whole-tree Guardian checks,
actual process exit0 for both. The first run passed56/58 and failed two tests
that still required biased QBE emission. Their policy attribution was repaired:
wide-bias, exact endpoint and detached-reference execution tests explicitly
select LLVM scalar policy executed by QBE. These are distinguished from actual
LLVM ELF evidence. The38 complete native pairs pass exact full-run equality
and direct result/status/output/trap assertions, with33 successes and5 failures.
The new QBE refusal test verifies zero output/temporary allocation before the
old recipe, then compares every old recipe byte and temporary number.

The official host is Debug; all24 guests retain ordinary ReleaseFast policies,
LLVM O3/fullLTO and ordinary QBE. Frozen external guests are reused by verified
identity. Fresh720 checksum qualifications and516 correctness holdouts passed;
these diagnostics discard elapsed values. Inputs/outputs and exact commands,
source/host/guest/log hashes are retained. Guardian policies are unchanged.

Every LLVM guest runtime image equals its5e counterpart and every QBE guest
runtime image equals its G4/6cf counterpart across compute, collections, text
and legacy. Comparison includes allocated section metadata/content, program
headers, entry addresses and all LOAD bytes/virtual addresses. Each executable
differs only at byte40 of the mapped nonexecutable ELF header (e_shoff); debug
and file metadata may differ, and whole-file hashes explicitly differ.
Comparison probes accept only unchanged images and an outside-image section
table relocation, and reject instruction, LOAD address and other mapped-header
changes. They modify disposable copies and verify the original is unchanged.

No successor timing was run. Exact runtime-image identity supports transferring
the5e frozen LLVM mechanism evidence (repeated filter small/large ratios
0.9401/0.9256 and small sort0.9482), while QBE retains the G4 runtime images.
No new goal pass or independent normal confirmation is claimed. The actual
LLVM boundary evidence for5e remains separately attributed to that source;
this successor preserves its LLVM proof and emitted recipe.

`archive-index.json` contains portable snapshots of all11 bounded-bias source
files, the exact5e-to-successor patch and raw receipts/logs compressed without
changing bytes. `verify-archive.py` checks archived relationships independently
of the receiving checkout's production files; `--live` additionally checks the
pinned receipt's source root/artifacts and recomputes all eight comparisons.
Static helpers use read-only parsing and never rewrite an input ELF.
