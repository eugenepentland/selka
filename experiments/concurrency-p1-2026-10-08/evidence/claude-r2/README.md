# Revision 2 probes (Claude, 2026-10-08)

Pinned toolchain `zig 0.17.0-dev.1683+5ceec001b`.

## Slow-path form

`gen.py VARIANT > VARIANT.ll` writes one function with 12 retain sites. Five
values stay live across every site. Each file was compiled with
`zig cc -O2 -c VARIANT.ll`; `work`'s size is from `nm -S`.

| variant | emitted form | `work` bytes | push/pop |
|---|---|---:|---:|
| D | before P1: `icmp eq -1`, plain increment, no call | 511 | — |
| A | P1-1 as built: plain test; slow block tests `-1`, then a C-convention `call @myl_core_retain_slow` | 1317 | 13 |
| B | plain test; slow block is one `call preserve_mostcc`; the helper handles immortal and shared | 814 | 2 |
| C | as B, but the immortal test stays inline in the slow block | 934 | 2 |

B removes 62% of P1-1's growth over D, and C removes 47%. Most of the difference
is the C calling convention: values live across the cold call need
callee-saved registers, which means pushes, pops and moves. `preserve_mostcc` avoids
that, as the ERROR-TRACE-6 helpers already do.

These are synthetic numbers. P1-1's `json::read_value` grew from 7,068 to 8,160
bytes, with 30 slow-call sites.

## Layout perturbation

`zig cc -mllvm -align-all-functions=K` (K = 4, 5, 6) changes function addresses
with the pinned toolchain. `-Wl,--shuffle-sections` and
`-Wl,--symbol-ordering-file` are rejected by the zig driver ("unsupported
linker arg").
