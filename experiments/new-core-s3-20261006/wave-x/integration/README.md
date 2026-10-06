# S3-X strict fuzz matrix

Run this once after all S3 packages are integrated and the final source and
both compiler executables have passed their prerequisite qualification. This
tool does not establish those prerequisites or rebuild either compiler.

From the final integration worktree, pass explicit qualified oracle paths and
the full final source commit:

```bash
scripts/build-slot.sh gate -- python3 \
  experiments/new-core-s3-20261006/wave-x/integration/fuzz_matrix.py \
  --old /absolute/path/to/qualified-old/mylang \
  --new /absolute/path/to/qualified-new/mylang-core \
  --qualified-head FULL_FINAL_INTEGRATED_COMMIT
```

The matrix holds the gate slot through this command. Each heavy worker also
uses `scripts/build-slot.sh build`; `--jobs` allows one to three workers (default
three), matching the three build slots. It runs all nine kinds with 200 fresh cases each, without evidence reuse:
`s0`, `s1`, `rc`, `rebinding`, `iteration`, `dict`, `text`, `number`, `functions`.
The longer number worker starts first; registry order and per-kind seeds remain
fixed. The manifest records the execution order separately.
Text explicitly uses the S3-A character extension of the complete S3-T1 harness,
including literal comparisons, multiple append branches, UTF-8 widths, NUL,
capacity growth and output snapshots. Number uses the updated original
`wave-b/s2-t2/fuzz_number.py`, which now includes S3 float parsing, formatting and
byte-buffer checks. Other generators and their argument sets remain unchanged.

The default evidence directory is a fresh UTC/UUID directory beside the driver.
`--evidence experiments/.../NEW_DIRECTORY` may select another fresh location;
even an existing empty directory is rejected. Every run has private frontend,
temporary and Zig local caches. No previous log or matrix evidence is overwritten.
The manifest records source identity, explicit oracle paths and SHA-256 hashes;
source changes or replaced oracle binaries invalidate the final result.

Qualification requires old release and new debug/release/verify builds for all
200 cases, the original harness comparison count, and independent raw stdout,
exit-status and trap-code comparisons for every native argument set. It rejects
refusals, build failures, crashes, timeouts, leaks, fact failures and unexpected
native exits. There are 25,800 required native comparisons across the matrix.
Existing harness-specific stderr comparisons remain authoritative too.

Final performance and count qualification uses an explicitly fresh all40
measurement directory. The count driver requires all 40 registry rows, an
explicit `--bin`, fresh optimized LLVM/assembly and a fresh JSON receipt; it
rejects partial `--rows` selections and `--reuse`. Its counts are static sites
in the shared runtime-size binary, with the same static scope at 4096 and 64.
Use `timing.totals.timed_innermost`, the exclusive parent and timed nonloop
metrics for the final table. Setup loops and opaque callee/runtime/untagged
header effects retain their separate or unknown scopes.

Timing and profiles hold both observed CPU10 locks, in this order, throughout
the command. The additional EDA lock coordinates an independent workspace;
the required S2 lock remains held too:

```bash
scripts/build-slot.sh build -- flock -x \
  /home/epentland/.cache/mylang/s4-wave0-20261006/cpu10.lock \
  flock -x /run/user/1000/mylang-s2-cpu10.lock \
  python3 experiments/new-core-s3-20261006/wave-c/s3-a/measure_all40.py \
  --build --rounds 7 --bin .mylang-cache/wave-x/all40-NEW-RUN \
  --mylang /absolute/path/to/qualified-old/mylang \
  --core /absolute/path/to/qualified-new/mylang-core \
  --json experiments/new-core-s3-20261006/wave-x/all40-NEW-RUN.json

scripts/build-slot.sh build -- python3 \
  experiments/new-core-s3-20261006/wave-x/integration/audit_all40.py \
  --bin .mylang-cache/wave-x/all40-NEW-RUN \
  --json experiments/new-core-s3-20261006/wave-x/count-audit-NEW-RUN.json
```

Each kind retains every generated source, `summary.json`, `harness.txt`, and an
append-only `commands.jsonl` containing unique command numbers, statuses and raw
stdout/stderr in base64. Matrix-level logs are separate `<kind>.txt` files;
`matrix.json` qualifies only if every kind passes. Failed sources and reasons
are additionally recorded in the kind summary and `failures/` directory.

Only Python syntax and `--help` checks were used while preparing these tools.
Preparation is not evidence that the S3-X matrix passed.

The integration merge qualifier also inspects the complete core-test build
summary and every reported test-run RSS through the inherited old-gate parser.
A green command status cannot hide a declared memory overrun or missing shard
verdict. The retained C/M receipts pass that retrospective inspection; final
source still requires its own fresh merge checks.

S3-A's private split-key fusion also has a supplementary 200-source text sweep.
Its generator exercises borrowed key lifetimes, managed dictionary returns,
rebound source text, break/continue, collisions, indexed/deleted dictionaries and
materialized escape fallbacks. The existing strict S3 monitor and text transport
run the same explicit old/debug/release/verify comparisons; this adds 3,000
comparisons without replacing any of the nine matrix kinds:

```bash
scripts/build-slot.sh gate -- bash -c '"$@"; result=$?; exit "$result"' -- \
  scripts/build-slot.sh build -- python3 \
  experiments/new-core-s3-20261006/wave-x/integration/fuzz_qualification.py \
  --kind text --cases 200 --seed 3340 \
  --harness experiments/new-core-s3-20261006/wave-x/integration/fuzz_split_harness.py \
  --old /absolute/path/to/qualified-old/mylang \
  --new /absolute/path/to/qualified-new/mylang-core \
  --evidence experiments/new-core-s3-20261006/wave-x/integration/split-200-NEW-RUN \
  --cache-root .mylang-cache/wave-x/split-200-NEW-RUN
```

Run only after A is integrated and on the same frozen source/oracle pair as the
matrix. Both output paths must be fresh. The adapter only renames the generated
module to the text transport's filename; it does not change the generated work.
