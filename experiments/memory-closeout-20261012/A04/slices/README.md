# Slice snapshot lifetime repair

Checked ownership cannot retain an owner to keep an optimizer-created span alive.
The previous slice-to-view rewrite missed owners moved into managed storage and
parents of borrowed collection elements. Source-valid independent slices could
therefore fail ownership qualification after optimization.

The repair follows borrowed parents and bidirectional phi aliases, then retains
the materialized snapshot if an owner moves, updates, or enters owned storage.
It also guards materialized span-to-view collapse. Read-only source slices still
fuse. Analysis is O(nodes + edges) per candidate query, including a graph rebuild;
this is not a whole-function linear-time claim. Conservative source-order false
positives retain independent storage. Indirect view-returning function signatures
remain explicitly unsupported by IR verification, so only direct view contracts
participate in parent tracking. A07 statically reviewed consuming operands,
indirect argument offsets and parent/phi traversal.

`focused-tests.json` records four passing IR tests: moved owner, replaced parent,
materialized span, and retained read-only fusion. The coordinator registered the
new test module. Existing S1 specification identifiers describe these contracts.

`prototype-01/results.json` pins source 92edc7a99e6ca2c03928586bc66f6f563a93b3b2
plus the recorded production diff and compiler SHA256
3aa1647fd499c237083289c5d44e22efa0ceb37937ad974865275e5cfd80d65c.
The new native regressions pass all five zero-RC modes. Original `s1_reads` passes
all five zero-RC modes and the ordinary control. Original `s1_views` passes its
ordinary control; its five checked modes refuse earlier at `sorted(list(d.keys()))`
with E_SINGLE_OWNER_BORROW in this worker compiler, which lacks the integrated
sorted/list-copy repairs. All five refusals remain in the 17-lane denominator;
the full original fixture still requires the integrated compiler rerun. The
source-valid S1 sources and their assertions were not changed to conceal defects.

All ten admitted counted zero-RC lanes have zero runtime RC and no managed exit
bytes; their LLVM and linked-symbol audits pass. This is correctness evidence,
not runtime/RSS or allocation-saving evidence. The exact old harness is retained
beside the prototype report; the current harness uses local pinned output oracles.
Run it directly because it owns bounded shared build admission:

```sh
python3 -B experiments/memory-closeout-20261012/A04/slices/qualify.py \
  --compiler /path/to/integrated/bin/mylang --phase final-candidate \
  --source-commit FULL_SHA
```

The integrated Support6 rerun (`support6-01/results.json`) passes all 17/17
lanes: the new regression program in five modes, and each unchanged original
s1_reads/s1_views program in five checked modes plus ordinary. Compiler source
is 5167c588be79dd43d21d5013c36db15110bf239b, SHA256
bc6432a75fc1fa0dbcbd2048a5c8dbe2909d7590e90ae729688ed4f6e69978d4.
All fifteen counted checked executions have RC0, no managed exit bytes and clean
LLVM/symbol audits. The older worker compiler's sorted/list refusal is resolved
in this integrated artifact; no additional source migration changed either S1
program. The full final C1/C2/C3 reruns remain required after affected changes.
Shared admission waited about 250 seconds for the last fixture; queue time is
not compiler or program timing and is not included in any performance claim.
