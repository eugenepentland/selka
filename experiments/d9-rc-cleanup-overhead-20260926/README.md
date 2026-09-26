# RC normal-cleanup overhead

`empty-scan.json` compares the cumulative `d69e579c` runtime with a normal-frame
cleanup loop that skips disarmed journal entries before calling slot drop.
It preserves complete build commands, compiler/binary/source hashes, three
interleaved private CPU0 instruction runs per backend, actual backend/LTO
manifest checks, stdout hashes, and separately captured ownership counters.
Both compilers are Debug. LLVM explicitly uses O3/full LTO with no later QBE
selection. The source is the unchanged depth-12 binary-tree diagnostic retained
in `../d9-rc-pointer-fastpath-20260926/`. This is not corpus acceptance.

`inline-invariant.json` repeats all three arms after replacing successful
out-of-line invariant calls with an inline condition and a cold, nonreturning
failure helper. Both measured artifacts retain `myl_rc_invariant_failed` and
have no `myl_rc_invariant` success symbol. All original conditions remain.
The unit fixture checks single evaluation and child-process SIGABRT on failure.
