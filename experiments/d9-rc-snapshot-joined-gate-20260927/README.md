# Joined record-field snapshot validation

Frozen source `5b87601297f01810968b9f7ac554c484d5848cca` combines scalar record publication `6a75eb2a`, private
scalar descriptor identity `45567840`, and the record-field snapshot correction
`2631a44f`. Its Debug compiler SHA256 is
`f87393b249f45699d63a1f5a81dc47fb59faa41d1396fc8035131d7b2533b120`. The ordinary runtime remains GC.

The complete four-command gate passes, with 2,325 executed main tests,
442 QBE tests, native-build and formatting checks. Both forced counted-RC
sweeps pass 952 assertions across 163 programs, with no failures, skips, cached
verdicts, dropped files or unloaded files. Whole-tree Guardian passes all 88
checks without a waiver. Source and HEAD stayed frozen throughout validation.
The archive includes the exact scripts, raw logs and artifact hashes. Invoke
both scripts with the frozen source commit as their required first argument;
the full gate additionally uses `flock ../.d9-closeout-gate.lock`.

The new snapshot fixtures now run in the combined language suite. The separate
correction archive retains the historical arena failures under both runtimes
and heap failure under GC; prior RC heap ownership masked the missing semantic
copy. It also records 188 focused native assertions and 16 trap controls.
The accepted GC performance baseline remains unchanged.

This correctness checkpoint does not establish Stage 4 performance acceptance.
The earlier full-corpus diagnostic still identifies its own immutable compiler,
and isolated optimization results remain tied to their original sources.
Complete instruction and peak-RSS acceptance, the ordinary RC default transition,
and final documentation and validation remain required.
