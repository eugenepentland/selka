# Joined nonheld-capture validation checkpoint

Frozen source `6983288b12c40579483c935449aa6b8488075a89` joins exact nonheld
scalar-list capture proof `aca67a7a` with bounded physical retention and the
preceding compiler/runtime changes. Its immutable Debug compiler SHA256 is
`20ba661290bf67d3d88ab47ee80e88a2306ebadffc945523eaca60a21d355885`.
The ordinary runtime remains GC.

The Debug installation passes 19/19 steps. All four required gates pass: 94/94
main steps with 2,318 executed tests, 51/51 QBE steps with 442 tests, 29/29 native
build steps and 2/2 formatting steps. The main runner's 23,641 exclusions are
its shard partition. Whole-tree Guardian passes all 88 checks without a waiver.
Both actual backend sweeps force counted-RC execution: 938/938 assertions across
161 programs each, with zero failed, skipped, cached, dropped or unloaded cases.
Source and HEAD stayed frozen through these runs. The
[archive](../../experiments/d9-rc-nonheld-joined-gate-20260927/README.md)
contains exact scripts, complete raw outcomes and identity hashes.

The imported nonheld-capture evidence verifier passes its 468 focused guest
assertions, 48 paired controls, 16 unchanged counted workloads and 72 timing
receipts. Root separately parsed all 72 raw instruction records and verified
100% counter running. The measured sieve improvement does not establish full
performance acceptance.

A separate new control in isolated scalar-record slice `6a75eb2a` exposed a
record-field snapshot defect on immutable predecessor `468bd8e5` and its own
candidate, under GC and RC on both backends. Copying a record and then appending
to its child can change the saved record's child too. Reduced heap and arena
cases reproduce it; a bare-list snapshot control remains correct. Diagnosis
points to missing mutation ancestry through compiler field receivers in the
shared ownership analysis. This is open correctness work, not an accepted
expected result or a claim supported by the passing gate above.

Stage 4 still requires that correctness repair, the complete 43-program
instruction and peak-RSS acceptance, the ordinary RC default transition and
final combined validation. No threshold or value/arena rule is waived.
