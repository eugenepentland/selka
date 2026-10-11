# Native nested gather loop correction, 11 October 2026

Native release compilation of the genuine nested `any` generator source failed
LLVM verification: cloned block `b17` had PHI entries for `b1.14` and `b21.168`,
but only `b21.168` branched there. The optimizer's loop-region walk crossed an
inner loop's break into the enclosing exit and its continuation. Cloning those
blocks preserved external predecessors that never targeted the copies.

Commit `93a4f2bc8562b61501cb486a4b6de251e2598fca`, based on `aa152f8dd`, adds a
closed-region check to the shared loop cloning entry point. Only the header may
have incoming edges from outside a candidate region. Unsafe candidates retain
the original CFG. The LLVM emitter and the producer payloads are unchanged.

The new graph regression reproduces the source through release fact passes and
Core verification. Before the fix it failed exactly with
`main b17: predecessor b1 does not branch here`. Afterward all three focused
native tests passed, including the existing versioned-loop runtime regression
and exact nested `any`/`all` mutation sequences `[3, 4]`. The executable regression
runs Debug, release and release with fact verification, with leak checks enabled.
The final focused/format build passed 24/24 steps and 3/3 tests, with no skips.
Whole-tree Guardian passed all 88 checks. The ReleaseFast installation passed
14/14 steps.

The corrected host SHA256 is
`4ce5f9ab80f5829973aceed8645b1edb122af048348a1ca62d3e4cb968cce5fc`.
Its coordinator SHA256 is
`d0ea4c4afa0ffa9c48162f182c9bc72c7d2cd968bacb1dbb4181514ef39781ab`.
The unchanged qualified seed SHA256 is
`c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`.
The genuine schema10 body package remained frozen at key
`8c8a9ba7faf5260b29e948490b33390853f1d8d1276a9cab232ebf4e5c070e24`,
artifact SHA256
`d0a43425c0c7cea795e8233d815f62a270e3727662673a0f33f9c78d6ca6800f`.

Against that unchanged package, the corrected host passed all 36 comprehension
fixtures and 294 operations, then the original 30 statement fixtures and 228
operations. Each selection compared exact native/shadow/component diagnostics
and full typed output; successful sources ran generated release programs with
fact verification and leak checks. Both selections recorded zero failures and
zero skips. The earlier native-host failure after 193 comprehension operations
is retained without editing its host identity or payload headers.

[Evidence receipt](evidence/selka-native-nested-gather-20261011/receipt.json)
binds gzip archives of all native build/gate logs, exact selected verdicts, and
the original malformed LLVM file and compile command to their byte hashes.
The missing Guardian sibling setup failure is retained. An intermediate run
passed all three tests but failed Guardian for a misplaced spec tag and function
complexity; both issues were corrected before the final green run.

The Guardian commit helper passed its whole-tree 88-check gate, then unexpectedly
launched a full `zig build test` under the small commit slot. Only that owned
process tree was intentionally terminated, yielding status 143; this is not a
successful full test gate. The subsequent normal git commit ran the existing
Guardian hook against the unchanged green inputs and completed successfully.
No Guardian feedback log was edited.

This evidence qualifies the native correction and the selected producer
behaviors. It does not claim full compiler bootstrap or performance acceptance.
