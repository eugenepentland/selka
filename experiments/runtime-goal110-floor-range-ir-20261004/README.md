# Isolated positive floor-remainder result range

This experiment changes no compiler, runtime or benchmark source. It tests
whether exposing the final range of a successful signed floor remainder
helps the installed LLVM optimizer recover a checksum recurrence's range.
It is separate from bounded-equality candidate 3dcbe723 and the guarded
dividend loop experiment. There are no performance timings or adoption claims.

The installed tool is Zig 0.17.0-dev.1683+5ceec001b, bundled Clang 22.1.8;
the Zig executable SHA256 is
1d314883fd8cf4490c1c29dd73ad8b64e319a8a53c4d9087d1135b52977df37f.
The shared helper was linked with `zig cc INPUT.ll -O3 -flto -shared -fPIC`,
through the build-slot wrapper and private disk caches/TMPDIR, without ISA
overrides. As in the project's driver policy, cc1 emits O2 bitcode and the
full-LTO link uses O3. The separate optimized-IR output is a cc1 O2
diagnostic, not a dump of the final LTO pass. The actual linked ELF bodies
are retained for all 56 exported functions. The valid compiler probe and
structured commands retain exact target/feature flags.

`-x ir` is rejected by Zig's public cc driver; the failed attempt is retained.
Letting the driver infer LLVM IR from the `.ll` extension works. An initial
unwrapped diagnostic compile also succeeded; the accepted helper was then
rebuilt through build-slot with private caches and rechecked afterward.
An initial relative-path `-###` probe failed after printing its cc1 line;
the project-shaped absolute-path compile probe subsequently succeeded.

Four variants use the same remainder and checked-add operations:

- baseline: the frontend's nonzero/sign-difference/mask/add floor correction;
- assume: baseline followed by `icmp ult i64 FINAL_RESULT, D` and `llvm.assume`;
- select: direct selection between the raw remainder and its shifted value;
- select_assume: the select form followed by the same final-result assumption.

The select's shifted add has no `nsw` or `nuw`: an unselected positive
remainder plus a large divisor can wrap. No assumption constrains the raw
signed remainder or the incoming dividend. Scalar tests use positive literal
divisors 1, 2, 3, 1000000007 and I64MAX. Loop tests use 3, 1000000007 and
I64MAX with a zero-initialized boolean checksum, an unknown signed seed,
and ongoing signed updates. Checked addition precedes floor remainder;
overflow retains a distinct status and returns before the assumption.

All 56 functions passed 27,452 individually retained Python integer-oracle
outcomes, including 1,400 overflow statuses. Tests include MIN/MAX, negative
dividends and seeds, divisor/multiple boundaries, empty loops and deterministic
random values/vectors. This is finite validation, not a proof of every LLVM
optimization or a replay of MyLang's runtime trap/accounting contracts.

For D=1000000007, the zero-initialized boolean loop has these actual linked
body metrics (LLVM unrolled each main loop four times):

| Variant | Bytes | Instructions | Optimized remainder |
| --- | ---: | ---: | --- |
| baseline | 457 | 127 | signed, retains negative correction |
| assume | 319 | 90 | unsigned, correction eliminated |
| select | 463 | 127 | signed, retains negative correction |
| select_assume | 319 | 90 | unsigned, correction eliminated |

The assumption exposes the checksum phi's range, yielding unsigned remainder
and `add nuw nsw` in the diagnostic IR. It removes the floor sign correction
and simplifies signed constant-divisor arithmetic in the linked body. The
constant-divisor multiply sequence remains; this does not establish a
compare/subtract recurrence. No loop clone or runtime range guard was added
to the input IR. Direct-select alone did not recover this range and makes
the signed controls slightly larger, so it is not the proposed production
change.

For D=1000000007, baseline and assume scalar bodies are identically normalized
(59 bytes/15 instructions), as are unknown-seed loops (113/31) and ongoing
signed-update loops (107/29). Both negative-control loops keep signed
remainder, floor correction and their `jo` overflow branch. Thus the
assumption does not falsely convert a possibly negative dividend to unsigned
remainder. Address normalization is only for body comparison; no layout or
guest performance attribution follows from it.

The [LLVM assume contract](https://llvm.org/docs/LangRef.html#llvm-assume-intrinsic)
permits a condition that is true whenever its call is reached; false conditions
cause undefined behavior. No machine code is generated for the intrinsic.
The [range metadata contract](https://llvm.org/docs/LangRef.html#range-metadata)
limits that metadata to load/call/invoke outputs, so attaching it directly
to an arithmetic or select instruction is not the proposed interface.

For signed i64 and a positive literal D<=I64MAX, `r = srem(a,D)` has
`-D < r < D`. When r<0, r+D is in [0,D); otherwise r already is. The final
masked correction computes exactly that result and cannot overflow. A positive
divisor excludes division by zero and MIN/-1; current guards must still be
emitted unchanged. The assumption belongs after the successful final correction,
never before a checked-add failure or on an exceptional path. This proof
requires no assumption that the dividend itself is nonnegative.

The proposed interface is in PROPOSAL.md. Production implementation requires
coordinator review and a fresh source/worktree. Generated IR, actual body
assembly, optimized IR, full per-call outcomes, logs, tool identities and
commands are bound by evidence.json; the helper ELF stays private and immutable.
