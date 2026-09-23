# Schematic lane 1 evidence — 2026-09-22

Harness for [`docs/audits/schematic-lane-runner-2026-09-22.md`](../../docs/audits/schematic-lane-runner-2026-09-22.md):
the build-policy change in `schematic-svg`. Nothing here changes production
source; the arms are built with an installed compiler from the lane's own
worktree.

| path | contents |
|---|---|
| `build_policy_arms.py` | builds `src/schematic/guest` once per candidate build policy with the exact argument vector `src/host_native.zig` composes, and records cold and warm build seconds |
| `bench_arms.py` | interleaved fresh-process timing of built guests (`kind: "guest"`), of the whole `schematic-svg` runner (`kind: "runner"`), and of the native ports (`kind: "native"`), with every run's SVG hashed against the reference arm |

## Reproduce

Two installs are needed: one from the base commit and one from the lane's, both
`-Doptimize=ReleaseFast`, because a Debug compiler's own speed hides the
per-invocation build cost this lane measures. Guest binaries are identical
either way — the compiler's optimize mode does not change the code it emits.

```sh
W=$PWD                     # the lane worktree
zig build -Doptimize=ReleaseFast --prefix "$W/.tmp/install-after"
S=experiments/schematic-lane-runner-20260922

# one guest per candidate policy, plus cold/warm build seconds
cat > .tmp/policies.json <<'JSON'
{"p-release": {"build": ["--backend", "llvm", "--llvm-opt", "3", "--max-frames=1024"]},
 "p-release-lto": {"build": ["--backend", "llvm", "--llvm-opt", "3", "--lto", "--max-frames=1024"]}}
JSON
python3 $S/build_policy_arms.py --compiler .tmp/install-after/bin/mylang --tree . \
  --work .tmp/audit/arms --arms .tmp/policies.json --warm 2

# guest binaries, interleaved, SVG-hash checked on every run
BENCH_WORK=$W/.tmp/audit/bench python3 $S/bench_arms.py \
  --arms .tmp/audit/arms-final-guest.json --out .tmp/audit/results-guest.json --rounds 31 --cpu 2

# the whole tool, end to end, warm object cache
XDG_CACHE_HOME=$W/.tmp/audit/xdg-bench BENCH_WORK=$W/.tmp/audit/bench python3 $S/bench_arms.py \
  --arms .tmp/audit/arms-final-runner.json --out .tmp/audit/results-runner.json --rounds 21 --cpu 2
```

`AUDIT_BENCH` names the frozen comparator tree
(`.tmp/full-svg-benchmark-20260921`, whose `projects/fixture` documents are
byte-identical to `experiments/schematic/fixtures`); the fixture's SVG is
`68157ea785ee3766c039714d1d081ea1c7a55def6cf9124660495f8b797ed388`. A `runner`
arm needs its own `XDG_CACHE_HOME`, which is where a host application puts its
object cache. Do not time while another build is running: the numbers in the
audit were taken with other lanes compiling on the same machine and are
inflated about twofold against a quiet one.
