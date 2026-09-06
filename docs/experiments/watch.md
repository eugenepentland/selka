# Automatic project checking

Run `python3 scripts/watch.py path/to/main.my --compiler zig-out/bin/mylang` to
check immediately and recheck after source changes. The driver keeps one
`check-session` compiler process, preserving its bounded syntax cache while every
request reloads inputs. Exact successful snapshots may reuse a checked verdict;
changed snapshots rerun semantic checking. It never executes the guest.
Repeated `--inputs=manifest.json` options watch the same declared manifests used
by ordinary checks, including paths outside the source directory.

Stdout contains the compiler's `check-session-v1` JSON replies; diagnostics go to
stderr. Rejected source and input errors do not stop watching. `--once` checks once
and exits with the reported status (0, 1, or 2). Otherwise SIGINT/SIGTERM stop the
watcher with 130/143 and reap its compiler child. Unexpected compiler exit,
malformed replies, or per-check timeout terminate with status 2. The default
reply timeout is 60 seconds, configurable with `--timeout`.

## Change detection and limits

The driver polls content every 0.25 seconds (`--interval`), hashing source bytes
rather than relying on modification times or sizes. Atomic replacement, deletion,
recreation, nested module addition, and same-size edits with restored timestamps
are detected. A timestamp-only touch causes no request. Changes during an active
check remain visible to the next poll because the driver retains the pre-check
snapshot. Edits completed and reverted entirely between polls may be unobserved;
this is polling, not a filesystem event history or an atomic project snapshot.

Traversal starts at the entry's lexical parent directory, matching compiler import
resolution. It includes `.my` files and subdirectories with valid module identifier
names, following directory symlinks with ancestor-cycle rejection. It watches all
such source files, so edits to an unrelated module can trigger a conservative
recheck. This also detects newly added imports and recovery from missing modules
without requiring a successful dependency graph first. Source symlink contents
are hashed; choosing a symlink entry preserves its lexical import root.

Each poll permits 10,000 directory entries, 256 directory levels, and 64 MiB of
source/manifest bytes.
Exceeding a bound or encountering a directory symlink cycle fails explicitly;
it does not silently watch an incomplete tree. Read errors are retained as change
identities so repair can trigger another check. Nonregular files are recognized
without blocking the hashing pass. The compiler's own read/check behavior remains
subject to the reply timeout. At most 16 manifests match the compiler CLI limit;
reply framing is capped at 64 KiB. These are driver limits, not a whole-process
memory guarantee or a claim about compiler semantic budgets.

## Acceptance

`tests/watch.py` runs the real compiler through cold/warm checks, content edits,
atomic replacement, rejected/deleted/recreated modules, new nested imports, and
external manifest errors. It verifies timestamp-only silence and content detection
with restored timestamps. Boundary checks cover traversal/hash limits and symlink
cycles; subprocess cases cover compiler EOF, malformed replies, edits during active checks, timeout, and child
reaping after timeout or interruption. The build
runs this driver alongside persistent-session acceptance.

This completes automatic polling for checking. Semantic query reuse, persistent
query storage, structured diagnostic frames, and incremental native compilation
remain separate unfinished work.

Validation: the full ReleaseFast build passed all 32 steps (unchanged core/CLI test
steps reused cached results). Final focused watch acceptance passed with Debug
and ReleaseFast compiler builds. Guardian passed all 88 checks with baselines
disabled. Native resource acceptance passed 116 outcomes, 106 VM trace comparisons,
392 allocation failures, and six registry sanitizer cases.
