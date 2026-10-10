# Independent frontend pilot qualification gates

`zig build test` includes `test-selfhost-pilots`. The focused targets are
`test-selfhost-lexer-pilot`, `test-selfhost-parser-pilot` and
`test-selfhost-probes-pilot`. They use the existing qualified component seed;
none accepts an arbitrary compiler executable as a bootstrap seed.

Run through admission with private disk scratch and a private local Zig cache:

```console
mkdir -p "$PWD/.tmp/pilot-gates"
export TMPDIR="$PWD/.tmp/pilot-gates"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"
export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
scripts/build-slot.sh build zig build test-selfhost-pilots --summary all
scripts/build-slot.sh build zig build fmt-check
```

The focused aggregate also runs six adversarial admission/input-tracking tests.
Every lane verifies the seed receipt through the component coordinator, then
executes all declared pure tests in normal and release modes. Lexer/parser pure
roots are discovered from every sibling module declaring public test functions,
so new type/value test modules enter the gate automatically. Release enables
`--verify-facts`; leak checking is enabled for both modes. Tests use `--force`
and `--no-cache`. The orchestration rejects empty selections, unexpected counts,
cached verdicts, failures, skips and missing summaries. Lexer qualification adds
both corpus comparisons and component-only edit/rebuild checks in both modes.
Parser qualification adds the structural oracle and malformed transport checks
in both modes. Its projection remains narrower than full production AST parity;
gate registration does not expand the supported grammar or route compilation
through the parser pilot.

The lexer oracle explicitly uses `MYLANG_LEXER_MODE=reference`. User-provided
`MYLANG_*` settings are removed from qualification children except the chosen
component cache store, whose seed receipts are still verified, and the pinned
Zig path. This keeps component routing and guest budgets from changing the
qualification selection. The build uses the existing live-environment
`withTools` wrapper; it does not copy environment variables at configure time.

Each lane records its complete source, driver, fixture and seed/coordinator
closure through `build_test_inputs.zig`. The parser additionally records the
entire `src/` tree because its standalone oracle copies that tree. Source
manifests discover edits, additions, removals and renames at execution time.
Artifacts and the pinned Zig executable are build dependencies. The new lane
steps intentionally execute on every invocation: repository source manifests
cannot observe a modified seed executable/receipt in an external cache store,
so a warm build must still call the receipt-verifying coordinator. The tiny
registration self-tests can cache against their complete declared input closure.

## Cache Wave 3 merge handoff

Registration is based on the committed pilot integration revision, without
copying the dirty cache Wave 3 worktree. That worktree currently adds a
verification registry through `build_verification.zig`, registers `cached()`
steps by input-list name, and wraps eligible actions in persisted receipts.
These changes overlap the shared build files but do not replace this gate.

When merging Wave 3, preserve the three `pilot_*` input lists and
`pilot_registration`, the aggregate/full-test dependencies and the per-lane
commands. Register lane actions as **non-cacheable** in the verification
registry with reason "external qualified seed receipt must be verified before
reuse". Merely setting `has_side_effects` in the Zig build is insufficient if a
separate action-receipt wrapper later reuses their verdicts. Alternatively, add
an always-run verified seed preparation action whose authenticated executable
and receipt identities become action inputs; that requires separate tests for
corrupt executable, corrupt/missing receipt and changed toolchain artifacts.
Do not claim that the ordinary component manifests alone cover the pilot seed
store's executable integrity. Keep the registration self-tests eligible for
normal input-based caching.
