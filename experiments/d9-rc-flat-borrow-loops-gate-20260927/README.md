# Joined flat-loan and borrowed-loop correctness gate

Frozen source `636524b81562e30285b15e297078fac24ffccb58` passes the complete
four-command gate and both uncached counted-RC language sweeps. `identity.json`
records the Debug compiler hash, exact build summaries, sweep counts and archive
hashes. Compressed files preserve the full raw receipts.

`gate.sh` and `sweep.sh` are the actual executed scripts. They check exact HEAD
and a clean tracked tree before and after execution. The gate held
`../.d9-closeout-gate.lock`; builds use the shared slot wrapper, a private Zig
cache and on-disk temporary files. LLVM sweeps use the actual `--release` backend.

This archive establishes correctness for this checkpoint. Complete performance
acceptance, the ordinary RC default transition and final validation remain open.
The running full-corpus diagnostic uses the older immutable `e926d1e1` compiler;
its evidence must not be attributed to this newer source.
