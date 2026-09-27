# Physically empty local journals

`summary.json` records the source/compiler identities and medians. `full.json.gz`
contains every unchanged 5M benchmark command, stdout, perf record, binary hash
and counted before/after execution. `reduced.json.gz` is the paired 10K control.
`advance.ssa.gz` retains the four-entry emitted function; `after-il.json.gz`
retains its whole manifest.

`guests.json.gz` contains all 436 assertions plus four expected bounds traps.
`standalone.json.gz` records eight runs with balanced counters. The corresponding
executed scripts and logs are retained. Files named `driver-missing-fixture` and
`units-invalid-mut-fixture` are rejected validation setup attempts, superseded by
the complete passing runs. They are not positive evidence.

From the repository root, reproduce paired reduced measurements with immutable
Debug compiler paths:

```sh
python3 experiments/d9-rc-empty-locals-20260926/compare.py \
  /path/to/before/bin/mylang /path/to/after/bin/mylang \
  /path/to/new-output --steps 10000 --cpu 10
```

Use `--steps 5000000` for the unchanged benchmark. The archived full driver reused
the parent's frozen before binaries; the portable command rebuilds both sides
from the same original benchmark source. No acceptance threshold is relaxed.
