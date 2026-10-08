#!/usr/bin/env bash
# PM-2 profile of one binary on CPU 8. The kernel caps sampling at 1000 Hz
# (perf_event_max_sample_rate), so the program is repeated for about SECONDS
# under one `perf record`. Two passes: user cycles (where time goes) and user
# instructions retired (where the instructions go). For each, the symbol report
# and `perf annotate` of the NSYMS hottest symbols; raw perf.data is deleted.
# usage: prof.sh OUTDIR NAME NSYMS SECONDS -- ARGV...
set -u
out=$1 name=$2 nsyms=$3 seconds=$4; shift 5
mkdir -p "$out"
start=$(date +%s.%N)
taskset -c 8 "$@" > /dev/null 2>&1
end=$(date +%s.%N)
reps=$(python3 -c "print(max(1, min(2000, int($seconds / max(1e-3, $end - $start)))))")
quoted=$(printf '%q ' "$@")
for event in cycles instructions; do
  data="$out/$name.$event.perf.data"
  taskset -c 8 perf record -q -e "cpu_core/$event/u" -F 1000 -o "$data" -- sh -c "for i in \$(seq $reps); do $quoted > /dev/null 2>&1; done" 2>"$out/$name.$event.record.err"
  perf report -i "$data" --stdio --no-children --sort dso,sym --percent-limit 0.3 2>/dev/null | grep -v '^$' > "$out/$name.$event.report.txt"
  syms=$(perf report -i "$data" --stdio --no-children --sort sym 2>/dev/null | grep -E '^ +[0-9.]+%' | head -"$nsyms" | sed -E 's/^ +[0-9.]+% +\[[^]]+\] +//')
  : > "$out/$name.$event.annotate.txt"
  while IFS= read -r sym; do
    [ -z "$sym" ] && continue
    echo "==== $sym" >> "$out/$name.$event.annotate.txt"
    perf annotate -i "$data" --stdio --no-source "$sym" 2>/dev/null >> "$out/$name.$event.annotate.txt"
  done <<< "$syms"
  rm -f "$data"
done
echo "$name reps=$reps"
