# Joined bounded physical-retain gate

Frozen source `d1d8b3c46ac41e832410a03aad49a5a6a1a54b07` passes the complete
four-command gate and both uncached counted-RC language sweeps. `identity.json`
records the Debug compiler, exact terminal summaries and receipt hashes.
`gate.sh` and `sweep.sh` require that source commit and a clean tracked tree at
both ends. The gate ran under the shared flock; build-slot, a private Zig cache
and disk temporary storage were used throughout. LLVM uses the actual release
backend with O3 and full LTO.

The main run executes 2,315 tests; 23,608 reported skips are shard exclusions.
QBE passes 440 tests, and each RC sweep passes 931 assertions across 160 programs
with no failed, skipped, cached, dropped or unloaded outcomes. Whole-tree
Guardian passes all 88 checks. Full performance acceptance and the RC default
transition remain outstanding.
