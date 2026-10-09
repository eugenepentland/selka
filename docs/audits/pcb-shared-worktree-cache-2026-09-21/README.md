# PCB shared worktree cache

Implemented and deployed to `/home/epentland/ai/canopy/pcb-workbench` on
2026-09-21. Identical worktrees on this machine now share the installed compiler,
canonical source snapshots, native caches, test receipts and application binary.
The existing LLVM application was preserved byte-for-byte during migration.

## Design

- `workbench.json` contains a version, stable project identity and the complete
  compiler-install content hash. Keep this file in version control with the
  wrappers. Each checkout reads its own pin; there is no shared mutable current
  compiler. Updating one checkout leaves another checkout's pin unchanged.
- `tools/workbench-store.py` uses `$XDG_CACHE_HOME/mylang/workbench`, normally
  `~/.cache/mylang/workbench`. An absolute `PCB_SHARED_CACHE` overrides the store.
  Toolchains live under `toolchains/<pin>` and project state under
  `projects/<project>`. Native build and test caches are partitioned by compiler
  pin, keeping native generation cleanup from evicting another pin's cache.
- Snapshots capture the flat `guest/*.my` inputs, plus the test inventory for
  gates. Inputs are read twice to reject changes during capture. Existing
  snapshots are checked against their expected contents. Equal snapshots have
  the same absolute path across worktrees, which lets native test receipts reuse
  their entry identity. Extend this contract before adding other compile inputs.
- Toolchain installation rejects incomplete installs, symlinks and special files,
  validates copied content, then atomically publishes a complete generation.
  Runtime lookup trusts this managed immutable installation's identity marker;
  hashing hundreds of megabytes on every invocation would defeat the fast path.
- Identical builds lock before checking for an existing executable, compile to a
  temporary path and publish only after success. Equal test selections also lock
  before execution. CPU scheduling width no longer changes the executable key;
  source, compiler, Zig, mode, relevant environment and recipe still do.
- Build and test reports remain checkout-local in `.workbench/results`.
  Application journal paths retain their existing runtime semantics. LLVM O3/LTO
  remains the application default, with LLVM O0 available for debug builds.

Normal use needs no `CACHE` or `MYLANG` overrides. New worktrees with the same
configuration automatically find this machine's populated store. A different
machine needs the matching installation registered first. Changed sources still
need validation, and `--force` deliberately executes tests again. Whole compiler
pins and application generations have no automatic pruning; shared state must
not be edited or cleared while agents are using it.

## Measurements and verification

These are individual wall-time observations on the shared host, not statistical
benchmarks. Tests used actual Git worktrees, including directory names containing
spaces, and the real pinned compiler. All PCB source hashes were preserved.

| Operation | Time | Outcome |
|---|---:|---|
| First worktree application build request | 0.215 s | Reused migrated executable |
| Second worktree, different build job count | 0.204 s | Same executable path and bytes |
| First full suite at new shared path | 221.266 s | 400 passed, 400 executed |
| Second worktree full suite | 5.749 s | 400 cached, zero executed |
| Deployed checkout application build request | 0.213 s | Reused shared executable |
| Deployed checkout status with private journal | 0.226 s | Exit 0 |
| Deployed checkout full suite | 5.267 s | 400 cached, zero executed |

Migration copied the previous native caches and final binary without deleting
the checkout's old cache. Test receipts needed one validation run because the
canonical source and installed-tool paths changed. Subsequent worktrees reuse
the newly populated shared namespace. The old build-key form is accepted only
as a migration seed when all its build inputs match.

The real dependency fixture initially printed 3 and passed its test. A second
worktree reused the executable and positive test receipt. Editing the dependency
to return 4 changed the executable, printed 4 and reran the test, which correctly
failed. The first worktree still printed 3 and reused its passing receipt.
Reverting the second worktree recovered the original executable and receipt.
Concurrent equal cold test requests produced exactly one executed test and one
cached result.

`tests/workflow.sh` passes. The four `tests/shared_cache.py` regressions pass in
5.365 seconds. They cover concurrent cold builds, compiler-pin/cache isolation,
source edits and reversion, partially written failed builds and retry, local
reports/journals, incomplete and symlinked install rejection, and corrupt snapshot
rejection. These tests use isolated stores and controlled compiler fixtures;
the real compiler checks above establish end-to-end behavior separately.

No compiler source changed in this follow-up. The compiler's full acceptance from
the [preceding latency work](../pcb-workbench-tool-latency-2026-09-21/implementation.md)
applies to the unchanged pin. This task validates the new wrapper/storage behavior.

## Artifacts

The external PCB folder has no Git repository. Its deployed changes are saved in
[workbench.patch](workbench.patch), including executable file modes. This patch
applies after the preceding latency-work changes using
`git apply --unidiff-zero workbench.patch`. Zero context keeps the archived patch
free of whitespace-only context lines. The deployment manifest records
all eleven changed/new files and their SHA-256 hashes.

- [Deployment manifest](verification/deployment.json)
- [Real worktree timings](verification/real-worktrees.json)
- [Deployed checkout timings](verification/live-checks.json)
- [Dependency invalidation timings](verification/dependency-worktrees.json)
- [Concurrent cold test receipts](verification/concurrent-gates.json)
- [Shared-cache regression results](verification/shared-cache-tests.log)
- [Workflow regression results](verification/workflow.stdout)

Complete native reports are retained as deterministic `.native.json.gz` files in
`verification/`. One-off migration and real-compiler verification scripts are in
`reproduction/`; their absolute paths describe this run and require adjustment
for another machine or run directory. The migration script refuses to overwrite
an existing shared namespace. Routine regression tests live in the deployed PCB
folder and are included in the patch.
