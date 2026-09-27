# Ownership-free numeric loop evidence

`identity.json` identifies source `280ef314`, the immutable Debug compiler and
the archived files. `source.patch.gz` preserves the exact implementation;
`measurement.json.gz` contains eight builds, 18 unscaled instruction samples and
four counted runs. `controls.json.gz` preserves 32 paired guest/trap outcomes.
All pairs preserve output, diagnostic trace and exact counters.

Run `python3 experiments/d9-rc-scalar-loops-20260927/verify.py` from any checkout
containing this archive to independently check its hashes, sample medians,
100% counter availability, expected outputs, traps and ownership balance.

`measure.py` and `controls.py` preserve the actual executed scripts. Their private
paths refer to the original worktrees and immutable compiler installations;
re-execution requires recreating those paths or explicitly recording substitutions
in a new experiment. The checked-in guest and two trap fixtures are included.
The accepted GC build manifest is preserved byte-for-byte under gzip. No workload
sizes or acceptance thresholds changed.

This establishes a single-workload improvement and focused correctness. The full
joined gate and complete 43-program-per-backend performance/RSS acceptance remain
separate requirements.
