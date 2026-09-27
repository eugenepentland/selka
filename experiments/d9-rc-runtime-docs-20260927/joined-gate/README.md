# Joined documentation gate

Frozen source `2ca89942c797df18af5856ec55a76c34cc372127` passes the complete
four-command gate and whole-tree Guardian. `identity.json` records terminal
success and exact receipts; `gate.sh` checks HEAD and tracked source at both ends.
The gate ran under `flock ../.d9-closeout-gate.lock` through the build-slot wrapper,
with a private Zig cache and disk temporary directory.

The 23,608 skipped main-test selections are shard exclusions; 2,315 tests execute.
Production compiler/runtime source is unchanged from `468bd8e5`, whose separate
uncached RC sweeps pass 931 assertions on each backend. Documentation examples
were additionally checked under both runtime selections as recorded in the parent
archive. Full performance acceptance and the default transition remain open.
