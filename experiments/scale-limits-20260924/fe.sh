#!/usr/bin/env bash
# Cold build frontend (emit-project-qbe, as `mylang build` runs it) at one tier with a fresh cache,
# phase-attributed memory. usage: fe.sh TIER COMPILER LABEL [host-limit]
set -u
tier=$1
compiler=$2
label=$3
root=/home/epentland/.cache/mylang-tmp/scale-limits
export TMPDIR=/home/epentland/.cache/mylang-tmp
[ $# -ge 4 ] && export MYLANG_HOST_MEMORY_LIMIT=$4
rm -rf "$root/fe-$tier" "$root/fe-$tier-cache"
cp -r "$root/$tier/mylang" "$root/fe-$tier"
cd "$root/fe-$tier"
taskset -c 0-11 python3 "$root/phase_rss.py" "$root/phase-$tier-$label.json" -- "$compiler" emit-project-qbe "$root/fe-$tier/main.my" \
  --lean-manifest=executable "--cache-dir=$root/fe-$tier-cache" --drop-debug --drop-step-checks --drop-frame-checks
rm -rf "$root/fe-$tier" "$root/fe-$tier-cache"
