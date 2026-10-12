# A01 harnesses for integrated rollout

`qualify.py --ordinary` and `allocations.py --ordinary` omit the experimental
selector and record `ownership_selection: ordinary` in their result manifests.
`repeat.py` executes the exact binaries from a qualification manifest and preserves
its selection identity; it invokes no compiler or ownership flag. Its binary hash
checks prevent relabeling another compiler's artifact as the current candidate.

For C2/C3, source the shared development environment and run:

```sh
python3 -B experiments/memory-closeout-20261012/A01/qualify.py --compiler "$MM_COMPILER" --zig "$ZIG" --output "$MM_OUTPUT/matrix" --source-revision "$MM_SHA" --ordinary
python3 -B experiments/memory-closeout-20261012/A01/allocations.py --compiler "$MM_COMPILER" --zig "$ZIG" --output "$MM_OUTPUT/allocations" --source-revision "$MM_SHA" --ordinary
python3 -B experiments/memory-closeout-20261012/A01/repeat.py --input "$MM_OUTPUT/matrix" --output "$MM_OUTPUT/repeated" --repeat 100
```

Each harness owns shared build admission; do not wrap it again. Use a fresh output
directory and exact complete installed compiler. Default matrix cases are combined
managed/nested maps, Result lists and trapped-item diagnostics, across six pipelines
and 1/2/8 workers. Instrumented counters are not runtime timing or RSS evidence.

The registered A01 native scheduler stress tests build the runtime embedded in the
test compiler and invoke no experimental CLI selector. They must run from the
integrated source tree for final runtime qualification. Their temporary C
`MYL_ZERO_RC` define selects the current prototype runtime layout; the retirement
draft removes it once that layout is unconditional. This is distinct from claiming
that the installed guest compiler or package has already changed its default.

Support5 probes use its actual supported selection and remain intermediate checks.
Final C1, C2 and C3 evidence must retain their own exact source/compiler identities.
