# Guest-test scratch staging: TMPDIR, cleanup and reclaim (2026-09-23)

Branch `fix/guest-test-tmpdir`, cut from `base/tmpdir-fix` (`027cf1b3`, which
was `main` at the time).

## The bug

`mylang test` staged each session's scratch in a hard-coded `/tmp/.pending/<hex>`
and ignored both `TMPDIR` and `--cache-dir`. That scratch holds the
materialized source snapshot, the `native-test-compile` facts and stderr, the
selection files and the test-runner build. On this machine `/tmp` is a tmpfs
with `usrquota`. On 2026-09-22 other sessions filled it, and every native guest
test then failed with `host failure: DiskQuota`, `NativeToolFailed` or
`ProjectConfigurationFailed`. Those failures looked like regressions.
`/tmp/.pending` also held 68 session directories totalling 298 MB, dated
2026-09-20 to 2026-09-23, that had never been cleaned up.

## What `main` already had

`d87dd687` ("Stage guest-test scratch under TMPDIR when it is set") had already
landed. It added `Context.scratchRoot()`, which reads `TMPDIR` from the
command's environment map and falls back to `/tmp` only when the variable is
unset or empty. `Session.initFrontend` stages under that root. The commit
included a unit test and the `[NATIVE-SCRATCH-ROOT-1]` SPEC bullet. This branch
adds end-to-end proof of that behaviour, cleanup and reclaim of abandoned
staging, and fixes for the other `/tmp` sites.

## Design choice: TMPDIR, not the cache directory

Scratch lives under `$TMPDIR`, with `/tmp` as the fallback. It does not live
under `--cache-dir`, for these reasons:

- **Scratch is per-invocation and disposable.** The cache is a durable, shared,
  content-addressed store. It is often shared across worktrees and sessions, and
  its eviction (`Context.sweep`) deliberately skips `.pending`. Putting source
  snapshots there would tie scratch cleanup to cache policy and leave copies of
  source code in a store meant to outlive the run.
- **`--no-cache` still needs scratch.** A run that opens no durable store should
  not need a cache directory to stage in.
- **`TMPDIR` is the convention.** `zig cc`, the linker, Python's `tempfile` and
  the gate's own drivers all honor it. Setting that one variable moves all of a
  host's scratch off a small tmpfs.
- **No rename crosses filesystems.** Nothing is renamed from session scratch into
  the cache. Receipts and graphs publish through `Context.atomic(path)`, which
  stages next to the destination.

The directory fan-out's report workspace already lived under the cache, in
`<cache>/.pending/<hex>`. It stays there: it is small and belongs to that cache.

## How Guardian's rule let it through

The `ban-hardcoded-paths` check (guardian-zig
`src/checks/ban_hardcoded_paths.zig`) only flags string literals that **start
with** `"/tmp/"`, `/home/`, `/usr/` and a few other prefixes, and it skips test
bodies. The original call was `context.temporary("/tmp")`. The bare `"/tmp"` has
no trailing slash, so the check never matched it. The fallback needs no
allowance for the same reason. It is now a single named and documented
constant, `qbe_build_io.default_scratch_root`, and that is the compiler's only
non-test spelling of `/tmp`.

Suggested follow-up in guardian-zig (not done here): also flag an exact
`"/tmp"`. The fallback would then need an `[[allow]]` entry or a home under
`src/config*`.

## Cleanup on every exit path

**Controlled exits.** A pass, a failing test, a rejected project, a host error
and an error return were already covered. `native_test_command.run` runs
`defer context.remove(session.temporary)`. `Session.init` and `initFrontend`
use `errdefer`. `invoke` removes staging on both its rejected and its ok paths.
New CLI tests pin this for a passing run and for a rejected project.

**Uncontrolled exits.** A `SIGKILL`, a timeout, a crash or panic, or an
interrupted gate runs no `defer`. That is where the 68 stale directories came
from. Scratch is now *owned*:

- `Context.owned(parent)` creates `parent/.pending/<hex>` containing a `.owner`
  marker with mode 0600.
- The creating process holds an exclusive `flock` on that marker until
  `Context.remove`. `remove` releases the lock only after the tree is deleted.
- Before creating a directory, `owned` runs `Context.reclaim(parent)`. It deletes
  every sibling under the same `.pending/` whose marker it can lock exclusively.
  The kernel releases a process's locks however the process exits, so a marker
  that can be locked proves its owner is gone.
- No age limit or wall clock is involved. This reuses the existing generation
  `.lease` idea under a separate marker name.

**What reclaim never touches:**

- An entry with no marker: another tool's scratch, an ordinary build's staging,
  or a directory left by a compiler that predates this change.
- A marker held by another process.
- A marker held by this process. `flock` conflicts between separate open file
  descriptions even within one process.
- A marker this user cannot open. Mode 0600 keeps one user's sweep away from
  another user's scratch in a shared `/tmp`.
- Anything that is not a plain directory. Symlinks are skipped.

