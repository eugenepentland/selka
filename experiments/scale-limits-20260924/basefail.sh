#!/usr/bin/env bash
# How the fd36abc2 baseline fails at a tier: no configuration, then with a raised byte budget.
set -u
tier=$1
base=/home/epentland/ai/trials/devspeed-20260923-private/compilers/integration-183251a9/bin/mylang
root=/home/epentland/.cache/mylang-tmp/scale-limits
export TMPDIR=/home/epentland/.cache/mylang-tmp
rm -rf "$root/basefail-$tier"
cp -r "$root/$tier/mylang" "$root/basefail-$tier"
cd "$root/basefail-$tier"
echo "== check, no mylang.json"
taskset -c 0-11 "$base" check main.my 2>&1 | head -c 400; echo
echo "== test, no mylang.json"
taskset -c 0-11 "$base" test main.my --cache-dir "$root/basefail-$tier-cache" 2>&1 | tail -c 300; echo
printf '{"version":1,"budgets":{"max_total_bytes":67108864}}\n' > mylang.json
echo "== check, max_total_bytes 64 MiB"
taskset -c 0-11 "$base" check main.my 2>&1 | head -c 400; echo
echo "== test, max_total_bytes 64 MiB"
taskset -c 0-11 "$base" test main.my --cache-dir "$root/basefail-$tier-cache" 2>&1 | tail -c 300; echo
