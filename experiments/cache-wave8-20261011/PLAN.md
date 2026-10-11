# Wave 8 native success transport qualification

This is an acceptance plan, not measured evidence. Baseline `eb3c86a33` already
contains main `1d202d41b`. No prior deferred performance measurements are resumed.

The permanent integration root is `src/core/test_runner_portable_test.zig`.
Each case creates two actual project roots with identical logical file names,
explicit in-root `mylang.json` configurations, distinct private `--cache-dir`
locations, and one explicit `--shared-cache-dir`.
Private receiving caches are deleted before transport assertions. A cached
verdict must say `shared-receipt-hit` and `portable-reachable-ir`; a local manifest
or whole-file replay cannot satisfy these checks.

The initial supported boundary is a legacy ordinary zero-argument Boolean test
whose reachable effects are only managed allocation or mutation. Exact compiler,
native tool/CPU/runtime/planner identity, mode, settings and relevant environment
remain part of acceptance. Source/configuration/policy/asset paths must be proven
inside the current project root before converting their locations to logical
paths. Source literals are never rewritten. Unknown metadata, external paths,
Host, environment authority, identity introspection and error traces fall back
to execution. Provider overlays and properties may also conservatively execute.
In-root embedded assets and cases/configuration may share only when fully bound.

The native matrix checks:

- Cold A then shared-only warm B; a dependency edit fails the affected test while
  an unrelated test still shares; reverting recovers the original success.
- Force, fact verification, leak checking and `--no-cache` execute; Debug and
  Release are separate; a keyed environment change misses and its revert shares.
- Identical case-file bytes share across roots; a changed cases expectation fails, and a stricter project configuration is
  checked before reuse. Reverting both allows the original shared success.
- Embedded asset changes fail instead of accepting the other root's success.
- Introspection and environment authority execute separately; unsupported Host
  inputs retain the existing refusal and create no portable success record.
- Absolute path literals remain exact, escaping source symlinks execute without
  portable publication, and embed symlink escapes retain their diagnostic.
- Invalid configured shared format fails before warm private-manifest replay.
- Directory fanout forwards the explicit shared path to every child.
- Corrupt shared records miss, refill only after execution, then replay.
- Two actual concurrent compiler commands publish into the same store using
  separate allocators/private caches; a subsequent shared-only receiver verifies
  the published records.

Store unit tests independently cover record bounds, checksum/key validation,
atomic publication and malformed/partial state. CLI unit tests independently
cover explicit-option precedence, environment opt-in and malformed arguments.
Focused tests run only after the combined compiler install succeeds, through
normal build admission with the pinned Zig and shared global/worktree local
caches. Parent owns full gates and the final report. No timing or cross-machine
reuse claim is implied by this matrix.
