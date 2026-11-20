#!/usr/bin/env bash
# probe.sh [--compiler PATH] [--asan] [--out DIR] [--limit SECONDS] FILE.selka... : check, run with the leak check, and run
# --release each file.
# One line per file: the verdict of each step, the first diagnostic code and line when the check refuses, the first 120
# characters of the debug run's output, and whether the debug and release runs printed the same (stdout and status).
# Files go three at a time; stores of its own (never ~/.cache); details of every step in DIR (default: kit probe-out/<time>).
# --asan runs the debug step with SELKA_CORE_SANITIZE=address and --max-memory 0 (needs the reviewed native libasan).
# The compiler defaults to zig-out/bin/selka of the worktree this script is in; PROBE_STORES names another store folder.
# It waits in the foreground for at most --limit seconds (default 270, under the lane card's 280). Done: the lines, then
# `probe: N files, ...` and `exit status 0; details DIR`. Not done: the lines so far, `still running ... (pid N)`, the one
# command that waits for it again (`probe.sh --wait DIR [--limit S]`, the same result when it is done) and exit status 124;
# the run goes on in its own session. A refused or failing file is a line, not a failing exit status: the lines are the verdict.
set -u
. "$(dirname "$0")/lib.sh"

one() {  # one COMPILER ASAN OUT STORES FILE : the probe of one file; prints its line
  local c=$1 asan=$2 out=$3 st=$4 f=$5 n k san="" mm="" rc r1 r2 first v1 v2 sum
  n=$(basename "$f" .selka); k=$(( $(echo "$n" | cksum | cut -d' ' -f1) % 3 ))
  local cache=$out/cache-$k
  local tag=""
  [ "$asan" = 1 ] && { san="SELKA_CORE_SANITIZE=address"; mm="--max-memory 0"; tag="+asan"; }
  run_with "$st" "$c" check "$f" > "$out/$n.check.out" 2>&1; rc=$?
  if [ $rc -ne 0 ]; then
    first=$(grep -a -m1 'error\[' "$out/$n.check.out" | sed -E 's/^([^ ]*):([0-9]+):[0-9]+: error\[([A-Za-z0-9_]+)\].*/\3 at line \2/')
    [ -n "$first" ] || first=$(head -c 100 "$out/$n.check.out" | tr '\n' ' ')
    printf '%s: check REFUSED %s (status %s), not run\n' "$f" "$first" "$rc"; return
  fi
  # shellcheck disable=SC2086
  timeout 300 "$LANE_DIR/with-stores.sh" "$st" env $(compiler_env "$c") SELKA_CORE_LEAKCHECK=1 $san "$c" run "$f" $mm --cache-dir "$cache" \
    < /dev/null > "$out/$n.run.out" 2> "$out/$n.run.err"; r1=$?
  timeout 300 "$LANE_DIR/with-stores.sh" "$st" env $(compiler_env "$c") "$c" run "$f" --release --cache-dir "$cache-rel" \
    < /dev/null > "$out/$n.release.out" 2> "$out/$n.release.err"; r2=$?
  v1=ok; [ $r1 -ne 0 ] && v1="status $r1 $(grep -a -o -m1 'R_[A-Z_]*\|[Ll]eak[a-z ]*' "$out/$n.run.err" | head -1)"
  v2=ok; [ $r2 -ne 0 ] && v2="status $r2 $(grep -a -o -m1 'R_[A-Z_]*' "$out/$n.release.err" | head -1)"
  if [ $r1 -eq $r2 ] && cmp -s "$out/$n.run.out" "$out/$n.release.out"; then sum=same; else sum=DIFFERENT; fi
  first=$(head -c 400 "$out/$n.run.out" | tr '\n' '|' | cut -c1-120)
  [ -n "$first" ] || first="(no stdout) err: $(head -1 "$out/$n.run.err" | sed -E 's,^[^ :]*/,,' | cut -c1-110)"
  printf '%s: check ok | debug+leakcheck%s %s | release %s | %s | out: %s\n' "$f" "$tag" "$v1" "$v2" "$sum" "$first"
}

