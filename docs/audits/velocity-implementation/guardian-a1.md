# Guardian feedback: package A1

Recorded 2026-09-15 while implementing A1 (required architectural policy in
ordinary project workflows). Guardian ran automatically on every
`zig build test-units` / `zig build test-cli` in the `velocity-a1` worktree; the
final diff-scoped run passed all 88 checks. The shared
`guardian-zig/FEEDBACK.md` was not edited.

## Good findings

- Diff-scoped mode was accurate and fast, and caught real problems before tests
  ran:
  - `cognitive-complexity`: adding the policy gate pushed `listModulesWithCache`
    from 25 to 26. Extracting `loadConfiguredPolicy`/`setPolicyIdentity`/
    `configuredPolicyReceipt` brought the function back under the cap; the
    policy logic is also easier to read in one place.
  - `type-size`: the 7-field cap rejected three flat structs. `frontend_cache`
    moved `policy_identity` into its existing `Runtime` bundle; `project_config`
    grouped the resolved policy into `PolicyFile`; `native_test_snapshot`
    grouped support files and identity into `Support`. All three now stay at or
    below seven fields and mirror the contract shape.
  - `catch-discipline`: an empty `catch {}` around best-effort forwarding of a
    child compiler's stderr was flagged. Replacing it with
    `catch |err| switch (err) { error.BrokenPipe => {}, else => {} }` kept the
    best-effort behavior while naming the handled class.
  - `dead-pub`: an unused `Config.policyPath` helper was removed rather than
    kept for a hypothetical caller.
  - `error-path-test`: the new `HostConfiguration`, `PolicyViolation`,
    `ProjectConfigurationFailed`, `ProjectPolicyRejected` and
    `project_config` error-set members were all reported until tests named
    them. The integration suite now names each error path by test name or by
    `expectError`.
  - `formatting`: `zig fmt` caught one non-conforming edit to
    `native_test_snapshot.zig`.
  - `change-classification`: correctly demanded regressions in the same change;
    the acceptance matrix (cold/warm deny, allow, policy-only flip,
    different-cwd, cycle independence, native preparation, locked packages,
    receipts) arrived with the source edits.
  - `debug-print-ban`: temporarily printing mirrored policy bytes to diagnose a
    lifetime bug was rejected by the gate; removing the debug print and
    re-reading the policy bytes into the snapshot context fixed the real bug.

## Friction

- Zig's `run test` step is cached independently of `-Dtest-filter`, so switching
  from `-Dtest-filter=policy` to a new filter reported `run test cached` and ran
  nothing new. Forcing a run required deleting `.zig-cache/o` or executing the
  cached `test` artifact with `--test-filter` directly. The summary line should
  include the filters in the cache key, or print the selected filter beside the
  cached result.
- `error-path-test` uses the enclosing function name as the subject for a new
  `catch` block. For a private `main.zig` function the only way to name it is an
  integration test whose *name* contains that identifier, which is not obvious
  from the finding text. A hint like "add a test whose name contains
  `loadConfiguredPolicy`" would help.
- The `type-size` cap of 7 fields is good discipline, but this package has three
  contract-shaped records (cache runtime, resolved policy, mirrored support
  files). The nested-struct workaround is documented in code, but the gate
  message could suggest nesting when a struct grows past the cap instead of
  only saying "reduce it".
- `spec` tags cannot be added by A1 because the package may not edit `SPEC.md`;
  the regressions are plain `test` blocks and the integrator still needs the
  `required-project-import-policy` SPEC bullet plus the `features.json` entry.
  This is reported in the completion report rather than worked around.
