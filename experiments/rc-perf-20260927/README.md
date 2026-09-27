# RC performance: fast measurement loop (2026-09-27)

`quick.py` measures the unchanged D9 WP-4 43-program corpus (parity, schematic,
13 Lox VM scripts) on both backends in about 20 seconds at dev size, against
the accepted WP-4pre GC binaries. It is a development instrument; acceptance
still uses the frozen full-size protocol.

    python3 experiments/rc-perf-20260927/quick.py setup
    python3 experiments/rc-perf-20260927/quick.py build --compiler PATH/mylang --tag mine
    python3 experiments/rc-perf-20260927/quick.py measure --tag mine            # dev size
    python3 experiments/rc-perf-20260927/quick.py measure --tag mine --size full --only lox
    python3 experiments/rc-perf-20260927/quick.py compare A.json B.json

Why it is fast: one pinned run per program and side (instruction counts are
deterministic to about 0.5%), parallel runs, GC counts cached by binary hash,
and a dev size that reproduces full-size ratios. RC output is compared with GC
output at every size, which is also a differential correctness check.

`base-dev.json` is integration `fdf73b30`: QBE geomean 4.05 (non-Lox 2.26),
LLVM 5.32 (non-Lox 2.48); every Lox program is 12-42x. It also found a wrong
answer: Lox `method_call` on RC/QBE prints `true` instead of `false` at
N <= 10000 (correct at the benchmark's N=50000, so full-size runs miss it).

Profile of Lox binary_trees N8 on RC/QBE: 27.4G instructions against 1.35G GC,
for about 78M ownership operations (27M hold pairs, 17M owner ops, 0.8M
allocations, 3.9M unique checks), about 335 instructions per operation. Time
goes to metadata lookup (index_find/descriptor_find about 13%), the generic
shape walker (walk/visit about 16%), loan/unloan, drain, frame journals and
calloc/free. The gap is the cost per operation more than the operation count.
