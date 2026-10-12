# Native time/entropy fixture migration

The original public reference contained two removed type names (`clock_cap`,
`random_cap`) and a redundant `module main` header. The proposed source changes
only those two lines: use `Clock`/`Entropy` and omit the header. All test bodies,
expected values, call order and repeated-use assertions are byte-preserved.
No explicit copies were added. Original and migrated sources/hashes plus both
original/intermediate parser failures remain in this directory.

On the same Support7 compiler, all five build modes now pass. The linked native
v7 provider returns the exact original clock/entropy values; six additional
runs per mode cover unavailable, denied and failed results from each provider.
All 35 executions return the expected status with zero observed RC events, zero
managed exit-live bytes and clean LLVM/symbol audits. Raw counters are retained.
The existing redundant-effects warning is recorded in the build receipts.

This is a source migration, not a compiler-only improvement. It supersedes the
five original fixture-refusal lanes only for the proposed current source; their
receipts remain unchanged. The separate memo warm-cache failure still blocks
complete common-compiler qualification.
