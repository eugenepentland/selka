#!/usr/bin/env bash
# probe.sh MODE [EDIT]: run EDA's `mylang test src --jobs 4` in a private cache.
#   warm        run until everything is cached
#   edit KIND   apply leaf|hub|iface edit, time one test run, revert, rewarm
set -uo pipefail
EDA=/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore
P=${PROBE:-$EDA/.cache/probe}
MYLANG=${MYLANG:-$HOME/.cache/mylang/bench-newcore-5a6b501d/bin/mylang}
export XDG_CACHE_HOME=$P/xdg ZIG_GLOBAL_CACHE_DIR=$P/zig-global ZIG_LOCAL_CACHE_DIR=$P/zig-local TMPDIR=$P/tmp
mkdir -p $TMPDIR
cd $EDA/mylang
if [ "${JOBS:-4}" = all ]; then JOBFLAG=""; else JOBFLAG="--jobs ${JOBS:-4}"; fi
run() { /usr/bin/time -f "wall %e s  user %U s  sys %S s  maxrss %M KB" ${WRAP:-} "$MYLANG" test src ${JOBFLAG} --cache-dir "$P/mylang" --max-frames 30000 --max-steps 4000000000 --max-memory 2G "$@" > $P/last.out 2> $P/last.err; local c=$?; tail -1 $P/last.out; tail -1 $P/last.err; return $c; }
edit() {
  case $1 in
    leaf) f=src/kicad_sch_stagger.my; a='    map = nets';;
    hub) f=src/sexpr_parser.my; a=$(python3 - <<'PY'
import tomllib;print(tomllib.load(open('/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore/harness/maps/mylang-new.toml','rb'))['edits']['hub_body']['anchor'])
PY
);;
    comment) f=src/sexpr_parser.my; a=COMMENT;;
    iface) f=$(python3 -c "import tomllib;print(tomllib.load(open('$EDA/harness/maps/mylang-new.toml','rb'))['edits']['interface']['file'])"); a=EOF;;
  esac
  cp $f $P/saved.my
  python3 - "$f" "$a" "$1" "$EDA" <<'PY'
import sys,tomllib,re,time
f,a,kind,eda=sys.argv[1:]
m={'anchor':'EOF','text':'# probe comment {nonce}'} if kind=='comment' else tomllib.load(open(eda+'/harness/maps/mylang-new.toml','rb'))['edits'][{'leaf':'leaf_body','hub':'hub_body','iface':'interface'}[kind]]
text=m['text'].replace('{nonce}',str(int(time.time()*1000)%1000000000))
src=open(f).read()
if m['anchor']=='EOF':
    new=src+('' if src.endswith('\n') else '\n')+text+'\n'
else:
    lines=src.splitlines(keepends=True); i=[k for k,l in enumerate(lines) if l.rstrip('\r\n')==m['anchor']]; assert len(i)==1
    ind=re.match(r'\s*',m['anchor']).group(0); lines.insert(i[0]+1,''.join(ind+l+'\n' for l in text.splitlines())); new=''.join(lines)
open(f,'w').write(new)
PY
  echo "$f"
}
case $1 in
  warm) run; run;;
  edit) f=$(edit $2); echo "edited $f"; run; cp $P/last.out $P/edit-$2.out; cp $P/last.err $P/edit-$2.err; cp $P/saved.my $f; git -C $EDA diff --quiet -- mylang || echo "WARN: tree differs"; WRAP= run;;
esac
