#!/usr/bin/env bash
# Repeated-edit probe: does a second edit with the same line shift reuse the first's work?
P=/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore/.cache/probe-shift-$1
MY=$HOME/.cache/mylang/bench-main-352d9396/bin/mylang
export XDG_CACHE_HOME=$P/xdg ZIG_GLOBAL_CACHE_DIR=$P/zig-global ZIG_LOCAL_CACHE_DIR=$P/zig-local TMPDIR=$P/tmp
mkdir -p $TMPDIR
cd /home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore/mylang
t() { taskset -c 0,1,4-9,12-19 /usr/bin/time -f "%e s user %U" $MY test src --cache-dir $P/mylang --max-frames 30000 --max-steps 4000000000 --max-memory 2G 2>&1 >$P/out | tail -1; tail -1 $P/out; }
t >/dev/null; t >/dev/null
f=src/kicad_sch_stagger.my; cp $f $P/saved
ed() { python3 - "$f" "$1" <<PY
import sys; f,text=sys.argv[1:]; src=open(f).read().splitlines(keepends=True)
i=[k for k,l in enumerate(src) if l.rstrip()=="    map = nets"][0]
src.insert(i+1, "".join("    "+l+"\n" for l in text.split("|"))); open(f,"w").write("".join(src))
PY
}
for spec in "one-line A:_ = 111111" "one-line B:_ = 222222" "two-lines C:_ = 333333|_ = 333333" "two-lines D:_ = 444444|_ = 444444" "one-line E:_ = 555555"; do
  ed "${spec#*:}"; echo "${spec%%:*}: $(t | paste - -)"; cp $P/saved $f; t >/dev/null
done
git -C .. diff --quiet -- mylang && echo tree-clean
