#!/usr/bin/env bash
# CE-X Part 3: wall time, final against base, every timed process on CPU 10 under cpu10.lock.
# No build runs while the lock is held: every binary comes from timing-prep.sh / ce.py, the Lox
# harness runs with LOX_PREBUILT=1, and parity_locked.py takes the lock only for the timing.
#   part3.sh feasible | lox | eda | parity | rows N
set -eu
WT=/home/epentland/ai/canopy/mylang-worktrees/codex-runtime-parity-3
source $WT/experiments/runtime-parity-3-20261009/tools/env.sh
X=$WT/experiments/runtime-parity-3-20261009
C=${RP3_FINAL:-/home/epentland/.cache/mylang/rp3-base-41ed360fb/bin/mylang}
B=/home/epentland/.cache/mylang/rp3-base-41ed360fb/bin/mylang
LOCK=/run/user/1000/mylang-slots/cpu10.lock
L=$WT/.mylang-cache/lox
EDA=/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore
load() { echo "$(date -u +%T) $1 load $(cut -d' ' -f1-3 /proc/loadavg)"; }
case ${1:-} in
feasible)
  load "feasible start"
  python3 "$X/tools/quiet.py" -- python3 $X/tools/feasible.py $L $X/results/lox-feasible.json
  load "feasible end" ;;
lox)
  # Wave 3 requires all 13 cells of each engine.
  export LOX_SKIP=
  cd $L
  export WORK=$L LOX_BENCH_MYLANG=$C LOX_PREBUILT=1 XDG_CACHE_HOME=$L/.tmp/xdg PYTHONDONTWRITEBYTECODE=1 PATH=$HOME/.cargo/bin:$PATH
  export TMPDIR=$L/.tmp/lox-bench/tmp
  load "lox runtime start (LOX_SKIP=$LOX_SKIP)"
  python3 "$X/tools/quiet.py" -- python3 harness/measure.py runtime --ports mylang,mylang-base,zig,rust,go --profiles release,zig:release-safe --rounds 3 --cpu 10; echo "runtime=$?"
  load "lox runtime end"; ls -td results/*-runtime | head -1 ;;
eda)
  R=$EDA/.cache/release
  export TMPDIR=$WT/.tmp
  load "eda runtime start"
  python3 "$X/tools/quiet.py" -- python3 $WT/experiments/bench-newcore-20261008/eda/runtime.py --repo $EDA --rounds 10 --cpu 10 \
    --work $WT/.mylang-cache/rp3/eda-runtime-out --out $X/results/eda-runtime.json \
    zig-fast=$R/zig-fast/bin/eda-sch zig-safe=$R/zig-safe/bin/eda-sch rust=$R/rust-target/release/eda-sch go=$R/go/eda-sch \
    mylang-base=$WT/.mylang-cache/rp3/ce/bin/base/eda-plain mylang-final=$WT/.mylang-cache/rp3/ce/bin/final/eda-plain
  echo "eda=$?"; load "eda runtime end" ;;
parity)
  P=$WT/.mylang-cache/rp3/parity
  mkdir -p $P/tmp $P/zig-global
  export TMPDIR=$P/tmp ZIG_GLOBAL_CACHE_DIR=$P/zig-global PATH=$HOME/.cargo/bin:$PATH
  cd $WT
  # The base run times only the mylang arms (zig-fast is always kept, for the ratios): the other
  # reference arms are timed once, in the final run (coordinator's cut, 2026-10-08).
  MY_ARMS="my my-arena my-array my-class my-flat my-keyed my-sorted my-tuned my-wrapping"
  for who in final base; do
    comp=$C; arms=""; [ $who = base ] && comp=$B && arms="--arms $MY_ARMS"
    load "parity $who start"
    python3 $X/tools/parity_locked.py run --mylang $comp --zig zig --rustc $HOME/.cargo/bin/rustc $arms ${PARITY_FILTER:+--filter $PARITY_FILTER} \
      --cpu 10 --rounds 9 --warmups 2 --jobs 4 --work $P/work-$who --json $X/results/parity-$who.json \
      > $X/logs/parity-$who.stdout.txt 2> $X/logs/parity-$who.stderr.txt; echo "parity $who=$?"
    load "parity $who end"
  done ;;
rows)
  n=${2:?run number}
  cd $WT
  load "rows $n start"
  python3 "$X/tools/quiet.py" -- python3 experiments/runtime-parity-3-20261009/tools/rows_allrefs.py --mylang $B --core $C --runner /home/epentland/.cache/mylang/rp3-rows-41ed360fb/bin \
    --bin $WT/.mylang-cache/rp3/all46 --json $X/results/all46-$n.json > $X/logs/all46-$n.log 2>&1; echo "rows $n=$?"
  load "rows $n end" ;;
*) echo "usage: part3.sh feasible|lox|eda|parity|rows N" >&2; exit 2 ;;
esac
