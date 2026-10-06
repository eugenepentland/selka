# S3-0 qualification

Source commit: `dc1a583109be06c3e699a433be24cbcd6e5d3816`.
Branch: `codex/new-core-s3-ir`, from `92590700`.
The user approved the design and IR foundation before resumption; no IR shapes
changed after that review. `ir.zig` is frozen at this package's exit.

The design covers all nine S3 areas. The foundation adds three counted leaf
types, five buffer ops, three integer ops, float-unary selection and runtime-C
linkage. New-op LLVM dispatch is deliberately fail closed. Source constructs
remain refused until their Wave B owner implements and qualifies them. Existing
compound IDs and op ordinals are preserved; record-phi ownership is unchanged.
The tests cover every new op, malformed signatures/selectors, C capability-token
passing versus source-extern erasure, aggregate/niche layouts and verified COW.

S3-T2's future float-text runtime object must be cached by complete helper
content, Zig version and target/build options. It must report the cold build
cost separately. This obligation is in the design note; no float-text runtime
implementation is claimed in Wave A.

## Checks

Every check below exited 0. New core/native builds ran through the build slot;
test-core held the gate slot for the complete build/test command. Shard RSS was
inspected separately from the runner's green verdict. No performance timing was
performed here; exact definitions establish identity for the 35 existing rows.

| Check | Result | Log |
|---|---|---|
| Baseline `zig build core --summary all` | 3/3 steps, 3.32 s | `baseline-build.txt` |
| Source rebuild `zig build core --summary all` | 3/3 steps, 1.67 s | `rebuild.txt`, `rebuild-seconds.txt` |
| Resumed `zig build core --summary all` | 3/3 steps cached, 0.03 s; gate lock excludes gate execution | `resume-01-core-build.txt`, `resume-01-core-build-seconds.txt` |
| Focused S3 hand-built IR gate | 14/14 tests | `focused-test-core.txt` |
| Four-shard `zig build test-core --summary all` | 219 selected tests pass, 126.81 s, peak shard RSS 206 MB | `test-core.txt`, `test-core-seconds.txt` |
| Eight-shard `zig build test-core -Dcore-shards=8 --summary all` | 219 selected tests pass, 79.19 s, longest shard 76.35 s, peak shard RSS 201 MB | `resume-02-test-core-8.txt`, `resume-02-test-core-8-seconds.txt` |
| Full conformance | debug/release each 1224 matching, 0 mismatching, 316 unsupported of 1540 | `conformance.txt` |
| Full leak/fact-verify conformance | same counts; no status/stdout/leak/fact failures | `conformance-verify.txt` |
| Complete 35-row emitted-definition identity | 35 identical, 0 changed | `code-identity.txt`, `identity-baseline.txt` |
| Strict S0 fuzz | 50 accepted cases, 750 comparisons, 0 mismatch/fact/crash/leak/refusal | `fuzz-s0/summary.json`, `fuzz-s0.txt` |
| Coverage | 3185/3627 accepted; complete refusal occurrences saved | `coverage.txt`, `coverage-checked/summary.json` |
| Source commit's Guardian gate | 88/88 checks pass | `resume-03-source-commit.txt` |

The initial four-shard gate exceeded the roughly 90-second shard guideline.
The resumed eight-shard run resolves that obligation without raising the
five-minute suite budget or the 2.5 GiB per-shard RSS ceiling. The canceled
`test-core-8.txt` was a queued command at the historical hold, not a test result.
Likewise `source-commit.txt` records a canceled queued commit; the source commit
actually completed in `resume-03-source-commit.txt`.

## Reproduction

Run from the package/integration worktree. The oracle is the pre-D2 S2 compiler
with its adjacent QBE tool copied into `.mylang-cache/s3/oracle/`. The baseline
35-row LLVM files were captured with the `92590700` compiler in
`.mylang-cache/s3/baseline/`. These are local caches, not frozen hash manifests.

```sh
scripts/build-slot.sh gate -- bash -c '"$@"; result=$?; exit "$result"' -- \
  scripts/build-slot.sh build -- zig build test-core -Dcore-shards=8 --summary all
scripts/build-slot.sh build -- python3 \
  experiments/new-core-s2-20261005/wave-b/integration/conformance_checked.py \
  --set all --jobs 4 --why --mylang .mylang-cache/s3/oracle/mylang \
  --core zig-out/bin/mylang-core --cache-dir .mylang-cache/s3/conformance
scripts/build-slot.sh build -- python3 \
  experiments/new-core-s2-20261005/wave-b/integration/conformance_checked.py \
  --set all --jobs 4 --why --leakcheck --verify \
  --mylang .mylang-cache/s3/oracle/mylang --core zig-out/bin/mylang-core \
  --cache-dir .mylang-cache/s3/conformance-verify
scripts/build-slot.sh build -- python3 \
  experiments/new-core-s3-20261006/wave-a/compare_all35.py
scripts/build-slot.sh build -- python3 \
  experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py \
  --kind s0 --cases 50 --seed 202610060 \
  --mylang .mylang-cache/s3/oracle/mylang --core zig-out/bin/mylang-core \
  --evidence experiments/new-core-s3-20261006/wave-a/s3-0/fuzz-s0 \
  --cache-root .mylang-cache/s3/fuzz-s0
scripts/build-slot.sh build -- python3 \
  experiments/new-core-s2-20261005/wave-a/qualify_coverage.py \
  --evidence experiments/new-core-s3-20261006/wave-a/s3-0/coverage-checked
```

Use fresh evidence paths and a unique log for every repeated command. The
coordinator's new `check_merge.py` refuses an existing stage output directory,
checks source stability, process status, stdout verdicts and RSS, and records
command time separately from admission. It is used after each committed merge.
The complete source/SPEC/design diff from `92590700` passes the whitespace check
in `resume-07-committed-source-diff-check.txt`. The earlier scan over captured
logs (`resume-04-evidence-diff-check.txt`) flags the build runner's trailing blank
lines; those original outputs are preserved unchanged.

S3-L owns the full old-core gate because it changes the shared checker and old
test corpus. This package's shared language behavior is unchanged. The Wave A
review follows both package merges and their cheap gates; Wave B still needs
the user's go.
