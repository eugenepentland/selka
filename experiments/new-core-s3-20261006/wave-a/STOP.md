# Historical S3 Wave A rebuild hold, 2026-10-06

**Superseded by the user's review and resume instruction.** The user approved
S3-0 and narrowed the rebuild rule to uncontended `zig build core`. The plan
amendment is committed as `427f2f25`; the 12-second old-compiler rebuild below
does not meet that amended stop condition. S3-0 is committed and integrated in
`e39ad11d`. S3-L corrections and qualification are complete and integrated in
`f5ba28e5`. The completed Wave A review is recorded in [REPORT.md](REPORT.md);
Wave B still requires a separate go.

The remainder is the original checkpoint record, retained as historical
evidence. Its branch states, outstanding fixes and authorization statements
describe the hold, not the resumed work.

Wave A is incomplete. The S3 plan's §6 inherits this S2 stop rule:
"a rebuild takes over 10 s". S3-L reported an old-compiler rebuild of 12 s
while the full old gate was running. This was the compiler step itself, not
build-slot admission. Contention may explain it, but the rule has no contention
exception. No implementation, rebuild, gate rerun, package commit or merge is
authorized past this checkpoint without the user's direction.

## Stop evidence

Worktree: `/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-language`.
Command:

```sh
scripts/build-slot.sh build -- zig build test-cli \
  -Dtest-filter='dictionary projections' --summary all \
  > experiments/new-core-s3-20261006/wave-a/language/focused-fix.log 2>&1
```

Reported Build Summary line:

```text
compile exe mylang debug native success 12s MaxRSS:569M
```

The lane reused that log for subsequent fixture fixes before reporting the
overrun to the coordinator. Its final contents show the later 5/5 passing
focused run. The 12 s line survives in the lane's tool transcript; the lane is
preserving a labeled transcript excerpt, not claiming it is the original log.
Later compiler rebuilds reported 3–6 s. The coordinator canceled its queued
source commit and eight-shard core gate while they were waiting for admission.

The existing full old `test` process is allowed to finish solely to retain its
evidence. It has already reported migration failures, including an obsolete
`RC-INLINE-TAKE-1` assertion at `src/qbe_rc_inline_take_test.zig:55`: the new
snapshot list permits `@rcmoveheader`. That assertion has not been repaired
after this stop. No full old-gate pass is claimed.

## Branch and workspace state

Integration: `codex/new-core-s3-integration`, created directly from
`92590700cb0bf5e4dc19cc1f0c836c3a41693f64` on `codex/new-core-s2-integration`.
It remains at that commit, with this uncommitted stop report only.

The two locked package worktrees also remain at that base:

- `/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-ir`,
  branch `codex/new-core-s3-ir`: S3-0 source/design staged, evidence untracked.
- `/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-language`,
  branch `codex/new-core-s3-language`: S3-L implementation and migrations
  uncommitted, evidence untracked.

The original dirty mylang worktree was left untouched. No branch was pushed;
nothing was merged into `main`. Wave B has not started. This is not the planned
completed Wave A review point or the §7 S3 exit report.

## Completed S3-0 checks

Logs below are in the IR worktree's
`experiments/new-core-s3-20261006/wave-a/s3-0/`.

| Check | Result | Evidence |
|---|---|---|
| Latest core rebuild | 1.67 s, green | `rebuild.txt`, `rebuild-seconds.txt` |
| New hand-built IR tests | 14/14, green | `focused-test-core.txt` |
| Held four-shard test-core | 219 selected tests pass, 126.81 s, maximum shard RSS 206 MB | `test-core.txt`, `test-core-seconds.txt` |
| Full conformance | debug/release each 1224 matching, 0 mismatching, 316 unsupported of 1540 | `conformance.txt` |
| Full leak/verify conformance | same counts, zero mismatches, strict process-status/stdout checking | `conformance-verify.txt` |
| S0/S1/S2 definitions | all 35 rows' complete emitted function definitions identical to 92590700 | `code-identity.txt`, `identity-baseline.txt` |
| Strict S0 fuzz | 50 cases, 750 comparisons, no mismatch/fact/leak/crash/refusal | `fuzz-s0/summary.json` |
| Coverage | 3185/3627 functions accepted; complete refusal occurrences retained | `coverage.txt`, `coverage-checked/summary.json` |
| Guardian | all 88 checks green | `guardian.txt` |

