# Borrowed-entry ownership traffic

These records compare a Debug compiler with canonical owned accessor returns
against the same source tree plus the certified borrowed-entry hook patch.
Both use the corrected plain-inline publication from `98f82437`, the proof
from `cba648fe`, and empty-sort fix `410d969f`. Only the after compiler emits
and calls the extra internal entry. The saved patch SHA is in `sources.json`.
Compiler and native binary hashes are recorded in each JSON file.

The runner obtains the exact three schematic workloads from
`experiments/d9-rc-acceptance-20260926/compare.py::programs()` and uses the
existing `pc.py` build, run and SVG validation functions. It uses RC stats on
both native backends; LLVM retains the required O3 and full-LTO options.
The accepted GC performance baseline and all input fixtures stay unchanged.

All twelve output checks pass (three cases, two backends, before and after).
Each run saves 38,060 owner acquires and 38,060 owner releases. Fixture and
changed-value acquires fall from 6,434,873 to 6,396,813 (0.5915%); changed-net
adds 154 acquires to both sides. All 56,314 heap allocations retire, and hold,
clone and uniqueness counters remain identical. No counter saturates.
These are ownership-traffic measurements, not wall-time performance acceptance.

Reproduce using two separately saved installations:

```sh
python3 experiments/d9-rc-borrowed-entry-20260926/run.py \
  --before-prefix .tmp/rc-borrow-valid-before/install \
  --after-prefix .tmp/rc-borrow-valid-after/install \
  --work .tmp/rc-borrow-reproduce --output .tmp/rc-borrow-reproduce/results
```

`--lox-root` locates the frozen Lox inputs needed by the acceptance workload
inventory; this runner selects only schematic cases and reads those inputs.
The default points at `../d9-rc-performance/.tmp-rc-performance/lox`.
