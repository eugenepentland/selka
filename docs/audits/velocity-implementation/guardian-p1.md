# Guardian feedback: package P1

Recorded 2026-09-15 while implementing P1 (selected test providers against
checked contracts) in the `velocity-p1` worktree. Guardian ran automatically on
every `zig build` / focused `test-*` invocation; the final diff-scoped run
passed all 88 checks. The shared `~/ai/canopy/guardian-zig/FEEDBACK.md` was not
edited.

## Good findings

- `dead-pub` correctly flagged the new `interfaces.Index.renderContracts`
  before the `list-interfaces --contracts` command consumed it; wiring the
  command first made the finding disappear.
- `type-size` caught two structs that would have grown past the frozen cap:
  an 8-field `ContractDeclaration` (folded `effects`/`mutates`/`origin` into one
  canonical `permissions` string) and a 13-field `native_test_receipts.Result`
  (nested `Identity` and `Context`; a custom `jsonStringify` keeps the
  `native-tests-v1` wire shape flat).
- `function-size` caught `receipts.hit` at 8 runtime parameters; bundling the
  three receipt identities into `receipts.Identity` brought it to 6.
- `repeated-string-literal` caught `const function_kind = "function"` duplicated
  with `src/incremental.zig`; renaming the local const removed the collision.
- `allocator-hygiene` caught a test helper hardcoding `std.testing.allocator`;
  threading the allocator through also exposed two real leaks in
  `contractIdentity`/`providerIdentity`, both fixed before the gate passed.
- `error-path-test` demanded a test naming each new error member; the
  directional-permission and contract-comparison unit tests now name
  `InvalidContracts` and `IncompatibleProvider`.
- `cognitive-complexity` caught `listModulesWithCache` at 26 after the first
  inline `--contracts` branch; extracting `listInterfaces` returned it to the
  limit and is clearer.
- `change-classification` correctly refused the behavioral lines until the
  acceptance-matrix regressions arrived in the same change.

## Friction

- A new spec behavior cannot get a primary `// spec:` tag without editing
  `SPEC.md`, which this worktree may not touch. The P1 regressions therefore use
  `// spec-case: NATIVE-TEST-3`, so the `spec` gate stays green but the new
  behavior has no primary bullet. The integrator must add the bullet and a
  primary tag (see the concrete request).
- `zig build` gates the install step on the diff-scoped Guardian run, so a
  helper could not be probed from `zig-out/bin/mylang` until every Guardian
  finding was cleared. The built artifact in `.zig-cache/o/*/mylang` was used
  meanwhile; that is workable but not obvious from the failure message.
- As in M2/M3, `zig build test-units`/`test-cli` print
  `failed command: <runner>` after a passing `PASS — N passed` summary, so a
  polled log reads as a failure until the enclosing build status is checked.

## Concrete request

- Add one primary SPEC behavior (either a new `NATIVE-TEST-5` or an extension
  of `NATIVE-TEST-3`) covering P1: a selected provider is validated against the
  production module's full declared public contract before any production body
  is checked; replacement may narrow effects/mutation/return-origin but not
  strengthen them; a production interface error rejects while an unselected
  body error or typed hole does not block the selected fake. Then add a
  `// spec: NATIVE-TEST-5` (or the chosen id) tag above the first P1
  integration regression and leave the `// spec-case: NATIVE-TEST-3` tags as
  the secondary references. This is the only registration patch P1 needs.
