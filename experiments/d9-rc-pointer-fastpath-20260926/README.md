# RC pointer and local-frame diagnostic

This is a scaled diagnostic, not WP-4 acceptance. The source is exactly
`bench/parity/suite/binary_trees.my` with `max_depth = 16` changed to `12`.
The complete corpus and its original depth-16 measurements remain unchanged.

`results.json` records compiler/binary/source hashes, raw perf counters, identical
before/after RC traffic, and three interleaved instruction measurements per arm.
All compilers were Debug; all guests used QBE, default optimization, no LTO,
and `--keep-symbols`. No `--backend llvm` arm is claimed here. CPU 0 was used
for this private diagnostic, on a shared machine; wall time/cycles are not used
as acceptance evidence. Profiles are sampled self cost, with fewer than 2,000
samples each, so their percentages guide prioritization rather than exact
attribution. Kernel symbol warnings do not affect named user-space symbols.

The baseline compiler is frozen `39f75f3f`. The pointer-only arm applies
`pointer.patch` to the recorded candidate parent; the complete change adds the
small automatic traversal frames. The generated guest function symbols and
sizes are identical in all RC arms. Counts are from separate instrumented
artifacts and do not affect instruction measurements.

Reproduce in an isolated worktree, with its own TMPDIR and Zig cache. Build a
Debug compiler for the desired source revision through `scripts/build-slot.sh`.
Then build this source through the same wrapper:

```sh
scripts/build-slot.sh build PATH_TO_DEBUG_COMPILER build binary_trees_n12.my \
  -o GUEST --cache-dir PRIVATE_CACHE --rc-runtime --keep-symbols
taskset -c AVAILABLE_CPU perf stat -x, -e instructions:u,cycles:u -- ./GUEST
```

Repeat alternating unchanged baseline/candidate guests three times, checking
stdout against `expected.stdout`. To check ownership traffic, build separately
with `--rc-runtime=stats` and verify the stderr JSON matches `results.json`.
A default-GC depth-12 control at the same compiler used 105,808,932 median user
instructions and produced identical stdout; the improved RC remains about
78 times that control. The complete 43-program decision remains outstanding.
