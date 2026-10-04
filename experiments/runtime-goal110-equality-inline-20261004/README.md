# B2 equality followup

This separate tree starts at join candidate 5a60ef10. Join is unchanged here;
its measured compiler/assets and the rejected equality965 tree remain intact.
No benchmark or contract edits are made.

The first equality candidate965 improved the frozen distributions but regressed
ordinary equal64-byte values by 1.138–1.207 in portable-C helper probes and
LLVM large string_search by1.1589 in a quiet15round guest repeat. It also lost
hot-loop LLVM inlining. This followup retains bounded short comparisons
through16bytes, preserves original libc comparison from17through256, and
places endpoint rejection above256 in a separate noinline helper. Empty
content returns before computing view storage, matching the original path.

The conservative256byte policy is chosen from independent distribution
evidence: short<=16 benefits,64equal suffers,257/4096 equal/middle formats
are nearneutral with strong endpoint mismatch gains. It is a power-of-two
limit separating medium and bulk work, unrelated to frozen fixture selection.
Additional lengths around64/128/256 and ordinary equal/prefix sharing views
are required before any integration. The policy and wrapper-inlineability
remain hypotheses pending emitted guest-code and distribution measurements.

Exact-allocation/unaligned/every-byte mismatch tests from965 are retained.
Five native suites pass with ASan/UBSan at -O3, including exact-payload equality,
views/indexing and structural equality/allocation refusal. native-tests.log
retains the check output. No guest build, timing or acceptance is claimed by
the implementation commit. The official Debug host and all24 ReleaseFast
guests now build with verified reference reuse. Text guests pass128 exact
oracle/control/artifact records. Actual LLVM hot equality still calls the
wrapper at104f1b7 and104f229: outlining the long helper alone does not restore
inlining. No timing or integration is claimed. static-validation.json retains
the receipt, source/log and raw/archive hashes; llvm-kernel-equal.asm.gz keeps
the actual kernel, wrapper and long-helper code. This source/installed runtime
tree remains fixed while a separate followup tests inline linkage.
