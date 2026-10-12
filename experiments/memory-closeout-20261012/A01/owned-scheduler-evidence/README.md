# Count-free native scheduler stress

The new fixture explicitly selects the count-free runtime and uses moved captures,
one result transfer per task, explicit owned group end, and implicit joining group
destruction. It performs 1,010,002 increment callbacks plus additional nested tasks
per stress run, a binary tree of depth 12, a chain of depth 2048, and discarded results.
Transferred results remain valid after their group is destroyed. A second take is
refused with R_TASK_GROUP. This supplements the existing legacy scheduler control;
it does not claim that legacy code has been retired.

The two registered tests passed: counted executions at 1/2/8 workers and a separate
ThreadSanitizer execution at eight workers, each also checking repeated-take refusal.
All three counted executions have zero RC events and zero exit-live managed bytes.
Native symbol audits are RC-free. Runtime sources are from 3c8c49475; the added
fixture/test hashes and exact exported binary hashes appear in summary.json.

Reproduce with shared admission:

```sh
MYLANG_P1_FIXTURE_OUTPUT="$PWD/.tmp/owned-scheduler" scripts/build-slot.sh build "$ZIG" build test-core -Dtest-filter='A01 zero RC scheduler' -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
```

Raw counters, symbol tables and the test log are compressed without altering their
contents. Timings in the test log are test execution observations, not paired
runtime performance results. Required final integrated checks remain outstanding.
