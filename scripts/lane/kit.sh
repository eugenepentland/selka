#!/usr/bin/env bash
# kit.sh prepare [REV] | kit.sh path [REV] : the lane kit (docs/tooling/lane-kit.md).
#   prepare  make ~/ai/.home-cache/aw/kit/<short REV>/ once (REV defaults to main's head); a no-op when its READY file exists.
#            base/ a Debug compiler of REV; proj/ the four projects prepared by the BASE compiler's `selka fix` only;
#            proj-base/ the base compiler's check of each (the "before" of newly-refused.sh); PROJECTS.txt the units and commands.
#   path     print the kit directory of REV (whether or not it is READY).
# Stores of the builds are under the kit (stores/), never under ~/.cache. At most three compiler processes at a time.
set -u -o pipefail
. "$(dirname "$0")/lib.sh"
usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; }
cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in -h|--help|"") usage; [ -n "$cmd" ] && exit 0; exit 2;; esac
rev=$(short_rev "${1:-main}")
KIT=$KIT_ROOT/$rev
case "$cmd" in
  path) echo "$KIT"; exit 0;;
  prepare) ;;
  *) usage; exit 2;;
esac

[ -f "$KIT/READY" ] && { echo "kit $rev: READY ($(cat "$KIT/READY" | head -1)) at $KIT"; exit 0; }
mkdir -p "$KIT/logs" "$KIT/stores" || die "cannot create $KIT"
exec 9>"$KIT_ROOT/$rev.lock"; flock -n 9 || die "another prepare of $rev is running (lock $KIT_ROOT/$rev.lock)"
avail=$(awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo)
echo "kit $rev: starting; memory available ${avail} GiB, disk free $(df -h --output=avail "$KIT_ROOT" | tail -1 | tr -d ' ')"
[ "$avail" -ge 4 ] || die "less than 4 GiB of memory available; try later"
ST=$KIT/stores/prepare
times=$KIT/TIMES.txt; : > "$times"
stage() { local name=$1 t=$2; echo "$name $(elapsed "$t")" >> "$times"; echo "kit $rev: $name in $(elapsed "$t")"; }

t=$SECONDS
if [ ! -x "$KIT/base/bin/selka" ]; then "$LANE_DIR/kit-base.sh" "$rev" "$KIT/base" > "$KIT/logs/base.log" 2>&1 || { tail -5 "$KIT/logs/base.log"; die "the base compiler did not build (see $KIT/base.build.log)"; }; fi
mv -f "$KIT/base.build.log" "$KIT/logs/base-build.log" 2>/dev/null; rm -f "$KIT/base.run.log"
stage "base compiler (Debug, $("$KIT/base/bin/selka" --version | cut -d, -f1))" "$t"
BASE=$KIT/base/bin/selka

t=$SECONDS
python3 -B "$LANE_DIR/kitproj.py" clone "$KIT" || die "clone failed"
stage "clones" "$t"

t=$SECONDS
if [ ! -f "$KIT/proj/.prepared" ]; then
  python3 -B "$LANE_DIR/kitproj.py" prepare "$KIT" "$BASE" "$ST" 2>&1 | tee "$KIT/logs/prepare.log" || die "prepare failed"
  date -u +%FT%TZ > "$KIT/proj/.prepared"
fi
stage "prepared with the base compiler's selka fix" "$t"

t=$SECONDS
python3 -B "$LANE_DIR/kitproj.py" sweep "$KIT" "$BASE" "$KIT/proj-base" "$ST" || die "the base compiler's check or fix --check ended oddly (see $KIT/proj-base/SUMMARY.txt)"
stage "base check and fix --check of every unit" "$t"

# One line per project: its units, errors and warnings under the base compiler (the base is recorded as it is, never repaired).
awk -F'\t' '{split($1,a,"~"); p=a[1]; n[p]++; split($3,e,"="); split($4,w,"="); er[p]+=e[2]; wa[p]+=w[2]; if ($2!="rc=0") bad[p]++}
  END{for (p in n) printf "  %s: %d units, base check %d errors, %d warnings, %d units not clean\n", p, n[p], er[p], wa[p], bad[p]+0}' \
  "$KIT/proj-base/SUMMARY.txt" | sort
fixn=$(wc -l < "$KIT/proj-base/fixcheck.txt"); echo "  base fix --check: $fixn files would still change"
{ date -u +%FT%TZ; echo "base $("$BASE" --version | cut -d, -f1)"; } > "$KIT/READY"
echo "kit $rev: READY at $KIT, $(du -sh "$KIT" | cut -f1), total $(elapsed 0)"