if [ "${1:-}" = --one ]; then shift; one "$@"; exit 0; fi
if [ "${1:-}" = --run-all ]; then  # --run-all DIR COMPILER ASAN STORES : the background half; leaves DIR/done when every file has a line
  shift; out=$1; c=$2; asan=$3; st=$4; echo $$ > "$out/pid"
  xargs -P 3 -I{} "$0" --one "$c" "$asan" "$out" "$st" {} < "$out/files.txt" > "$out/lines.unordered" 2>&1
  status=$?; date +%s > "$out/finished"; echo "$status" > "$out/done"; exit 0
fi

# report DIR LIMIT : wait for DIR/done up to LIMIT seconds, then print the lines (in argument order) and the closing line.
report() {
  local out=$1 limit=$2 n=0 got=0 refused=0 bad=0 diff=0 f line pid="" late=() begin t0=$SECONDS
  while [ ! -e "$out/done" ] && [ $((SECONDS - t0)) -lt "$limit" ]; do
    pid=${pid:-$(cat "$out/pid" 2> /dev/null)}
    if [ -n "$pid" ] && ! kill -0 "$pid" 2> /dev/null; then sleep 1; break; fi  # gone: `done` is written just before it exits
    sleep 0.5
  done
  pid=${pid:-$(cat "$out/pid" 2> /dev/null)}
  begin=$(cat "$out/started")
  while IFS= read -r f; do
    n=$((n + 1))
    line=$(grep -a -F -- "$f: " "$out/lines.unordered" 2> /dev/null | head -1)
    if [ -z "$line" ]; then late+=("$(basename "$f")"); continue; fi
    got=$((got + 1))
    case $line in *"check REFUSED"*) refused=$((refused + 1));; esac
    case $line in *"| debug+leakcheck status"*|*"| release status"*) bad=$((bad + 1));; esac
    case $line in *"| DIFFERENT |"*) diff=$((diff + 1));; esac
    printf '%s\n' "$line" | sed "s,$PWD/,,"
  done < "$out/files.txt"
  if [ -e "$out/done" ]; then
    echo "probe: $n files, $refused check REFUSED, $bad run not ok, $diff debug and release DIFFERENT, in $(( $(cat "$out/finished" 2>/dev/null || date +%s) - begin ))s"
    echo "exit status 0; details (every step's output) $out"; return 0
  fi
  if [ -n "$pid" ] && ! kill -0 "$pid" 2> /dev/null; then
    echo "probe: the run ended without finishing (its process $pid is gone): $got of $n files have a line; run it again"
    echo "exit status 1; details $out"; return 1
  fi
  echo "still running after $(( $(date +%s) - begin ))s (pid ${pid:-unknown}): $got of $n files done; not yet: ${late[*]:0:5}"
  echo "wait: scripts/lane/probe.sh --wait $out"
  echo "exit status 124; details $out"; return 124
}

compiler=$LANE_REPO/zig-out/bin/selka; asan=0; out=""; files=(); limit=270; waitdir=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    --compiler) compiler=$(realpath "$2"); shift 2;;
    --asan) asan=1; shift;;
    --out) out=$(realpath -m "$2"); shift 2;;
    --limit) limit=$2; shift 2;;
    --wait) waitdir=$(realpath -m "$2"); shift 2;;
    -*) die "unknown option $1 (probe.sh -h)";;
    *) files+=("$(realpath "$1")"); shift;;
  esac
done
if [ -n "$waitdir" ]; then
  [ -f "$waitdir/files.txt" ] && [ -f "$waitdir/started" ] || die "no probe run recorded in $waitdir"
  report "$waitdir" "$limit"; exit $?
fi
[ ${#files[@]} -gt 0 ] || die "no files (probe.sh -h)"
compiler_check "$compiler"
for f in "${files[@]}"; do [ -f "$f" ] || die "no such file: $f"; done
stores=${PROBE_STORES:-$KIT_ROOT/stores/probe}
[ -n "$out" ] || out=$KIT_ROOT/probe-out/$(date +%y%m%d-%H%M%S)
mkdir -p "$out" || die "cannot create $out"
rm -f "$out/done" "$out/finished" "$out/lines.unordered"
printf '%s\n' "${files[@]}" > "$out/files.txt"; date +%s > "$out/started"
# the files go three at a time in a session of their own, so that the run outlives this call when it passes the limit
setsid "$0" --run-all "$out" "$compiler" "$asan" "$stores" < /dev/null > /dev/null 2>&1 &
report "$out" "$limit"; exit $?
