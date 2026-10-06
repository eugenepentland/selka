# S2-X dictionary fact repair

Base: `090dabd5a6932a7c3beaec68248f9a35d4c637d7`, reached by a fast-forward of the
clean, locked dictionaries worktree. Existing package commits and caches were
preserved. The staged source tree qualified by these checks is
`69bd18dfbbf741cfb5cee7af40e11d4540278643`. Qualified source commit:
`0c6029d7`. No integration worktree source or index was edited.

The frozen full leak/verify sweep found a false dictionary length fact: after a
helper populated `fresh`, `dict_len(fresh)` asserted `[0,0]` while its actual
length was 27. `diagnosis.md` retains the original source identity, native
assertion and read-only reproduction commands. Four of the six new guest
regressions fail on the frozen pre-repair compiler (`regressions-before.txt`).

Dictionary copy and update transfers now distinguish an unknown call or
parameter input from a transfer that has not run yet. `pendingDict`, analogous
to `pendingList`, is shared by copies, updates and phi joins. Unknown inputs
settle to unknown length and hulls, weakening a loop phi instead of permanently
skipping its back edge. Existing widening and failure-to-converge behavior is
unchanged. The IR shape, runtime, ownership pass and frontend are unchanged.

Six guest tests cover unknown call inputs through copy, insertion, removal and
replacement, parameter-copy/replacement and the original text-slice/bump helper
failure. A direct IR test covers the actual `dict_copy` transfer into an empty
loop phi because source-level `dict.copy()` preserves its SSA value. The guest
fixtures run in debug, release and release with fact verification, under leak
checking, and their process statuses and JSON verdicts are checked. The first
held gate was cancelled to add the direct IR copy test; its log is retained as
`test-core-cancelled-for-copy-regression.txt`. Compiler source did not change
after the focused rebuild; the final core gate includes both new Zig tests.

The old oracle is the absolute protected accepted-72 installation at integration
`.mylang-cache/wave-b/baseline/mylang`, with its adjacent `qbe`. All native builds
use `scripts/build-slot.sh build`, private worktree caches and a disk TMPDIR.
The core gate additionally keeps the outer Gate lock alive through the Build
wrapper. Admission waits are excluded from command time. Each `.txt` log
contains the exact command, base commit, exit status, command time and RSS.

| Check | Command / evidence | Result |
|---|---|---|
| Rebuild | `record_fact_check.py --name build -- zig build core --summary all`; `build.txt` | exit 0, 1.57 s, RSS 318528 KiB |
| Focused leak/verify | strict `conformance_checked.py dictionary_hashing test/core/d_fact_inputs.my --jobs 1 --leakcheck --verify`; `focused.txt` | 14 matching, 0 mismatches, 3 precise refusals in both modes; exit 0, 6.85 s |
| Full ordinary comparison | strict `conformance_checked.py --set all --jobs 4 --why`; `conformance.txt` | 1224 matching, 0 mismatches, 316 precise refusals / 1540 in both modes; exit 0, 132.46 s |
| Own leak/verify | the 37 design dictionary/set files, `operand_snapshots`, and the three `test/core/d_*` fixtures; `own.txt` | 264 matching, 0 mismatches, 84 precise refusals / 348 in both modes; exit 0, 14.35 s |
| S0/S1 emitted code | `compare_code.py --stage s2-d-fact-repair`, then `inspect_fact_repair.py`; `code.txt`, `code-inspection.txt` | all 20 programs' function definitions identical to frozen integrated 090 controls; builds 4.22 s |
| Dictionary row emitted code | `inspect_fact_repair.py --rows`; `rows.txt` | all five rows' function definitions identical to frozen integrated 090 controls; exit 0, 2.60 s; no row requires remeasurement |
| Held core gate | `record_fact_check.py --name test-core --gate -- zig build test-core --summary all`; `test-core.txt` | 200/200 tests pass; exit 0, command 293.07 s (<300), wall including admission 298.11 s; test MaxRSS 205 M, compile MaxRSS 334 M (<2.5 G) |
| Dictionary fuzz | `fuzz_qualification.py --kind dict --cases 50 --seed 202610052`; `fuzz.txt`, `fuzz/summary.json` | qualified: 50 accepted, 750 comparisons, 1000 native runs; no mismatches, refusals, build failures, leaks, crashes or fact failures; 14 matching expected traps; exit 0, 317.51 s |
| Guardian | `guardian-check all . --full`; `guardian.txt` | all 88 checks pass; exit 0, 1.75 s |

The full S0/S1 comparison still includes the previously accepted NUM inline
parser helper additions relative to Wave A. The extra exact comparison against
the frozen integrated 090 definitions proves this repair changes none of those
definitions. Private `.ll` controls remain in caches; no file-hash manifest was
created.

The strict sweep wrapper is copied from the coordinator's repaired version.
Its documented empty-selection exception accepts status 3 only with a valid
`native-tests-v1` report, `tests: []`, and zero selected/executed/verdict counts.
Its 16 synthetic process/report cases pass; signals, empty stdout, general
status-3 errors and status/verdict disagreements remain errors. This harness
repair is separate from the compiler fact repair.

The source commit's normal Guardian hook passed with a cached whole-tree green
result and zero blocking checks. The coordinator owns integration and the
affected final S2-X reruns,
plus the single Guardian feedback entry for the whole task.
