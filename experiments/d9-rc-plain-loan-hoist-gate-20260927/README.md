# Joined plain-value, loan and loop correctness gate

Frozen source `a9eae92edb41f845a1caa9e8562cddd364117897` passes the four-command
gate and both uncached counted-RC sweeps. `identity.json` records exact compiler
identity, command summaries and sweep counts. Compressed files preserve complete
raw receipts, including the earlier historical-manifest compatibility check.

`gate.sh` and `sweep.sh` record the exact commands. They check both HEAD and a
clean tracked tree before and after execution. The full gate was run under
`flock ../.d9-closeout-gate.lock`; all builds use build slots, a worktree-specific
cache and on-disk temporary storage. The frozen compiler and guest binaries stay
in private scratch. LLVM sweeps use the real `--release` backend.

This is correctness evidence. Full performance acceptance, the ordinary RC
default transition and final validation remain open. The separate e926 compiler
continues the complete historical corpus measurement; it is not this source.
