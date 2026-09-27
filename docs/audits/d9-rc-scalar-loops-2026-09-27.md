# RC numeric loops without ownership actions

Source `280ef314d9c7eceae23b98be20d38e0b467604fe` restores the existing guarded
numeric loop version when a bounded proof shows that the entire RC loop touches
only built-in integers, booleans and unit values. The previous RC admission
required a proved collection ownership entry even for pure arithmetic, leaving
the QBE integer-loop benchmark on its original checked path.

The new admission refuses managed operands, caller-backed locals, inline origins,
captures, COW operations and implicit release edges. It bounds code, loop body,
release-edge inspection and total stack-state work. Unknown operations decline.
Existing range guards, checked fallback, emitted allocating-call veto and
step-counted original path remain in force. The proof changes no arithmetic rule
and introduces no public ABI or runtime change.

The exact historical `parity/micro/intloop` program still runs 30,000,000
iterations. CPU 3 measurements interleave immutable accepted GC, the joined
`636524b8` RC compiler and this RC candidate, with three unscaled instruction
samples each. Every counter ran 100% of its enabled time; all outputs match.

| Backend | GC median | Previous RC median | Candidate RC median | Candidate / previous |
| --- | ---: | ---: | ---: | ---: |
| QBE | 1,260,199,595 | 2,340,227,364 | 1,260,227,389 | 0.538506× |
| LLVM O3/full LTO | 650,201,875 | 650,227,709 | 650,227,726 | 1.000000× |

The candidate/GC ratios are 1.000022× QBE and 1.000040× LLVM. Separate counted
builds have identical all-zero ownership/allocation counters before and after.
The unchanged LLVM result is expected: its optimizer already removed the numeric
overhead. This is one workload's instruction evidence, not complete Stage 4
performance or RSS acceptance.

Validation includes 153 selected RC tests and all 32 paired actual-backend
outcomes: successful numeric/ownership/arena assertions, overflow, step-limit and
frame-limit traps, each with old/new compilers and GC stress/counted RC. Paired
stderr traces and every ownership counter match exactly; all RC runs balance.
The structural regression verifies original and fast paths and rejects managed
reads, callbacks and step-counted fast versions. Formatting and whole-tree
Guardian88 pass without a waiver. A fresh combined full gate follows integration.

The candidate compiler is Debug, SHA256
`d945395b87a630783f36e41d27aad37cd9727635db778e3435a93e5c9af8a879`.
All builds used the shared slot wrapper, private caches and disk-backed temporary
storage. The [archive](../../experiments/d9-rc-scalar-loops-20260927/README.md)
preserves source identity, complete commands, raw counters, exact outputs and
trap controls. Its independent verifier passes. Arenas and the ordinary GC
default remain unchanged.
