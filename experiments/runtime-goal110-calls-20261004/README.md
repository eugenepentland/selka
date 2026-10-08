# Bounded invariant-loop copy selection

Candidate production commit: `5dc31c3af5114938fe1c92fc72941efd0b3074c3`.
Baseline guests: production `730a86e6`, preserved in the runtime harness worktree.
The host compiler is Debug; both guest backends are ReleaseFast, and LLVM is
effective LLVM at optimization 3 with full LTO. This directory contains
diagnosis, correctness, static costs and an exploratory timing screen. It is
not a current-fastest acceptance report. The candidate is **rejected for
integration** because its LLVM record-update and fallback regressions outweigh
the limited LLVM gains; QBE gains do not satisfy the primary LLVM goal.

The frozen compute program has an immutable selector inside each per-element
loop. Before this change, LLVM still reloads that selector at `0x102ceb9` and
dispatches through the table at `0x102ced3` after the inner-loop header
`0x102cead`. A suspected branch-attribution problem was retracted before any
production edit: the unswitch pass runs before original labels are elided.
The actual refusal was the existing all-or-nothing copy budget.

The temporary diagnostic compiler identified a certified 11-literal loop at
head 553/backedge 1035. Its native region was 100,678 bytes, and the cumulative
renamed copies reached 209,406 bytes, exceeding the unchanged twice-region cap
of 201,356 bytes. `diagnostic-receipt.json` pins that temporary compiler, exact
patch and emission command. It is pre-production diagnostic evidence. The
comment-captured `before-rewrite.ssa` subsequently passed through normal output
cleanup: it is illustrative, not a byte-exact pre-pass dump (571,734 bytes,
438 fewer than the diagnostic's exact 572,172-byte input metric).

The candidate constructs exact renamed copies, sorts by byte cost with source
ordinal as a deterministic tie-breaker, and emits only the cheapest prefix
that fits every existing budget. Those budgets remain 256 KiB absolute, twice
the original region, and half the whole function with a 4 KiB minimum allowance.
Only selected values get guards and copies. Other certified and unknown values
retain the complete original loop, and zero fitting copies returns the exact
original input. Certification, joins, frame/step admission, traps, error traces,
overflow and bounds behavior are unchanged.

The actual frozen guest's frontend fragment selects 10/11 certified values in
order `0,1,7,6,8,4,10,9,11,5`, totaling 182,385 renamed copy bytes. Certified
value 2 and uncertified value 3 retain fallback. `actual-emission-receipt.json`
and `before-actual-emission-receipt.json` pin the actual cached fragments used
for the guest builds. Their entry IL grows 510,140 → 693,099 bytes (+35.86%).
The earlier derived `compute-inspection.my` removes the module declaration
solely for static CLI emission; it was never used for guest timing.

`llvm-dispatch-static.json` and `static-dispatch.py` inspect the pinned ELF
table at `0x1009e90`. Candidate dispatch at `0x102d081` occurs once per batch,
before the selected inner loops. All ten selected direct inner-loop graphs
have no indirect jump before the shared batch-fold block `0x102ea40`. The two
excluded values enter the shared original fallback at `0x102d8dc`, where
indirect dispatch remains. The static graph excludes cold external edges,
helper bodies and indirect fallback targets; it is neither a dynamic instruction
count nor a kernel-cost estimate.

| Static artifact | Before | Candidate | Change |
|---|---:|---:|---:|
| LLVM entry bytes | 20,050 | 25,575 | +27.56% |
| LLVM whole guest `.text` | 169,554 | 175,074 | +3.26% |
| LLVM entry instructions | 4,148 | 5,339 | +28.71% |
| LLVM entry stack allocation | 728 | 808 | +80 bytes |
| QBE entry bytes | 43,823 | 53,270 | +21.56% |
| QBE whole guest `.text` | 204,125 | 213,581 | +4.63% |
| QBE entry instructions | 9,429 | 11,621 | +23.25% |
| QBE entry stack allocation | 2,968 | 2,584 | −384 bytes |

All static measurements include the whole entry and untaken paths. Register
reference counts in `static-sizes.json` do not assert executed stack accesses.

Correctness and build qualification:

- The final focused invariant-loop unit command returned exit 0; Guardian
  selected 17 tests and reported 17 passed. The new cost fixture puts an
  expensive literal first, proving cost reordering and deterministic ties.
  A real dynamic partial-admission program asserts `0 < selected < 3`, runs
  every certified literal and an unknown value, zero trips, bounds/overflow
  traps and prior effects, and compares full process status/stdout/stderr.
- Actual frozen compute guests passed 108 independent checksum inputs per
  backend (216 total), including both frozen sizes, multiple seeds and nearby
  dimensions. `guest-build-qualification.json` pins commands, manifests,
  compiler, source, clock, binary hashes and input coverage.
- The unchanged eight-form Boolean/CFG producer join diagnostic passed
  144 inputs and 432 guest executions across accounted QBE, fast QBE and actual
  LLVM. Exact status, stdout, full stderr and independent oracles matched.
  This is Boolean producer joining, not native string joining.
- Independent reviewer snapshot replay passed two allocator-failure scenarios
  over successful rewriting and zero-fitting refusal. That replay did not
  measure runtime performance.
- Host/commit full Guardian gates passed all 88 checks. Diagnostic-only
  logging and formatting changes were removed. Guardian feedback is being
  consolidated by the parent agent in its separate repository.

The focused test log contains a Zig `failed command: ... --listen=-` line
after `Guardian PASS — 17 passed`, although the parent shell command returned
exit 0. `execution-status.json` preserves the observed exit separately; this
misleading line is reported as tooling feedback, not a test failure.

The five-round selected timing screen and fallback sentinel reuse exact
production iteration/seed plans but measure fresh same-session before/candidate
samples. Raw sample order, checksums, kernel/wall times, binary identities,
per-sample cgroup/frequency snapshots and paired bootstrap intervals are
retained. Historical samples are never paired, current-fastest references are
not measured here, and independent confirmation is required.

The selected screen ran 2026-10-04 01:54:00–01:54:51 UTC, followed by the
fallback sentinel at 01:55:45–01:55:53 UTC, in the parent-approved quiet window.
Both commands returned exit 0. Every sample matched the independent checksum.
The tables below report candidate/before ratios; intervals are exploratory
paired bootstrap 95% intervals over the five fresh measured rounds.

| Case / size | LLVM ratio [interval] | QBE ratio [interval] |
|---|---:|---:|
| call_direct / small | 0.910 [0.908, 0.912] | 0.238 [0.237, 0.239] |
| call_direct / large | 0.926 [0.872, 0.931] | 0.226 [0.225, 0.226] |
| option_handle / small | 0.955 [0.948, 0.962] | 0.228 [0.226, 0.230] |
| option_handle / large | 1.039 [1.033, 1.040] | 0.228 [0.228, 0.229] |
| result_propagate / small | 0.999 [0.977, 1.009] | 0.323 [0.322, 0.324] |
| result_propagate / large | 1.038 [1.030, 1.066] | 0.345 [0.344, 0.346] |
| record_update / small | 4.048 [4.023, 4.223] | 0.556 [0.553, 0.558] |
| record_update / large | 4.258 [4.238, 4.279] | 0.543 [0.542, 0.545] |
| branch_predictable / small | 1.366 [1.343, 1.402] | 0.646 [0.636, 0.648] |
| branch_predictable / large | 1.641 [1.285, 1.667] | 0.630 [0.629, 0.634] |

No reference binaries were changed. The result does not recommend a
benchmark-specific exclusion. Subsequent investigation must explain the
actual lowering regression and retain this rejected candidate's evidence.

Large raw artifacts are stored as deterministic gzip files. `archive-index.json`
records both raw and compressed hashes; the uncompressed local inspection
files are intentionally not committed. `gzip -dk FILE.gz` restores a raw copy.
