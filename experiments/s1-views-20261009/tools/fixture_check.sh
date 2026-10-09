#!/usr/bin/env bash
# usage: fixture_check.sh FIXTURE.my COMPILER... : CPython oracle, then debug/release/verify-facts
# builds under the leak check for each compiler; prints one md5 per run.
W=/home/epentland/ai/canopy/mylang-worktrees/claude-vk-vp3
fx=$1; shift
out=$W/.tmp/fxcheck; mkdir -p $out
python3 $W/experiments/s1-views-20261009/tools/py_oracle.py "$fx" > $out/py.out 2>&1; echo "py exit=$? $(md5sum < $out/py.out)"
for c in "$@"; do
  tag=$(echo "$c" | md5sum | cut -c1-6)
  for m in "" "--release" "--release --verify-facts"; do
    name=$out/$tag$(echo "$m" | tr -d ' -')
    if ! $c build "$fx" -o $name.exe --cache-dir $out/cache-$tag $m > $name.build 2>&1; then echo "BUILD FAIL $c [$m]"; cat $name.build; continue; fi
    MYL_CORE_LEAKCHECK=1 $name.exe > $name.out 2>&1; st=$?
    echo "$c [$m] exit=$st $(md5sum < $name.out) $(cmp -s $name.out $out/py.out && echo '== py' || echo '!= py')"
  done
done