**Races.** A sweep can take a new directory's marker in the window between the
creator making it and locking it. The creator then either fails its `tryLock`,
or wins a lock on a marker that has already been unlinked. The creator compares
the inode from `fstat` with the one from `stat` to catch that second case. In
both cases it leaves the directory to the sweep and stages a new one, within the
same bounded retry budget as `temporary`. On a filesystem without advisory
locks, the creator gets an unmarked directory, which is the old behaviour.

**Users.** Owned scratch is used by the `mylang test` session
(`Session.initFrontend`, which also covers `invoke`) and by the directory
fan-out workspace.

**Manual probe.** A `mylang test` run was killed with `SIGKILL` 0.7 s after it
started, leaving `.pending/<hex>/{.owner,.pending}` behind. The next run
reclaimed that directory, and the scratch root ended empty.

**Known limit.** When the parent is killed, a compiler child it spawned (for
example `native-test-compile`) can outlive it briefly. The next run's reclaim
may delete the directory under that orphan, which then fails on its own. The
orphan never holds the marker, because the descriptor is close-on-exec.

**Legacy directories.** The 68 directories now in `/tmp/.pending` have no
marker, so no run will ever reclaim them. They are safe to delete by hand once
no pre-fix `mylang test` is running (`rm -rf /tmp/.pending/<hex>` for each
unmarked entry). This branch did not delete them.

## Every hard-coded `/tmp`

| Site | On a real code path? | Fate |
|---|---|---|
| `src/native_test_session.zig` session scratch (`context.temporary("/tmp")` before `d87dd687`) | yes | `scratchRoot()` on main, now also `context.owned(...)` |
| `src/qbe_build_io.zig` `scratchRoot` fallback | yes | kept as the POSIX `P_tmpdir` fallback, named `default_scratch_root` |
| `tests/native_scoped_test.c` `mkdtemp("/tmp/mylang-scoped-XXXXXX")` | yes, run by `test-native-memory` inside `zig build test` | **fixed**: uses `$TMPDIR`, falls back to `/tmp` when unset or empty |
| `scripts/profile_large_project.py` default workdir `/tmp/mylang-s1-work` | yes, when neither `--workdir` nor `MYLANG_S1_WORKDIR` is set | **fixed**: `tempfile.gettempdir()` |
| `scripts/benchmark_semantic_population.py` `--work-dir` default `/tmp/mylang-r4-population` | yes | **fixed**: `tempfile.gettempdir()` |
| `scripts/benchmark_semantic_publication.py` `--roots tmpfs:/tmp ext4:…` | benchmark input | kept: it deliberately compares tmpfs with ext4, and the flag overrides it |
| `scripts/unblock-local-reasoning-lanes.sh` `rm -rf /tmp/zc-* …` | one-off ops script from a past incident | kept: it names the exact files that incident left in `/tmp` |
| `scripts/store_server.py:69` | comment | no change needed |
| `src/native_test_directory.zig` `"/tmp/work"`, `src/qbe_build.zig` `"/tmp/hermetic"`, `src/qbe_build_cache.zig` `"/tmp/out.o"`, `src/project_test.zig` `"/tmp/a"`, `src/standard_library_test.zig` guest string, `src/qbe_build_io.zig` scratch-root test | test-only literals, never created on disk | no change needed |
| `tests/test_deepseek_tool_audit.py` | transcript fixture strings | no change needed |
| `tests/store_*.py` `ROOT/.zig-cache/tmp/…` | repo-relative, not `/tmp` | no change needed |
| `tests/lang/README.md` `--cache-dir /tmp/lang-cache` | prose example | no change needed |

`build.zig` contains no `/tmp`. The Python drivers under `tests/` that need
scratch already use `tempfile`, which honors `TMPDIR`.

## Tests

- **`[NATIVE-SCRATCH-OWNER-1]`**, unit test in `src/qbe_build_io.zig`. It checks
  four things:
  - An abandoned marked sibling is reclaimed.
  - A sibling locked through another open file description survives, and so
    does an unmarked sibling.
  - This process's own live scratch survives a second call to `owned`.
  - `remove` releases the marker.
- **`[NATIVE-SCRATCH-ROOT-2]`**, CLI tests in `test/integration.zig`. They read
  the compiler-child argv recorded through `MYLANG_TEST_TRACE`:
  - With `TMPDIR` set to a fresh directory, every child reads its snapshot from
    `$TMPDIR/.pending/`. The trace names no `/tmp/.pending/`, and the scratch
    directory is empty afterwards.
  - A project the checker rejects (exit 1) staged under `TMPDIR` and left
    nothing behind.
  - With `TMPDIR` unset, staging falls back to `/tmp/.pending/`.
- **`spec-case NATIVE-SCRATCH-OWNER-1`**, CLI test. A planted killed-run
  directory with an unlocked `.owner` is reclaimed by a real `mylang test`,
  while an unmarked `foreign` directory survives. I disabled `reclaim` to check
  that this test fails without it, then reverted the change.
- An empty `TMPDIR` stays covered at unit level by `NATIVE-SCRATCH-ROOT-1`.
