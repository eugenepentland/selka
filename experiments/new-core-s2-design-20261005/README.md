# S2 design experiments (2026-10-05)

Inputs to `docs/design/new-core-s2.md`. Nothing here is built by `zig build`.

- `dict-layout/`: C microbenchmark of five dictionary layouts (old core's shape, with and
  without its probe hint; CPython's compact dict; SwissTable with inline values; the chosen
  hybrid of dense entries plus control-byte groups) over the benchmark rows' key and value
  distributions. `./run.sh [rounds]` builds with `zig cc -O3 -march=native`, runs on CPU 10
  and writes `results/layouts-YYYYMMDD.txt` (user cycles per operation from a perf counter).
  `results/layouts-20261005.txt` is the run the note quotes.
- `conformance_groups.py`: groups `tests/lang` files by their S2 blocking features from a
  `conformance.py --set all` result; `results/conformance-groups-a09d8274.txt` is the S1
  head's (the input file lives in the S0/S1 worktree's
  `experiments/new-core-s1-20261005/results/conformance-all-a09d8274.txt`).
