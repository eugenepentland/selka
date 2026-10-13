# Publication qualification, 13 October 2026

The completed Lox/EDA performance branch `8c0aa4bbdcab614b59ac5cd9ad833cc0255e9038`
was merged with local `main` at `fcd00eb60d7a572d2299b20e0e6ed1db68f8185d`.
Local main tracks `origin/development`; the unrelated GitHub main snapshot is not
this publication target. The merge was automatic, with no conflict resolutions.
Both merge directions produced tree `a73e659066d4d9611c3af2a7704dc2c8168a8f68`;
using the performance branch as first parent kept Guardian's diff below its
64 MiB capture limit while preserving the identical merged tree and both histories.
No hooks or checks were bypassed.

The final tested source is `505d2ca3411c6d757fbe0ad829ebf9983abf954e`.
The complete verification coordinator ran directly with `--integration`, the
pinned Zig, shared admission, and the unchanged qualified component source/pin.
Gate 005 passed all **149/149 steps**, **3,194 tests**, and all **46 selected
registered actions**, with zero failures and stable inputs. The 27,739 skips in
Zig's summary are shard partitioning. The integration phase separately forced
1,596 language, 140 value-semantics and 98 ported tests with fact verification
and leak checking: zero cached, zero failures, and one existing unsupported
language case. The shared-store mismatch check passed. Whole-tree Guardian
passed all 88 checks on each integration-fix commit.

## Integration fixes and retained failures

- Gate 001 found four uses of the compiler-path API replaced on main. The three
  affected test files now call `corePath()`.
- Gate 002 found a scalar-reader fixture passed relatively after changing the
  child working directory. Its path is now resolved before launching the child;
  the focused regression passed.
- Gate 003 found two component-protocol failures, including `DiskQuota`. A
  read-only quota query confirmed `/tmp` has a per-user hard limit and little
  remaining space despite free filesystem capacity. Eight protocol fixtures now
  name their private temporary directory explicitly. All 29 protocol tests
  passed directly, and the subsequent full gates passed those tests.
- Gate 004 found two CLI guest-test failures. They passed 20 subsequent focused
  repetitions. Failure diagnostics now preserve child stdout/stderr. Gate 005
  passed the entire CLI shard and complete integration request. The earlier
  CLI failures' cause remains undetermined; their logs are retained.

All post-merge source edits are test setup or failure diagnostics. Production
compiler/runtime behavior was not changed during publication qualification.
`results.json` and each `gate-NNN/` retain exact source identities, commands,
statuses and compressed raw logs. The final gate receipts are in `gate-005/`.
The component pin and archive were hash-checked before every gate; no bootstrap
seed was changed. This does not extend the earlier guest ownership evidence into
a claim that every installed component has retired legacy RC.

The existing performance report remains tied to the measured C4 compiler.
No results have been relabeled as measurements of this merged compiler.
Uncommitted documentation edits in the original main worktree were kept separate;
`main-dirty-files-before.json` records their bytes for the fast-forward check.
The inherited whitespace findings are preserved in `diff-check.log.gz`: raw
historical stderr and an environment fixture's intentional trailing PS1 space
were not rewritten.
