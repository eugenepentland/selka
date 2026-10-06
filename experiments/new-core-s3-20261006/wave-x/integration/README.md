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
uses `scripts/build-slot.sh build`; `--jobs` allows one or two workers (default
two). It runs all nine kinds with 200 fresh cases each, without evidence reuse:
`s0`, `s1`, `rc`, `rebinding`, `iteration`, `dict`, `text`, `number`, `functions`.
Text explicitly uses the extended S3-T1 harness. Number uses the updated original
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

Each kind retains every generated source, `summary.json`, `harness.txt`, and an
append-only `commands.jsonl` containing unique command numbers, statuses and raw
stdout/stderr in base64. Matrix-level logs are separate `<kind>.txt` files;
`matrix.json` qualifies only if every kind passes. Failed sources and reasons
are additionally recorded in the kind summary and `failures/` directory.

Only Python syntax and `--help` checks were used while preparing these tools.
Preparation is not evidence that the S3-X matrix passed.
