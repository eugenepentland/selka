# FB1 external corpus receipts · 2026-10-08

The immutable FB1 compiler passed the saved native and current-language Lox/EDA
corpus checks. No compiler was rebuilt, no frozen answer was regenerated, and
the reserved `codex/frontend-fb1` source worktree was not changed.

## Identities

- Candidate compiler: `/home/epentland/ai/canopy/mylang-worktrees/codex-frontend-fb1/zig-out/bin/mylang`,
  SHA-256 `5ddab7ce39d576615f55676886252e4dbfff863d0d253cc003886a769c7b1a55`.
- Production source: `061f46aba144c00bf2094fcdada9a2c682696105`, with evidence-only
  FB1 HEAD `889943fa81a7c0c69a6452b0ab6c076b42b728cc` sharing its exact `src`
  tree `a45dd2386068c2d28ba2f042cc2a62837e661f12`.
- Lox source: `codex-frontend-fp2-lox` at
  `f44302d877dfc8a01b64673e70c44b9e0c49f063`.
- EDA source: `codex-frontend-fp2-eda` at
  `7e938b65a880339f0aa0d58f5805cd2cd2bbfe1b`.
- Saved S5 answer/compiler identity: SHA-256
  `ec4d76d2b57a0de47eda656571952dab90cc1aa3ddea822a327b945d3c464d03`.
  Its binary was read for identity verification and never executed in this task.

`input-identities.json` binds the frozen answer/test-reference hashes, source
commits, compiler bytes and copied collectors. `compiler-production-tree.json`
verifies the evidence HEAD and the immutable compiler's production source tree
are identical. The mode collectors validate all reference/source manifests,
compiler source membership/content and compiler bytes before and after their runs.

## Results

| Check | Result | Admitted command time |
|---|---|---:|
| Lox ReleaseFast native build | pass, fresh link, one reused unit | 1.082 s |
| EDA ReleaseFast native build | pass, fresh link, one reused unit | 6.789 s |
| Lox native conformance | 974/974, no failures or answer mismatches | 3.528 s |
| EDA native goldens | 34/34, no failures or answer mismatches | 2.416 s |
| Lox Debug, ReleaseFast, verify-facts | 65 tests + 13 configured cases per mode; directory 65 per mode | 29.011 s |
| EDA Debug, ReleaseFast, verify-facts | 310 tests per mode; directory 310 per mode | 162.371 s |
| Lox raw receipt audit | all 84 command reports verified | 0.217 s |
| EDA raw receipt audit | all 366 command reports verified | 0.220 s |
| Shared comparator focused regressions | 10/10 | 0.127 s |

Every mode retains the original commands' force, leak checking, cases, jobs,
timeouts and execution budgets. Failed, skipped, cached and unsupported counters
are zero. Per-file and directory membership, names, statuses, reasons, counters,
diagnostic fields and source manifests all match the saved answers.

Lox native conformance compares the complete 974-entry answer dictionaries,
including exact output/error hashes and rule/mode identities. EDA checks all
generated files against the 34 saved native answers and their source goldens.
The native output binaries retained their original hashes throughout execution:
Lox `9e6a5da3eb32379cf4ec5571fe6890b5c4f21dbd465451ac5b094644d4fd4335`,
EDA `1c49de6b0ab4b9e0d4eec8973d92de35c410dde097555592d989ed9dff53fda9`.
The native build receipts report `compiled=0`, `reused=1`, `program=linked`;
these builds do not establish cold-build or performance results.

## Configured report fingerprint proof

The Lox configured reports contain `tests[].source`, which is the BLAKE3
`core-test-settings-v4` fingerprint, not a file-content hash. The unchanged
`src/core/test_runner_receipt.zig` recipe hashes length-prefixed compiler identity,
entry/root and cases paths/bytes, Zig content identity, complete execution
options, native inputs and sorted keyed environment variables.

The original freezer's SHA-bound launch receipt explicitly supplies
`MYLANG_SLOT_DIR=/run/user/1000/mylang-slots` and
`MYLANG_TIMING_CPUS=2,3,10,11`. Together with `MYL_CORE_LEAKCHECK=1` and the real
CLI-generated host checkpoint
`MYLANG_HOST_LIMIT_CHECKPOINT=8858370048:18446744073709551615`, these reproduce
every frozen fingerprint exactly. No unknown environment input was waived.

