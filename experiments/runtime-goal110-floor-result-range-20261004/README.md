# Positive floor-remainder result range (0311796e)

This candidate remains unintegrated. A repeat confirms a 9.96% LLVM small
equality gain and a 15.49% LLVM large search cost. Small equality remains
above the 1.10 target: the six-arm screen reports 3.65935 ns versus Rust's
2.92597 ns, or 1.25064. These are exploratory Debug-host measurements;
guests use the frozen ReleaseFast LLVM O3/full-LTO and QBE policies.

Source is 0311796e84e192e3ac1e4fd0bb9d5824b55be1e2 on integrated G4
6cf7bdce11bc205862bf75b9d9ce72e46caad0a2. Only successful final corrected
signed 64-bit floor remainders with a proven positive literal divisor are
annotated. A typed IL comment binds the immediately preceding add's exact
Instruction pointer. Translation emits unsigned result < divisor followed
by llvm.assume. Raw signed remainder, quotient, unknown/negative/zero
divisors, QBE policy, checked arithmetic, traps and accounting are unchanged.

`evidence.json` binds deterministic gzip archives and all helpers. Live
ELFs are retained in the immutable worktrees and bound by manifests and
receipts; ELF executables are not stored in Git. `commands.json.gz` holds
the exact structured argv used for all three timing phases. The source
diff, build receipts and final runtime asset hashes identify the compiler.
The final runner LLVM text ELF is hash-identical to the qualified diagnostic
ELF (892b089c25a316f80d8ad000d93125f59ffa871893d3d15526e7b05bb29319a0).

Qualification passed 18 focused units, all 88 Guardian checks, 2,763 native
before/after pairs (5,526 executions), 200 ordinary frozen text records,
516 fresh holdouts and 720 six-arm runner qualifications. Native policies
include actual LLVM/QBE, accounting, counting, sites and GC stress, plus
exact checked-overflow, division-by-zero, memory/step/frame refusals.
Native and paired checks retain full process streams; the normal six-arm
runner retains its usual parsed clock/checksum protocol, not full streams.
The default QBE emission JSON and matched native QBE ELFs are byte-identical.
LLVM-policy emission changes only range comments and the corresponding
11 implementation hashes in dependency metadata.

The six-arm screen ran 12 rows, five rounds and one warmup (360 samples),
followed by 288 matched G4/031 outcomes. An independent two-row repeat ran
15 rounds and three warmups (144 outcomes). CPU2, randomized paired order,
host/cgroup snapshots, UTC/session IDs and unchanged artifact validation
are retained. Repeat LLVM ratios and pointwise paired 95% intervals:

| Case | Before ns/op | After ns/op | Ratio | Interval |
|---|---:|---:|---:|---:|
| Equality, small | 3.8918172 | 3.5042810 | 0.900423 | [0.894395, 0.908677] |
| Search, large | 83.0508537 | 95.9126553 | 1.154867 | [1.146615, 1.162229] |

QBE repeat equality/search ratios are 0.999073/1.001366, with intervals
[0.998070,1.001165]/[0.995922,1.004257]. `analyze.py` replays all 432 paired
outcomes. It exhaustively resamples five paired rounds (3,125 draws) and
uses 20,000 deterministic draws for 15 rounds, seeded with
`case/profile/backend` through Python's Random. These pointwise intervals
exclude multiplicity and systematic/between-session host noise. Root's
independent bootstrap uses a different draw count and confirms both effects.

`code-proof.json.gz` binds actual linked instructions and pre-LTO IR.
The equality checksum remainder shrinks from 17 arithmetic instructions
to 11 (20 to 14 including loop bookkeeping). The search checksum retains
the signed correction. `search-proof.json.gz` and `search-code.py` establish
that its 102-instruction/400-byte caller loop and scanner, index-walk and
large-octet equality helpers are instruction-identical after rebasing
branch/call targets and verifying exact constant bytes from ELF segments.
The caller moves -32 bytes, modulo64 16 to48; scanner stays 64-byte aligned.
Index-walk moves -112 bytes, modulo64 48 to0, including its internal loops.
These are placement observations; no timing counterfactual establishes cause.

Failed attempts are retained, rather than discarded: the first focused
test expected signed textual -7 instead of LLVM's unsigned bit-pattern
format; the initial Guardian nesting-depth check rejected depth6/cap5;
an extracted early-return helper passed unchanged rules. Native harness
attempts expected the wrong startup-memory diagnostic, then omitted the
sites policy's zero-event line. Only harness assertions were corrected.
Emission checks first treated JSON as raw IL, then overlooked expected
implementation-hash changes. A first `inspect.py` helper shadowed Python's
stdlib inspect module and was renamed. The saved unit log's trailing
"failed command" text accompanies Guardian PASS and process exit0.
No full repository gate or official ReleaseFast compiler host is claimed.

Diagnostic loop alignment is a separate prospective experiment. LLVM's
[llvm.loop.align metadata](https://llvm.org/docs/LangRef.html#llvm-loop-align-metadata)
provides a general loop alignment request; Clang's
[code_align attribute](https://clang.llvm.org/docs/AttributeReference.html#clang-code-align)
maps a loop statement to this metadata. No alignment source change,
counterfactual build, or extra timing is part of this archive.
