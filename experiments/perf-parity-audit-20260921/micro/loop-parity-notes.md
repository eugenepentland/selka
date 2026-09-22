# Loop-parity targets: measured mechanisms and next steps

Written while the harness shell was unavailable (see "Environment" below), so
nothing in this file has been built or measured since commit 6fd70dc6. Treat it
as a handoff, not as a result.

## Landed

`6fd70dc6 perf: keep a float's NaN canonicalisation off the finite path`
`float_loop` 2.76x -> 1.02x zig (target met). Mechanism, profile evidence and
medians are in the commit message; the new spec bullet is `QBE-FLOAT-CANON-1`.

## bytes_scan (1.43x, target 1.30x) -- diagnosed, not fixed

Profile (`.tmp/verify/selfprof.py`, `.tmp/verify/hotinsn.py`, 60 runs): 100% of
samples in `entry_run`; the inner scan is

    10075a0 inc %rdi / 10075a3 dec %r8 / 10075a6 je exit
    10075a8 cmpb $0x6d,(%rdi) / 10075ab jne 10075a0
    10075ad cmp max,count / 10075b0 je overflow / 10075b2 inc count / 10075b5 jmp

i.e. 5 uops and one taken branch per byte. Zig's arm unrolls 8x and counts
branchlessly (`cmpb` + `sete` + `add`, one back edge per 8 bytes). Splitting the
kernel (`range(16)` -> `range(0)`) shows the buffer build is 11 ms of the 67 ms
and the scan 89%.

Ruled out by measurement, not by argument:
- LLVM already CSEs the length/storage loads, removes the index normalisation and
  removes the `i += 1` overflow check; the emitted loop carries no bounds check.
- The extra trap call does NOT block unrolling by itself: a hand-written Zig loop
  with the same `if (count == max) overflowTrap();` still unrolls 8x and beats
  mylang 2x on an L1-resident version of the same scan (66 ms vs 132 ms over
  128 MiB, `.tmp/verify/l1scan*.zig`).
- The inner `if` is not the cost: `count += data[i]` and `for b in data:` variants
  measure the same (~103-107 ms) as the original.

So the remaining lever is the shape of the lowered loop in LLVM IR (slot-heavy:
every bytecode operand is an alloca store/load, and addresses round-trip through
`inttoptr`/`i64`), which keeps the unroller/vectorizer away. Next step to try:
dump the loop's IR (the pattern is in `.tmp/verify/ll/bs.ll`) and see whether
removing the accumulator's checked add from the per-byte path (e.g. by letting
the vectoriser see `count += (byte == needle)` with the overflow check outside)
buys the 9% needed. Nothing here is verified.

## list_records (1.39x, target 1.30x) -- diagnosed, not fixed

Profile (60 runs): 99.96% of samples in `entry_run`; 36% on the append loop's
32-byte store and **28% on one instruction**:

    1006cf0 mov 0x20(%r14),%r8          ; list storage
    1006cf4 vmovups (%rsi,%r8,1),%ymm0  ; load the 32-byte Row
    1006cfa vmovups %ymm0,-0x50(%rbp)   ; store it to the loop variable's slot

The body only reads `row.c` (offset 16), so the copy is the loop-body copy item 6
left unfinished. In the pre-LTO IR it is `call void @llvm.memmove.p0.p0.i64(...,
i64 32, ...)` into the loop variable's slot, and the samples on the store are the
store-to-load-forwarding stall of the following `row.c` load out of the same
32 bytes.

Next step to try: give the `for row in rows` loop variable the by-reference
treatment the emitter already has for read-only parameters (`Emitter.byReference`,
`addressLocals`) and match payloads (`payloadAddresses`), i.e. store the element
address into the loop variable's slot in `inlineIndexRead` instead of blitting the
element into it, guarded by the same conditions `elementFeedsStore` uses
(`!drop`, nonzero size, not a managed record) plus the condition that the local is
written nowhere else and that no call, allocation or mutation runs between the
store and the last read of it. The address is recomputed every iteration, so the
loop-carried copy disappears; the window bound is what keeps it sound.

## Environment

While this file was written the harness shell was down for every session:
`/tmp` is out of quota (`write` to `/tmp/dsh-probe.txt` fails with
`Unknown system error -122` = EDQUOT) and the bash tool reports
`UNKNOWN: unknown error, write` for every command, including `echo`. Freeing
`/tmp/dsh-spill-*` restores it. The committed change above predates the outage;
its full gate (`zig build test`, `test-qbe`, `test-qbe-build`, `fmt-check`,
`scripts/test_native_memory.py`, ASan, GC/arena filters) had NOT been run when the
shell died -- only `zig build` (guardian whole-tree, green) and the focused unit
test for the new spec tag.
