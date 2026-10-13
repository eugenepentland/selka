#!/usr/bin/env bash
set +e
for case_name in fib equality; do
  perf record -e cycles:u -F 499 -g -o ".tmp/lox-eda-parity/P2/base-${case_name}.perf" -- timeout 25 .tmp/lox-eda-parity/P2/base --engine=vm "experiments/lox-eda-zero-rc-20261012/lox/full-size-counters/inputs/vm-${case_name}.lox" > "experiments/lox-eda-parity-20261013/P2/base-${case_name}-perf.log" 2>&1
  profile_status=$?
  printf '%s perf exit status: %s\n' "$case_name" "$profile_status"
  cat "experiments/lox-eda-parity-20261013/P2/base-${case_name}-perf.log"
done
