# Loop-parity targets: measured mechanisms, what landed, what blocks the rest

Every number here was measured on this worktree; the commands are named beside
them. The file started as a handoff written while the harness shell was down and
has been rewritten after both diagnoses were completed.

## Landed

`perf: keep a float's NaN canonicalisation off the finite path` — `float_loop`
2.76x -> 1.02x zig (independently re-measured at 1.00x). Mechanism and evidence
in the commit message; spec bullet `QBE-FLOAT-CANON-1`.

`perf: name a list element where it lives in a for-each loop` — the `for row in
rows` iteration local now holds the checked element address instead of a copy.
`.tmp/verify/ab.py --kernels list_records --rounds 21`: base 81.397 ms -> new
79.673 ms = 0.979x; the four-arm harness moved the o3-lto ratio 1.42x -> 1.39x.
Spec bullet `QBE-ELEMENT-ADDRESS-1`.

## What the two remaining kernels are actually blocked on

Both `bytes_scan` (1.42-1.46x) and `list_records` (1.29-1.39x) reduce to one
mechanism, and it is not a missing lowering:

**mylang's `int` arithmetic traps on overflow, so neither accumulator can be
vectorised, and Zig's ReleaseFast `+` is unchecked, so both of Zig's are.**

The experiment that isolates it: replace the accumulator with the prelude's
`wrapping_add` in a scratch copy of each kernel (same source, same output,
semantics changed only for the overflow case that never happens here):

    bytes_scan    80 ms  -> 63 ms   and the binary gains vpcmpeqb/vpaddq
    list_records  79 ms  -> 63 ms   and the binary gains 28 vpaddq

Both then run the loop as a 16- or 32-byte SIMD reduction. Against the same
`zig-fast` builds that is ~1.15x and ~1.13x, so:

- the *floor* for these kernels with mylang's checked arithmetic removed is about
  1.13-1.15x, comfortably inside the 1.3x target;
- the *current* form cannot get there, because a per-iteration overflow trap and
  a vector reduction are mutually exclusive under LLVM: it will not vectorise a
  reduction whose every step may branch to a trap.

Everything else the earlier diagnosis blamed is ruled out by measurement:

- `bytes_scan` reloads neither length nor storage in the loop and keeps no bounds
  check; the index normalisation and the `i += 1` check are gone from the emitted
  loop. It is 5 uops and one taken branch per byte (`inc ptr / dec count / je /
  cmpb $109,(ptr) / jne loop`), which is what a non-vectorisable scan costs.
- The inner `if` is not the cost: `count += data[i]` and `for b in data:`
  variants measure the same as the original.
- An extra trap call does not by itself stop LLVM unrolling: a hand-written Zig
  loop carrying the same overflow trap still unrolls 8x.
- `list_records`' residual is not the loop-body copy any more (that copy is
  gone); an L1-resident version of the same loop measures at parity with Zig, so
  the per-row instruction count is fine and the gap is the streaming sum plus the
  append phase, both with the same checked-arithmetic ceiling.

A fix would be a language/analysis feature, not a lowering change: prove the
accumulator cannot overflow (a loop-trip-count or value-range fact strong enough
for `count += 1` inside `range(len(data))`, and for `total += row.c` a bound on
every field — not available in general), or give programs an explicit unchecked
arithmetic escape hatch.

## Where the numbers come from

- four-arm interleaved medians:
  `ZIG_GLOBAL_CACHE_DIR=$PWD/.zig-cache-global python3 .tmp/verify/measure.py --kernels <k> --rounds 15`
- same-session base-vs-branch A/B: `.tmp/verify/ab.py --kernels list_records --rounds 21`
- instruction attribution: `.tmp/verify/selfprof.py --kernel <k> --runs 60` then
  `python3 .tmp/verify/hotinsn.py --kernel <k> --top 20`
- the wrapping experiment kernels: `.tmp/verify/bsW.my`, `.tmp/verify/lrW.my`
  (scratch copies, deliberately not part of the suite).

Note for whoever measures next: this machine's absolute times move by 30-50%
between runs when other lanes are building, so ratios only mean something when
the arms are interleaved in one process (`measure.py`, `ab.py`). Keep build
scratch out of `/tmp` — a lane filled the 16 GB tmpfs and every agent on the
machine lost the ability to spawn a process.
