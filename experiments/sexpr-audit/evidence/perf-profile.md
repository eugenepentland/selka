# Hardware-counter profile (perf)

`perf` was blocked by `kernel.perf_event_paranoid = 4`; the operator raised it to `1`
with `sudo /usr/sbin/sysctl kernel.perf_event_paranoid=1`. Every number below is
`taskset -c 6 perf stat …` on the frozen stage-`s1` candidates (lever 4 applied) and
the Zig driver `/tmp/zb-out/bin/zig-bench` over `/tmp/sexpr-bench/input.sexp`
(927,415 bytes).

## The gap is instruction count, not efficiency

`census` (parse + walk the whole file):

| | mylang | Zig | ratio |
| --- | ---: | ---: | ---: |
| instructions | 2,248,517,817 | 22,944,184 | **98×** |
| cycles | 934,755,133 | 11,305,836 | 83× |
| branches | 320,383,061 | 5,119,210 | 63× |
| branch misses | 145,742 | 20,007 | 7× |
| cache misses | 646,886 | 39,296 | 16× |
| **IPC** | **2.41** | **2.03** | — |

mylang retires 2.4 instructions per cycle — *better* than Zig's 2.0 — while retiring
98× as many instructions for identical work: 2,424 machine instructions per input
byte against Zig's 24.7. Branch misses and cache misses are 1–2 orders of magnitude
below the instruction ratio, so this is not a misprediction or locality problem. It
is pure code expansion.

Phase by phase (instructions, mylang vs Zig):

| driver | mylang | Zig | ratio | mylang instr/byte | Zig instr/byte |
| --- | ---: | ---: | ---: | ---: | ---: |
| `loop` (empty while) | 124,707,076 | 2,046,815 | 61× | 134.5 | 2.2 |
| `scan` (byte compare) | 917,571,151 | 7,968,012 | 115× | 989.4 | 8.6 |
| `tokens` (read+tokenize) | 2,141,548,519 | 18,335,012 | 117× | 2,309 | 19.8 |
| `parse` | 2,198,398,198 | — | — | 2,370 | — |

## Where a single scanned byte goes

`e_scan.my`'s loop is ~8 bytecode operations. Emitting its unit and running the
vendored QBE over it (`mylang emit-qbe`, then `zig-out/bin/qbe`) shows the hot loop is
**649 machine instructions per byte**:

| | loop body | `movq` | `callq` |
| --- | ---: | ---: | ---: |
| shipped | 649 | 457 | 33 |
| with the step check and `%position` store deleted from the IL | 380 | 282 | 33 |

Two independent costs are visible in the assembly:

1. **Per-instruction scaffolding.** Every bytecode instruction emits `storel <pc>,
   %position` plus a six-instruction step-budget check
   (`loadl %ctx` / `loadl %maxsteps` / `ceql` / `jnz` / `add` / `storel`). Deleting
   those lines from the IL alone drops the loop from 649 to 380 instructions
   (1.7×). This is lever 1 + lever 2, and it is the largest single identified win so
   far.
2. **The operand stack is address-taken, so it can never reach a register.** The
   function holds a managed `bytes`, so `has_roots` is true and every op in
   `allocates()` becomes a GC safepoint. `roots(stack)` passes `l %s{i}` — the
   *address* of the operand slot — to `myl_native_root_push`. An alloc whose address
   escapes cannot be promoted by QBE, so every push/pop round-trips through memory:
   282 of the 380 remaining instructions are `movq`. One safepoint expands to a run
   of `myl_native_root_push` calls (26 in this loop body) each with ~6 argument
   moves.

So the ranking of remaining work is: step scaffolding (1.7×) > address-taken operand
slots / over-broad safepoints > call prologue. Note that this is *why* lever 4 alone
measured 1.00×: removing the `@i` labels does not help while the step check's own
`jnz` label still ends every block, and it cannot help the operand slots because they
are address-taken regardless of block shape.

## Reproduce

```sh
taskset -c 6 perf stat -r 3 -e cycles,instructions,branches,branch-misses,cache-misses \
  -- /tmp/sexpr-stages/s1/census /tmp/sexpr-bench/input.sexp
taskset -c 6 perf stat -e instructions,cycles,branches -- /tmp/zb-out/bin/zig-bench /tmp/sexpr-bench/input.sexp
# IL and generated assembly for one driver
zig-out/bin/mylang emit-qbe /tmp/il/scan.my | python3 -c 'import json,sys; print(json.load(sys.stdin)["functions"][0]["il"])' > /tmp/il/scan.ssa
zig-out/bin/qbe -o /tmp/il/scan.s /tmp/il/scan.ssa
```
