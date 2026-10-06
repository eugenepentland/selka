# S4 exit programs: state and old-core baselines, 2026-10-06

Copies were made under `.mylang-cache/s4/base/`; no external checkout was edited.

The old compiler is a ReleaseFast build of the S3 Wave B base `8918de74`
(`.mylang-cache/s4/old`). The new core is S3's integration build at `e50e508a`, copied
to `.mylang-cache/s4/core-s3-latest`.

## Lox port

- **Source:** `/home/epentland/ai/canopy/mylang/.tmp/lox-bench/tree/benchmarks/lox/ports/mylang`
  (`4e48a0922`), 26 `.my` files, about 5,100 lines.
- **`mylang check main.my`** fails with `E_VALUE_CLASS` at `heap.my:20` (`public class
  CallFrame`). The port declares 16 classes.
- **New-core coverage:** 24 of 26 files fail the front end with `E_VALUE_CLASS`. The
  14 functions in the 2 files that check all pass.
- **No baseline is possible** until the port is migrated (S4-L).

## EDA port (pilot)

- **Source:** `/home/epentland/ai/canopy/eda-bench/mylang/src` (`af8cf03`), 16 files,
  5,169 lines, 30 tests in 9 programs.
- **New-core coverage:** 117 of 120 functions accepted. The refusals are
  `stream_write`, text of a non-integer value, and `array`. One file (`main_test.my`)
  cannot be checked alone.
- **Old core,** pinned with `taskset -c 10`:

| Step | Time |
|---|---:|
| `mylang build main.my` cold | 0.41 s |
| unchanged rebuild | 0.00 s |
| `mylang test . --jobs 1` cold | 5.51 s |
| unchanged rerun | 0.07 s |
| rerun after a one-function edit (`support_strs.my:146`), 1 test reran | 0.29 s |

The edit used for the build was in a function `main` does not reach, so the rebuild
after it also cost 0.00 s. S4-P must use an edit on main's path.
