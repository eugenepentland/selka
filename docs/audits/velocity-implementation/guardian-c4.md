# Guardian feedback: C4 — test selection without repeated lowering

Task: reuse the shared query cache for native-test validity, separate the
checked schema/dependency graph from full QBE emission, and look up deterministic
result receipts before lowering/emitting/building.
Branch: `codex/velocity-c4`
Base: `ee392fbf`

## What Guardian exercised

Guardian ran automatically on `zig build` and on every `zig build test-*`
invocation. The final diff-scoped run passed all 88 checks with only the
existing report-only findings (`file-size`, `function-length`, `line-length`);
none of those findings named the changed code as a new hard failure. Full public
gates were rerun on the final sources:

- `zig build` — clean, guardian 88/88 diff-scoped checks
- `zig build test-units` — 1046 passed, 0 failed
- `zig build test-cli` — 112 passed, 0 failed (includes the six new C4 tests)
- `zig build test-native-tests` — 53 passed, 0 failed
- `zig build test-qbe` — 31 + 39 + 1 passed, 0 failed
- `zig build test-doc-coverage` — 119 documented features, 0 failures
- `zig build test-docs` — 440 blocks, 120 run, 24 checked, 0 failed
- `zig build fmt-check` — clean

The shared `~/ai/canopy/guardian-zig/FEEDBACK.md` was not edited.

## Good findings and friction

- `catch-discipline` correctly rejected a bare `catch {}` for an intentionally
  ignored graph-cache write. The final code names the ignored cause in a small
  `ignoreStoreFailure` helper, so the intent is explicit and the check passes.
- `function-size` rejected a seven-runtime-parameter `graph_store.key`. Bundling
  the inputs into a `KeyInputs` struct is clearer than the argument list and
  satisfies the cap.
- `type-size` ratchet blocked adding two flags to `native_test_options.Options`
  and one field to `native_test_session.Session`. Rather than accepting a
  baseline bump, the flags were grouped into `Options.Flags` and the two tool
  paths into `Session.tools`, keeping both structs under their frozen ceilings.
- `bool-ops-per-condition` blocked a four-operator receipt-reuse condition;
  splitting it into small named helpers (`durableReuseAllowed`) reads better.
- `line-length` forced two long lines (the fake-compiler manifest in the unit
  test and the native `build` argv) to be split at readable boundaries.
- The `MYLANG_TEST_TRACE` hook is intentionally in-process rather than a
  wrapper: `mylang test` re-invokes `/proc/self/exe`, so an external wrapper
  cannot see the child compiler commands. The hook only appends argv lines when
  the environment variable is set and never changes control flow or receipts.
