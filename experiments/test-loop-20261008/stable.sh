#!/usr/bin/env bash
# stable.sh FILE: append a comment line to FILE, run tests, remove it, run tests (identities should all hit).
set -uo pipefail
EDA=/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore; P=$EDA/.cache/probe
MYLANG=${MYLANG:-$HOME/.cache/mylang/bench-newcore-5a6b501d/bin/mylang}
export XDG_CACHE_HOME=$P/xdg ZIG_GLOBAL_CACHE_DIR=$P/zig-global ZIG_LOCAL_CACHE_DIR=$P/zig-local TMPDIR=$P/tmp
cd $EDA/mylang; f=$1; cp $f $P/saved-stable.my
R() { /usr/bin/time -f "wall %e" $MYLANG test src --jobs ${JOBS:-4} --cache-dir $P/mylang --max-frames 30000 --max-steps 4000000000 --max-memory 2G > $P/s.out 2> $P/s.err; echo "$(tail -1 $P/s.out) | $(tail -1 $P/s.err)"; }
printf '\n# probe %s\n' "$RANDOM" >> $f; echo -n "with comment:    "; R
cp $P/saved-stable.my $f; echo -n "comment removed: "; R
git -C $EDA diff --quiet -- mylang || echo "WARN tree differs"
