#!/usr/bin/env bash
# child.sh JOBS: leaf edit, then time the one child that dominates (export_kicad_sch_test) alone, revert.
set -uo pipefail
EDA=/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore; P=$EDA/.cache/probe
MYLANG=${MYLANG:-$HOME/.cache/mylang/bench-newcore-5a6b501d/bin/mylang}
export XDG_CACHE_HOME=$P/xdg ZIG_GLOBAL_CACHE_DIR=$P/zig-global ZIG_LOCAL_CACHE_DIR=$P/zig-local TMPDIR=$P/tmp
cd $EDA/mylang; f=src/kicad_sch_stagger.my; cp $f $P/saved-child.my
python3 - $f <<'PY'
import sys,time
f=sys.argv[1]; s=open(f).read(); a='    map = nets\n'; assert s.count(a)==1
open(f,'w').write(s.replace(a,a+'    _ = %d\n'%(int(time.time()*1000)%10**9)))
PY
T() { /usr/bin/time -f "  %C | wall %e s user %U sys %S" "$@" > $P/child.out 2> $P/child.err; tail -1 $P/child.err | sed 's/.*| /  /'; }
echo "check:"; T ${WRAP:-} $MYLANG check src/export_kicad_sch_test.my --cache-dir $P/mylang
echo "test child jobs=$1:"; T ${WRAP:-} $MYLANG test src/export_kicad_sch_test.my --json --jobs $1 --cache-dir $P/mylang ${FILTER:+--filter $FILTER} --max-frames 30000 --max-steps 4000000000 --max-memory 2G
python3 -c "import json;d=json.load(open('$P/child.out'));print('  ',{k:d[k] for k in ['passed','cached','failed']})"
cp $P/saved-child.my $f; git -C $EDA diff --quiet -- mylang || echo "WARN tree differs"