The standalone `scripts/frontend_settings_hash.zig` witness independently
recomputes both fingerprints from the raw byte fields. The configured comparison
requires every input except compiler identity to be byte-equal, verifies each
of the 39 actual source fields against the computed candidate fingerprint, and
rekeys those verified fields to the canonical fingerprint with a fixed compiler
identity placeholder. All other JSON fields and all other raw output bytes are
compared unchanged. Source paths are identical and need no path normalization.

The S5 embedded compiler identity is
`684daf21ff6d228f070309b170a511d48bcf30dc691d20e1fb08639135bf87f6`;
FB1 is `2ca83cdad34673efa34062dab2ea87daf2cbe6acf8af24673e0a1d699fac4d7e`.
`settings-provenance.json` binds both immutable binary hashes to copied generated
identity modules, the identical receipt recipe and independently checksum-verified
tool memos. The guest tool content digest is
`51984741b695a32abdbf6396c86ec291fd980d5100d1536f0a341c8c05e7733b`.

`lox-tests-fixed/settings/*/configured/*.proof.json` retains every old/new input,
both recomputed hashes, the canonical hash and the witness command receipt.
`settings-negative-results.json` records actual BLAKE3 checks showing wrong
cases, compiler identity, budget and environment inputs cannot reproduce the
frozen hash. Focused tests also reject unproved project configuration, source
fingerprint corruption and launch ceilings, and preserve unrelated literal,
contract and provider fields. The real CLI produces the checkpoint; the
collector does not inject one.

The reusable optional proof currently requires the unchanged S5 receipt recipe,
same physical configured source/cases paths, a simple module root, no project
configuration and an unlimited launching address-space limit. Other inputs
fail closed and require an explicit recipe extension. Default comparisons remain
strict byte/JSON comparisons without fingerprint normalization.

## Retained evidence and timing

The final Lox authority is `lox-tests-fixed`; EDA is `eda-tests`. Both are
audited against the immutable references. Lox collector/helper/context/witness
self-hash guards and all compiler/source/reference guards are true. EDA's raw
full JSON/stdout/stderr comparison and immutable compiler/source/reference guards
are true. `fb1-lox-fixed-mode-audit.json` and `fb1-eda-mode-audit.json` audit every
saved raw report, including test counts and names.

The first Lox trial exposed the settings fingerprints: all tests passed, while
the comparator correctly rejected their full JSON/raw stdout differences. A
subsequent successful trial was superseded because queued admission overlapped
the last comparator source refinement. The final run uses fixed committed tools
and explicitly requires unchanged collector/helper hashes. Both earlier trials,
their raw receipts and the unsuccessful fingerprint search inputs are preserved
losslessly, with SHA/size/member manifests; they do not establish the final exit.

Native receipts/output files are in `native-lox.tar.gz` (2,923 verified members)
and `native-eda.tar.gz` (644 verified members), with answer JSON and SHA/size
manifests alongside them. Original native outputs remain in this worktree's
owned `.mylang-cache/frontend-fb1-external/native-results`. Large fingerprint
search inputs are preserved in `settings-search-trials.tar.gz` and owned scratch,
with an exact manifest. Archive verification compares every member's bytes and
membership before moving any original.

Every command is timed in `logs/`; heavy jobs acquire the benchmark compile
lock outside build-slot admission, and every build/test runs through
`scripts/build-slot.sh`, on CPUs `0-1,4-9,12-19`. Commands retain admitted affinity
and process snapshots. The initial Lox native queue waited 2,055.189 seconds
behind active benchmark builds; this was contention, while execution took
3.528 seconds. No step in this package exceeded five minutes uncontended.
No CPU-10 timing lock or reserved benchmark tree/cache was used or changed.

## Integration boundary

This package completes FB1's external corpus checks only. It does not declare
the integration branch's complete §5 exit, C2 policy probes, C3 performance or
CPU-10 measurements passed. The coordinator holds those gates and merges.
Results may be reused only for exactly the same immutable compiler/source
identity; other compilers must run their candidate checks against these saved
answers. No main merge or push occurred.

Tools-only commits are independently cherry-pickable before FB1 integration;
CLI/help commits remain separate and merge after FB1. Guardian's whole-tree
precommit gate passed 88/88 for the tool commits (about one second each), and
the coordinator is consolidating the required Guardian feedback entry.
