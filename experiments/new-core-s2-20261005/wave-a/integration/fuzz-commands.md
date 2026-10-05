# Frozen Wave A fuzz qualification

Do not launch until the coordinator declares the final compiler tree ready.
Run in `/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s2-integration`.
Use at most two jobs concurrently; each command holds one normal build slot.
There is no gate lock. The wrapper creates a distinct disk TMPDIR, frontend
cache and local Zig cache for each job, uses the shared global Zig cache, and
requires CPU affinity to exclude 2, 3, 10 and 11. No compiler source is changed.

```bash
scripts/build-slot.sh build -- /usr/bin/time -f %e -o .mylang-cache/wave-a/final-fuzz/s0-seconds.txt python3 experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py --kind s0 --cases 200 --seed 31 --cache-root .mylang-cache/wave-a/final-fuzz/s0 --evidence experiments/new-core-s2-20261005/wave-a/integration/fuzz-s0 > experiments/new-core-s2-20261005/wave-a/integration/fuzz-s0.txt 2>&1

scripts/build-slot.sh build -- /usr/bin/time -f %e -o .mylang-cache/wave-a/final-fuzz/s1-seconds.txt python3 experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py --kind s1 --cases 200 --seed 42 --cache-root .mylang-cache/wave-a/final-fuzz/s1 --evidence experiments/new-core-s2-20261005/wave-a/integration/fuzz-s1 > experiments/new-core-s2-20261005/wave-a/integration/fuzz-s1.txt 2>&1

scripts/build-slot.sh build -- /usr/bin/time -f %e -o .mylang-cache/wave-a/final-fuzz/rc-seconds.txt python3 experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py --kind rc --cases 200 --seed 42 --cache-root .mylang-cache/wave-a/final-fuzz/rc --evidence experiments/new-core-s2-20261005/wave-a/integration/fuzz-rc > experiments/new-core-s2-20261005/wave-a/integration/fuzz-rc.txt 2>&1

scripts/build-slot.sh build -- /usr/bin/time -f %e -o .mylang-cache/wave-a/final-fuzz/rebinding-seconds.txt python3 experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py --kind rebinding --cases 200 --seed 42 --cache-root .mylang-cache/wave-a/final-fuzz/rebinding --evidence experiments/new-core-s2-20261005/wave-a/integration/fuzz-rebinding > experiments/new-core-s2-20261005/wave-a/integration/fuzz-rebinding.txt 2>&1
```

Create `.mylang-cache/wave-a/final-fuzz` before using the timing commands.
`/usr/bin/time` starts after build-slot admission, so its output excludes queue
time. Wrapper progress every 25 cases provides a calibrated runtime estimate;
the provisional allowance is 2–6 minutes per job, subject to concurrent gate
contention and guest compiler cache preparation.

S0, S1 all, and rebinding require 3000 comparisons each; RC requires 1800.
The inherited generators, argument matrices and comparison logic are unchanged.
Rebinding uses its previously accepted Wave A generator extension. The wrapper
enables `MYL_CORE_LEAKCHECK=1`, caps guest builds at 60 seconds and guest runs at
their existing 20/30 seconds, rejects every negative native/compiler return,
leak/fact diagnostic and incomplete run, and saves failed sources under each
evidence directory's `failures/`. Harness-retained mismatch sources also remain
in the job's `sources/` cache directory. `summary.json` reports accepted cases,
old rejections, explicit unsupported refusals, unexplained build failures,
comparison counts and the qualification result. Known language traps remain
part of ordinary differential comparison. Refusals are reported separately
from wrong-answer counts; any refusal still makes this complete matrix fail.
