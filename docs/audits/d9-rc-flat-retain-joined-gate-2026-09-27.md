# Joined bounded physical-retain correctness checkpoint

Frozen source `d1d8b3c46ac41e832410a03aad49a5a6a1a54b07` joins the bounded
physical-retain optimization `c2357ae4` with the preceding append, borrowed-helper
and scalar-loop changes. Runtime documentation and the repaired managed example
are also integrated. The descriptor-repeat proposal is documentation only at
this checkpoint. The ordinary runtime remains GC.

The Debug installation passes 19/19 steps; its immutable compiler SHA256 is
`12a3693929913d50385248a5938fcf57694de8a3538e65f150432c998936d268`.
The complete gate passes 94/94 main steps with 2,315 executed tests, 51/51 QBE
steps with 440 tests, 29/29 native-build steps and 2/2 formatting steps.
The main runner's 23,608 exclusions are its shard partition, not missing tests.
Whole-tree Guardian passes all 88 checks without a ratchet waiver.

Both actual backend language sweeps run counted RC with forced uncached
execution: each passes 931/931 assertions across 160 programs, with zero failures,
skips, cached results, dropped files or unloaded files. Source and HEAD stayed
frozen throughout the complete gate and sweeps. The
[archive](../../experiments/d9-rc-flat-retain-joined-gate-20260927/README.md)
contains exact scripts, raw logs, machine-readable outcomes and artifact hashes.

An additional independent audit of the isolated flat-retain archive verifies
all eight rows, 48 unscaled instruction observations, eight exact balanced
ownership records and 16 paired guest controls. It also rechecks the original
compiler, binary and input hashes on this machine. The report's function count
is corrected to 128 to match its authoritative emission identity.

This checkpoint establishes combined correctness only. The isolated instruction
reductions leave substantial overhead against accepted GC. Full 43-program
instruction and peak-RSS acceptance, the ordinary RC default transition and final
validation remain open.
