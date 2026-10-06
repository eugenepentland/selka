# S3-C property runner checkpoint — 2026-10-06

Runner-owned qualification is green. This checkpoint is **not a combined S3-C
integration or stage-exit claim**: the complete core suite and full conformance
found the dependency issues listed below, which their owning lanes are fixing.

## Implemented behavior

The independent Core generator, shrinker, type refusal graph and literal renderer
port the old primary algorithms. Actual trials preserve name-derived SHA256 seeds
(first eight bytes, little endian), source parameter order, the default 100 runs,
10× discard threshold, generation edges and budgets, refill/retry decisions,
2,000-attempt shrink limit, counterexamples and complete reasons. True and Ok(True)
pass; False, Ok(False) and Err fail. A test's own precondition and reachable record
invariants discard; a helper's precondition fails.

The frozen IR builds recursive copied-value adapters and trial dispatchers. The
two-u64-per-node transport is private to this runner; published formats and old
wire ABIs did not change. A bounded outer batch forks each trial so fatal Core
traps retain normal resource cleanup. Each selected test owns and retires its
private directory. Clock, entropy, filesystem, environment and buffered streams
reset per trial. No real network operation or `tests/lang` edit was introduced.
Native signals and arbitrary native exits preserve the completed batch prefix,
original termination, and old retry/shrink accounting. Linux parent-death cleanup
prevents a timed-out outer process from leaving its trial child running.

Trace-bearing single-block functions get a return block in the test module before
shared passes. This retains their source names through Core's leaf inliner; LLVM
may still optimize the calls after trace metadata is emitted. The shared inliner,
emitter and frozen IR were not changed for this runner correction.

The CLI accepts `--seed`, `--property-runs` and repeated `--link` test options.
The existing `native-tests-v1` report gains the old optional property evidence.
Cache-input manifests name every new fixture and trusted native helper exactly.

## Evidence

- Frozen corrected old compiler:
  `codex-new-core-s3-capabilities/.mylang-cache/s3/env-grants-oracle/mylang`, SHA256
  `d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`.
  Its paired QBE SHA256 is
  `b6139650a99b39131cd791fa1fdc84c09472dc303930bbadd3f8a5348487af4c`.
  S3-C qualified the authorized old ENV fix with gate04: exit 0, 138/138 steps.
- `final-comparison.json`: **24 exact matches, 0 mismatches, 0 unsupported**.
  This compares full reasons and every property field, rather than verdicts alone:
  all generated shapes, actual integer/list shrinking, discard exhaustion, helper
  contracts, ordinary/property Results, buffered output, stand-in reset, default
  name seeds, native signals and empty-stderr exit 17. Each invocation's command,
  status and binary hash are in `final-01-commands.json`/`final-02-commands.json`.
- Integer shrinking is 27→8, three prior passes, four shrinks, 25 attempts and
  seven batches. List shrinking ends at `[100]`, 62 shrinks, 512 attempts and
  65 batches. Impossible preconditions discard 121 inputs for 12 requested runs.
  Native signal and silent exit each use four batches, one shrink and one attempt.
- The failed state-capture test records original -1 and minimal 0. Both start at
  clock 946684800000000000, missing `trial.txt`, empty environment, and entropy
  words 13309476754707697221 / 11984929618412882174 despite preceding mutations.
- `logs/conformance-focused-run01.txt`: **44/44 matching, 0 mismatching,
  0 unsupported**, separately in debug and release with facts/leak verification.
  Files: `properties`, `test_capabilities`, `recursive_values`, `error_traces`.
- All three actual runner regression tests passed in full `test-core` run02:
  generated shapes/reset in both modes, actual failures/discards/shrinking, and
  signal/silent-exit retry counts. Codec, generation and shrink unit tests also ran.
- `logs/core-run13.time`: **1.78 s**, 339,840 KB, with the retained gate lock and
  all three build slots held. Source dependency was frozen C/M `d1b9b094e`.
  `core-run12` was 2.22 s. The contended diagnostic build is explicitly excluded
  from rebuild timing evidence; waiting/canceled commands never started compilers.
- Guardian whole-tree gates and normal dependency commit hooks pass **88/88**.
  The coordinator owns the serialized feedback append; use
  `guardian-resume-feedback.md` for the resumed work.

Native helper qualification first used default-Debug PIC objects with an old
ReleaseFast library. The two objects required an unavailable UBSan symbol and
therefore did not execute their intended faults. Those invalid runs are preserved
in final01. Recompiling only the trusted helpers with `-O2 -fno-sanitize=all -fPIC`
and rerunning those cases produced exact matches in final02. Compiler behavior
was unchanged; the helper source and all command logs remain available.

## Trial-boundary cost

`trial-cost-run01.json` measures an already compiled scalar property on CPU 10,
three repeats, asserting every measured answer is True with clean output/leaks.
It includes process start, fork, capture files, decode/encode and cleanup, and
excludes compiler build time. Median: 12 trials 2.73 ms; default 100 trials
11.81 ms; 1,000 trials 104.40 ms (about 104 µs/trial).

The report's `processes` field counts **outer batch launches**, matching the old
contract. Core also forks one trial child per actual submitted input, including
discarded and shrink candidates. That implementation cost is recorded separately;
the old report count does not pretend to count these additional children.

## Combined gates still outstanding at this checkpoint

- Full core suite run02: 126.30 s total, below five minutes. Two dependency tests
  failed: the M authority fixture selected an extern instead of its main; C's
  scope-close assertion expected the obsolete textual `call void` spelling.
  Root/C own their test corrections. The longest 16-shard run was 107.34 s;
  replacement qualification will use **32 shards** to meet the 90 s shard rule.
- Full strict conformance run01: **1,517 matching / 1 mismatch / 0 unsupported**
  in each mode over 1,518 tests. The sole mismatch is M's
  `rc_scalar_replacements::test_plain_and_owning_fields_alternate_without_losing_pending_tokens`:
  `InvalidIr`, b12 %114, `record_set` signature. All generated-parameter tests
  execute; no parameter refusal is counted as qualification. Root owns this
  newly exposed place defect. Preserve run01 and rerun after the source fix.
- Final combined C integration must rerun the full old gate after adding these
  runner SPEC/manifests/fixtures. The earlier corrected ENV gate does not cover
  later runner source. Fuzz kinds are unchanged; I/O remains fixture evidence.

No package or stage exit is claimed until those combined gates are clean. No push,
main merge, or S4 implementation occurred.
