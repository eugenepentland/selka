# Revision 1 probes (Claude, 2026-10-08)

Pinned toolchain `zig 0.17.0-dev.1683+5ceec001b`.

## TSan: `unordered` count read

`count-reader-unordered.ll` is P1-0's `count-reader-atomic.ll` with `monotonic`
replaced by `unordered`. It was linked with P1-0's `tools/count-reader.c`:

    zig cc -O1 -g -fsanitize=thread -pthread count-reader.c count-reader-unordered.ll -o unordered

and run 100 times with `TSAN_OPTIONS=halt_on_error=1:exitcode=66`.

**Result:** 0 failures and 0 TSan reports. Every run printed `unique=0 count=80000002`.

## Optimisation: plain, `unordered` and `monotonic` count reads in a loop

`hoist-<order>.ll` is a loop whose body tests one block's count, with TBAA that
separates the count from the stored output. It was compiled with:

    zig cc -O2 -S -emit-llvm hoist-<order>.ll -o hoist-<order>.opt.ll

**Results:**
- **plain:** the load is hoisted to the loop's entry, and the loop vectorises (`<8 x i32>` stores).
- **unordered:** the same as plain: hoisted and vectorised.
- **monotonic:** the load stays in the loop, unrolled ×8 with eight loads, and the loop does not vectorise.