One four-shard core step exceeded approximately 90 s. Per §5, eight shards were
queued for subsequent qualification; that queued run was canceled at this
stop, so there is no eight-shard result.

## Work prepared for review

S3-0 wrote `docs/design/new-core-s3.md` before its IR changes. The note covers
all nine required areas and records the foundation's as-built scope. It adds
counted `byte_buffer`, `capability` and `resource` leaves; five buffer operations;
integer shifts, saturating addition and float-unary selection; and `runtime_c`
linkage that passes runtime capability tokens while source extern retains its
scalar-only Host-erasing contract. Existing compound IDs/op ordinals remain
unchanged. New operation emitters fail closed; no Wave B source feature is
admitted. Ownership tests exercise buffer COW and verify uniqueness assertions.

S3-L prepared the shared `E_VIEW_STORED` rule, including unused generic bodies,
structured snapshot fixes, SPEC/docs migration and source-test snapshots or
rejections. Its latest focused checker tests pass 19/19 and focused fix/rejection
fixtures pass 5/5. The audit found no stored-view use in examples, benchmarks or
the inspected external Lox sources. Direct projected membership had an existing
concrete-checker `E_MEMBERSHIP` gap; the lane prepared a narrow existing-node loop
implementation for the plan's explicitly required immediate `in` use. Its full
old gate and final new-core conformance remain unqualified.

## Remaining before the Wave A review

The user must first direct handling of the 12 s rebuild stop. If resumed, isolate
and measure that rebuild with contention controlled, repair outstanding D2
migration assertions, finish the full old gate and D2 conformance, then commit
the qualified packages. Merge each into the integration branch with held
test-core and full debug/release conformance after each merge. Finish the Wave A
design/IR review report and stop for the user's Wave B go. S3's later §7 exit
report remains required after Waves B/C/X; S4 still requires its own go/stop.


## Final initial-gate and administrative results

The already-running S3-L `zig build test --summary all` completed at exit 1:
105/115 build steps succeeded, 9 steps failed, and the runner reported 8 failing
tests. Complete evidence is retained at
`../codex-new-core-s3-language/experiments/new-core-s3-20261006/wave-a/language/gate-test.log`
(relative to the integration worktree), with process status in
`gate-test-status.txt`. This initial gate predates later focused fixture repairs,
and is not a pass of the latest source state.

Outstanding unrepaired migrations at the hold are four snapshot-list optimizer
assertions in `src/qbe_rc_inline_take_test.zig:55,66` and
`src/qbe_rc_plain_record_write_test.zig:86,134`, plus the python-core snapshot
fixture expected total at `src/python_core_test.zig` (32 should be 33). Initial
CLI fixture and declaration-identity failures were repaired before the hold;
the latest focused CLI fixtures pass, and the identity helper requires rerun.
The initial language-corpus step also hit prelude fixture lookup errors repaired
before the hold. The module compilation oracle later reports 342/342 equal,
and the native boundary matrix 68/68 agreement; the full gate remains failed.

The required Guardian feedback-only commit completed after the old gate released
the gate slot: `c147da6` in `guardian-zig`,
`feedback: mylang — S3 Wave A rebuild-stop checkpoint`. It changed FEEDBACK.md
only (three lines), and the whole-tree Guardian gate reported zero blocking
findings. Its log is retained as `guardian-feedback-commit.log` in the language
evidence directory. No post-stop S3 source fixes, builds, commits or merges occurred.
