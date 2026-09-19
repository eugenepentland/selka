# Runtime performance audit and implementation plan — 2026-09-18

Why a mylang native executable runs 26–37× slower than the equivalent Zig on the
sexpr workload, measured mechanism by mechanism, and a six-wave plan that takes
the hot byte loop from **90× Zig's instruction count to about 3×** using the
existing QBE backend. Every number here was measured on this checkout with
`perf stat`, pinned to one core, on the 927,415-byte EDA input
(`/tmp/sexpr-bench/input.sexp`); the drivers are in `experiments/sexpr-audit/`.

## 0. Landed so far

**Status after the second batch and the lever search (rounds 1-24).** Census is
**7.5x wall / 8.4x cycles / 11.0x instructions** against the frozen Zig driver:
17.228 ms vs 2.310 ms, 73-74 M vs 8.7 M cycles, 244.8 M vs 22.9 M instructions.
Progress this session: census 23.15 ms / 10.1x -> 17.23 ms / 7.5x, and 350.8 M ->
244.8 M instructions (-30 %).

Every item in the original six-wave plan has now been landed or measured and
disproved. Landed and measured: Wave 1 safepoints, Wave 2 index/cast/checked-int
lowerings, scalar const folding, interprocedural root elision, the frame-record
half of Wave 4, QBE promotion via slot hoisting, static `str`/`bytes` literals,
single-pass UTF-8, both inliner milestones (-7.2 %), `QBE-FLOAT-ENV-1`,
GC pacing, branchless signed-index normalisation (-2.1 %) and the
constant-operand overflow test (-3.1 %).

Disproved by measurement, each recorded in its own section below: the frame-counter
fold (breaks exact `--max-frames`), per-block step accounting (no step code exists
in a plain build), `-fPIC` on guest/runtime objects (exactly zero), QBE
optimisation flags (none exist), bounds checks as the explanation for the gap
(2.8 %), and a cheaper frame record (the same stores, moved). The frame protocol
decomposes into 5.3 % bound checks and ~6.8 % record bookkeeping, both required for
exact frame budgets and exact trap traces, and `advance` can trap, so its ~11 % of
cycles cannot be recovered without giving one of those up.

Landed: Wave 1 (precise safepoints), Wave 2's index and integer-cast lowerings,
scalar `const` folding, interprocedural root elision for calls to functions that
cannot allocate, the frame-record half of Wave 4, and the slot-declaration
placement that lets QBE's promotion pass actually run. Gated by
`QBE-SAFEPOINT-1`, `QBE-PURECALL-1`, `QBE-FRAMES-1`, `QBE-PROMOTE-1` and
`QBE-PROLOGUE-1`.

The last change was the largest of the four rounds. Slot `alloc8` declarations
were emitted after the frame protocol's labels, and QBE's `promote` pass scans
only the entry block, so every operand push and pop was a real stack access: the
empty loop cost 41 instructions per iteration for two checked adds. Declaring
the scalar local and operand slots before the protocol's first label turns them
into SSA temporaries. Per-pc aggregate scratch stays after the protocol because a
zero-length aggregate otherwise folded to a load from null; the existing
const-length backlog test caught that.

| driver | before (audit §1) | after W1+W2 | now | cycles now |
| --- | ---: | ---: | ---: | ---: |
| `e_scan` instructions | 714.9 M | 86.7 M | **59.6 M** | 13.0 M (÷14.5) |
| `i_index` instructions | 382.8 M | 69.9 M | **45.7 M** | 12.5 M |
| `b_tokens` instructions | 1,469.1 M | 883.1 M | **303.8 M** | 77.7 M (÷4.6) |
| `c_parse` instructions | 1,514.3 M | 919.9 M | **333.4 M** | 88.0 M (÷4.3) |
| `f_calls` instructions | 370.3 M | 370.3 M | **70.0 M** | 14.2 M (÷4.9) |
| `h_loop` instructions | 40.2 M | 40.2 M | 27.2 M | 7.7 M (÷1.9) |
| census (end-to-end) | — | 942.9 M | **252.6 M** | 73.4 M |

The second batch (static `str`/`bytes` literals, single-pass UTF-8, the bytecode
inliner's two milestones, `QBE-FLOAT-ENV-1`, GC pacing and branchless signed-index
normalisation) took census from 350.8 M to **252.6 M instructions (−28 %)** and
92.6 M to **73.4 M cycles (−21 %)**. Against the frozen Zig driver on the same
core and input, interleaved: Zig **22.9 M instructions / 8.7 M cycles**, so the
honest end-to-end ratio is **11.0× instructions, 8.4× cycles**, and **7.7× wall
clock**: `run_audit.py --runs 15` on the quiet machine gives census 17.574 ms
against Zig's 2.290 ms, of which mylang spends 1.1 ms and Zig 0.8 ms before guest
code runs. The wall figure decomposes as tokenize 12.624 ms vs 0.722 ms (17.5×),
parse 2.538 ms vs 0.618 ms (4.1×) and walk 0.930 ms vs 0.026 ms (35.8×, but only
0.93 ms absolute); the render path is 27.428 ms vs 3.573 ms (7.7×, 10.8 ms of it
beyond the shared read).

That is not 5×, and the gap is instruction count rather than efficiency: mylang's
IPC is *higher* than Zig's (3.4 vs 2.6) and the profile is not memory-bound (25 K
LLC misses and 290 K L1 misses for the whole census), so cache and stall effects
are an order of magnitude below the instruction ratio. Attributing *instructions*
per function (`perf record -e instructions`) gives `advance` 20.2 %, `tokenize`
19.7 %, `read_string` 17.7 %, `myl_native_text_from_utf8_checked` 5.0 %,
`memmove` 2.7 %, `is_atom_continue` 2.5 %, `parse_list`/`parse_node` 4.2 % and
`heap_alloc_at` 2.1 %.

Two counterfactual builds size the largest remaining levers. Both change what a
trace would print, so they measure an upper bound rather than a landing:

| counterfactual (census) | instructions | cycles |
| --- | ---: | ---: |
| integrated tree | 252.6 M | 73.4 M |
| every per-pc `%position` store deleted (Wave 3) | 244.8 M (−3.1 %) | 72.9 M (−2.3 %) |
| the whole frame record deleted (Wave 4) | 214.3 M (−15.2 %) | 67.5 M (−7.6 %) |

The frame protocol is therefore the largest remaining item, and it is worth ~8 %
of cycles rather than 15 %: those instructions are cheap stack and ALU work that
overlaps other work at IPC 3.4. A shadow-stack or lazily-reconstructed frame
design recovers perhaps half of it while keeping `--max-frames` and the trace
byte-identical. Adding the other identified levers — eliding the position store on
instructions that cannot trap, specialising the inlined overflow check for a
constant operand (`x + 1` currently spends seven instructions on the check where
`cmp $INT64_MAX` needs two), and making text creation one allocation instead of
two — is worth roughly another 10 %, which lands near **7× cycles**. That is where
this architecture plateaus — but **not** for the reason this paragraph first gave.
That version said the residual was the cost of the checks Zig does not perform.
Measured, it is not: disabling the per-read bounds check in `inlineIndexRead`
entirely (byte-identical output) takes census from 244.8 M to **238.0 M
instructions, only −2.8 %**. The checks are not the gap.

What the counterfactuals do account for is small and additive to roughly a fifth:
frame protocol 15.2 %, bounds checks 2.8 %, position stores 3.1 %. The other ~80 %
is the plain volume of emitted code in the tokenizer's per-byte path — `advance`
alone runs ~33 instructions per call where Zig's equivalent is about six, and after
the frame record (~19) and the three checked increments (~9) are subtracted, almost
none of it is a check. It is loads and stores of the lexer's fields through a heap
object, recomputed lengths, and call traffic that QBE does not keep in registers.
Closing that is a code-quality problem spread across the whole lowering, not a
lever that can be pulled in one place.

**Landed: constant-operand overflow checks (`QBE-INTOPS-2`).** The inlined
overflow test for a 64-bit signed add or sub now specialises when the right
operand is a literal: with one operand fixed, exactly one value of the other can
carry the result out of range, so the general three-instruction sign test
collapses to one `csgtl`/`csltl` against `max − c` (or `min ± c` on the other
side). `x + 1` went from nine instructions of check to three. The cold path is
still the shared `overflowTrap`, so the sticky trap, its operand detail and the
result bits are unchanged, and a left-constant `C + x` falls back to the general
test unchanged.

Provenance is proven, not guessed. `pushedLiteral(pc)` accepts the operand only
when the *linear predecessor* is the literal push, the operand-stack height grows
by exactly one across the pair, and `pc` is not named by any `jump`,
`jump_if_false` or `try_result` — so a pc that anything can jump to directly is
never claimed. The literal itself arrives as `.push_i64` (plain i64) or
`.push_integer` (only when its declared type is 64-bit signed).

Getting here cost two failed rounds, and the lesson is recorded because the trap
was invisible: the first implementation was **silently dead** — it switched on
`.push_integer`, but `x + 1` lowers to `LOAD_LOCAL`, `PUSH_I64 1`, add. The
diagnostics that followed were worse than useless: the "relaxed" height condition
I substituted still excluded both stack models, so its null result proved
nothing, and a sentinel build was run against a tree the helper had already been
reverted from. Dumping the actual instruction stream (`Compilation.dump`, see
`src/domain_equality_test.zig` for the pattern) identified the opcode in one
step. Read the lowering before instrumenting it.

Measured on census: 252.5 M → **244.8 M instructions (−3.1 %)**, cycles flat
within noise (−3.1 % of instructions did not reach the critical path, the same
pattern as the inliner's −7.2 %), with census and render output byte-identical to
the Zig driver and the four hand-written overflow cases byte-identical.

Reproduce:

```sh
cd experiments/sexpr-audit
for d in h_loop e_scan b_tokens c_parse i_index f_calls; do
  ../../zig-out/bin/mylang build $d.my -o /tmp/now_$d --mode ReleaseFast
done
taskset -c 6 perf stat -e instructions,cycles -- /tmp/now_e_scan /tmp/sexpr-bench/input.sexp
```

(Note: `compare_impls.py` in the same directory has since been repurposed by
another change and no longer reports the Zig/mylang columns; the table above is
from the `perf stat` ladder.)

### Retracted: per-block step-budget accounting

Round 18 claimed the step check was emitted per bytecode instruction and cost
~19 % of the program. That was wrong, and the measurement says so plainly: with
`step()` hacked to emit nothing, census measured **244.7 M / 244.9 M instructions**
against the current **244.7 M / 244.8 M** — zero, within noise, with byte-identical
output. The step sequence is not in this binary at all.

The reason is already-landed `QBE-STEP-ACCOUNTING-1`: `main.zig:507` (the `build`
path) passes `parsed.saw_steps`, so step checks are emitted only when the build
itself was given a step ceiling. A plain `mylang build -o prog` carries none, which
is why the census profile shows no trace of them. The estimate had been anchored on
the position-store counterfactual and on `main.zig:423`, which is a different call
site (`run`), and I did not check which site the benchmark used.

Net: there is no step-budget lever for this workload. Per-instruction step
accounting is only paid by builds that asked for a ceiling.

### The highest-value sound win left: bounds-check elimination unlocks frame elision

Fresh instruction profile of the current tree (`perf record -e instructions`):

| share | function |
|---:|---|
| 21.44 % | `sexpr.tokenizer::advance` |
| 16.69 % | `sexpr.tokenizer::read_string` |
| 14.40 % | `sexpr.tokenizer::tokenize` |
| 4.26 % | `myl_native_text_from_utf8_checked` |
| 3.27 % / 2.45 % | `parser::parse_node` / `parse_list` |
| 2.95 % | `tokenizer::is_atom_continue` |

The tokenizer is still 57 % of the program, and `advance` alone is the largest
function at ~35 instructions per call. Roughly 19 of those are its frame record and
~6 are the bounds check on `lx.src[lx.pos]` — a check that is **already implied by
the guard on the line above it**:

```
def advance(lx):
    if lx.pos < len(lx.src):        # guard
        if lx.src[lx.pos] == 10:    # index provably in range
```

So a proven-range elimination pass would do two things at once, and the second is
the large one:

1. drop the redundant bounds check (~2.8 % of the program across all inline reads);
2. make `advance` **trap-free**, at which point its frame record is no longer
   needed — and the frame protocol is 15.2 % of instructions overall, of which
   `advance`'s share (19 of ~35 instructions in the hottest function) is the
   biggest single piece.

Together that is the ~8–11 % scale, soundly, with every check kept for cases the
compiler cannot prove. The cost is a path-sensitive range analysis over local slots
(after a `jump_if_false` guard, the taken branch knows `pos < len`), wired into the
lowerer so `emitIndex` can skip `requireIndexBounds` and the frame emitter can skip
the record. That is a real pass, not a peephole, which is why it has not been
attempted yet — but it is the first lever found whose size is worth the work.

**Counterfactual confirms it, and it is the largest single-function effect
measured in this audit.** Skipping the frame record and the bounds check for
`advance` *only* (and nothing else), census goes from 244.8 M to **213.3 M
instructions (−12.9 %)** and 74.2 M to **65.6 M cycles (−11.5 %)**, with
byte-identical output. One function out of the whole program. That is well above
the 8–11 % estimate, and it makes the range-analysis pass the clear next piece of
work: prove `pos < len(src)` from the guard, drop the bounds check, observe that
`advance` can then no longer trap, and drop its frame record too.

**Corrected again: the win is the frame record, not the bounds check.** Splitting
the counterfactual (round 23), with the bounds check left in place and *only*
`advance`'s frame record skipped: census 244.9 M → 215.2 M instructions and 73.8 M
→ 65.4 M cycles, i.e. **−12.1 % instructions and −11.4 % cycles**. The bounds check
is worth barely 0.8 % of that. So the range-analysis pass sketched above is *not*
what unlocks this — the target is the frame protocol itself, one 32-byte record per
call, and it is worth ~11 % of cycles on its own.

Which sharpens the real problem instead of solving it: `advance` can trap (its
`col` and `line` increments have no provable bound), so exact trace attribution
demands a record per call. Removing it for good needs either (a) a proven
trap-free `advance` — which the guard gives for `pos` but not for `col`/`line` — or
(b) a cheaper record. A redesign that has the *caller* push `{prev, callee,
call_position}` and the callee hold only one global trap position would drop the
per-call `alloc8`, the entry position initialisation and some stores: perhaps ten
of the ~19 instructions the protocol spends rather than all nineteen. That is the
next thing to measure, not to assume.

**Measured (round 24): the protocol splits, and both halves are needed.** Skipping
only the two bound checks for `advance` — keeping the record, the link and the
counter — takes census 244.9 M → **231.9 M instructions (−5.3 %)**. So of the
12.1 % that `advance`'s frame costs, 5.3 % is the `--max-frames`/stack-floor bound
checks and ~6.8 % is the record bookkeeping (32-byte `alloc8`, four stores, the
link and the counter). Neither half is removable while the guarantees hold:

- The bound checks must run once per call to keep `--max-frames` exact, which
  `integration.zig:1282-1283` pins in both directions on one program.
- The bookkeeping is what makes the trace exact. The caller-side redesign sketched
  above moves the same stores rather than deleting them — the caller would push
  `{prev, callee, call_position}` and the callee would still need its own position
  somewhere — so it does not recover the 6.8 %. The only genuinely droppable
  instruction found is the per-call `storel 0, %position` initialisation.

So the ~11 % of cycles that `advance`'s frame costs is the price of exact frame
budgets and exact trap traces for a function that can trap. Recovering it needs
`advance` to become trap-free, which its `col`/`line` increments prevent, or a
different trace mechanism that gives up per-call attribution. That is the plateau,
stated with a measured decomposition rather than an argument.

### Next lever: fold the frame counter into the frame floor

Reading the runtime settles how to remove the depth counter without losing
anything observable:

- The emitter's inline protocol uses `ctx->frames` (offset 8) for exactly two
  things: comparing it to `ctx->frame_limit` (offset 56) for `R_FRAME_LIMIT`, and
  incrementing/decrementing it. The *trace* does not use it — `fail()` walks
  `active_frame->prev` and computes logical depth from that walk plus the inline
  tables (`qbe_runtime.c:182-214`), so reporting is independent of the counter.
- A frame-limit failure and an execution-stack-floor failure already call the
  same `myl_qbe_fail_frame` and produce the identical text
  (`R_FRAME_LIMIT` → "call-depth budget exhausted; raise it with --max-frames=N",
  `qbe_runtime.c:46`). Folding the two bounds into one address test therefore
  cannot change a trap code, a message, or a source location — it can only change
  *which* of two indistinguishable bounds fired.

So: have the entry prologue fold `sp − frame_limit × 32` into `ctx->frame_floor`
(offset 64) alongside the execution-stack bound, take the stricter of the two,
and drop the counter load/compare/increment from `enterFrame` and the
load/decrement/store from `leaveFrame`. That removes six or seven of the roughly
twenty instructions the protocol spends per call — about 4.5 % of program
instructions and 2.3 % of cycles on the counterfactual split.

Cost and hazards, so the next round can start here: the writer of
`frame_floor` is `src/qbe_stack.c:47` (`ctx->frame_floor = bottom + 65536`, the
64 KiB headroom above the guard page), *not* the entry prologue — and that file
already has `ctx` in hand, so the ceiling composes there from `ctx->frame_limit`
and the emitter needs no new state; `MYL_QBE_UNBOUNDED` must not be multiplied
into an address; the C-model `myl_qbe_enter_at_sized`/`leave` helpers
(`qbe_runtime.c:540-558`) keep their own `frame_data`/`scratch_frame` bookkeeping
and must stay consistent; and the `QBE-FRAMES-1`/`QBE-PROLOGUE-1` IL assertions
plus the two CLI frame-budget tests pin the current shape and need updating in the
same change.

**Falsified before implementing (round 17).** The fold above does not preserve
`--max-frames`, and the tests say so exactly: `integration.zig:1282-1283` require
`--max-frames=2` to *succeed* returning 7 while `--max-frames=1` traps
`R_FRAME_LIMIT` on the same program. A frame record is a fixed 32 bytes, but a
frame's own locals, aggregate scratch and spilled operands live on the same stack,
so a record's address is not a function of depth — with `--max-frames=N` for
non-trivial N the address bound fires early and reports the wrong depth. The
counter cannot be replaced by an address test.

What survives is small: the limit check is already two loads plus `ceql`/`jnz`, the
floor check is one `cultl`/`jnz`, and both are live guards (the floor is set in
`qbe_stack.c:47`, the counter is compared against `frame_limit` at ctx+56). The
only trims left are cosmetic — merging the two bound loads, or removing the
`storel 0` position initialisation if it is provably unreachable before the first
per-pc store. That is worth a fraction of a percent, not the 4.5 % the fold
promised, and it means the frame protocol is essentially irreducible while frame
counting stays exact.

### Next round: shrink the class field write, then let the inliner take `advance`

Direction from review, verified against the tree before implementing.

**The inliner is not the problem; the callee is too fat to qualify.** `advance` is 76
bytecode instructions against the inliner's 48-instruction cap (`bytecode_inline.zig`),
so it stays a call at every one of its sites and every call pays the ~19-instruction
frame record. Shrinking `advance` under the cap lets the existing inliner remove the
call, the frame record and the argument marshalling together.

**It is fat because of the field-assignment desugaring.** `sema.zig:1495-1531` lowers
`b.n = b.n + 1` as `b = update(b, n: <rhs>)`:

- `fieldDestination` (sema.zig:1591-1600) allocates a `saved` local and initialises it
  from the base — a copy used only to read the base back;
- the RHS is evaluated into an `assigned` local (1511-1512);
- `destination.refresh` (`saved = b` again) is appended *after* the RHS (1516);
- the update chain is built as a value (1518-1525) and finally assigned back to the
  destination (1526-1529).

**The write-back is provably a no-op for a class.** `qbe_aggregate.zig:33-50` lowers
`update_record` with `cell = isManagedRecord()` and sets `pointer = source` for managed
records — it mutates in place, skips the blit, and stores back the *same* pointer. So
for a class the final assign cannot change the local, and `saved`/`refresh` exist only
to survive the RHS reassigning the base.

**The change.** In the name-rooted destination case, when the destination type is a
managed record (a `class`/cell) *and* the RHS did not write that local, skip the
`saved` copy, the `refresh` and the final `assign`, leaving the update as a statement
whose result is discarded. The write check is available: the checker already counts
`locals[owner].usage.writes` (sema.zig:1595) for the destination before the RHS, so
snapshotting it before `expressionWithTemporaries` and comparing after detects an RHS
write. When the RHS does write the base, keep today's shape exactly.

Expected effect: the review measured the current shape at ~15 instructions against ~6
for the direct form, putting `advance` near 40 and under the cap, which should also
shrink every class-mutating function in the port. Census then needs re-measuring; the
review's estimate is 5-6x.

Also queued from the same review, to do after that measurement rather than at the same
time: lazy frame records for leaves that can trap but neither call nor allocate
(allocate and link on the cold path, where the callee still knows its own metadata and
pc) — with `--max-frames` accounting either kept as the four-instruction compare or
made build policy the way step accounting already is (`main.zig:507`), since an
inlined or lazily-framed callee must not silently change the depth count; and the three
dead instructions after an inlined scalar cast (position store, trap load, branch after
a `copy`), which the tokenizer pays on every byte.

### Lazy frames: corrected arithmetic and the hook that already exists

Implementing item 3 turned up two things that change its size and its shape.

**Correction to the 11 % figure.** The 11.4 % of cycles that `advance`'s frame costs
is *not* recoverable by lazy linking alone, because it decomposes as 5.3 % bound
checks (the `--max-frames` compare and the stack-floor test) plus ~6.8 % record
bookkeeping. A lazy record still needs the bound checks — they are what makes
`--max-frames` exact — so lazy linking alone recovers only the bookkeeping, roughly
**4-5 % of cycles**, not 11 %.

**The full 11 % needs frame accounting to be build policy, and the hook for that
already exists.** `main.zig:710` declares `saw_frames` and line 858 sets it when a
build is given `--max-frames`, but nothing reads it at emission time — while its
twin `saw_steps` *is* threaded into the emitter at `main.zig:507` and suppresses all
step accounting in a plain build. Frames can follow the same precedent: when a build
was not given a frame ceiling, emit no limit check and no depth counter, and have the
executable refuse a runtime `--max-frames` loudly the way the step path does. That is
what recovers the other 5.3 %, and with lazy linking on top the whole ~11 % comes
back with trap traces still exact.

**The constraint that shapes the implementation.** `fail()` builds the trace eagerly
(`qbe_runtime.c:200-214` walks `ctx->active_frame` at the moment a helper is called),
so a lazily linked record must be linked *before* the helper call, not on the shared
`@failure` path afterwards. There are twelve such emission sites — four in
`qbe_scalar.zig`, two in `qbe_managed.zig` (plus the name-parameterised
`requireIndexBounds`), one each in `qbe_aggregate.zig` and `qbe_host_lower.zig`, and
three in `qbe.zig` — so the link belongs in one `Emitter.trap()` wrapper those sites
call instead of `print`.

Order of work: thread `saw_frames` into the emitter and gate the limit check and
counter on it; add the loud runtime refusal; then lazy linking through `trap()` for
functions that contain no `.call`/`.invoke` and no op whose C helper can fail on its
own; then gate, gc-stress, goldens and the audit. Each half is independently
measurable, and the build-policy half is the larger of the two.

## 1. The answer in one table

The gap is **instruction count, not efficiency**: mylang retires more
instructions per cycle than Zig (2.4 vs 2.0 IPC) while executing 60–90× as
many. Cache misses and branch misses are an order of magnitude below the
instruction ratio (`evidence/perf-profile.md`). So this is a code-generation
problem, and it decomposes into four mechanisms, which a hand-patched IL ladder
on the `scan` driver isolates one at a time:

| `scan` build (same bytes, same output)                      | instructions | cycles | ÷ Zig instr |
| --- | ---: | ---: | ---: |
| current `mylang build --mode ReleaseFast`                   | 714.9 M | 189.1 M | **90×** |
| A: every GC root push/restore deleted                        | 316.1 M |  57.2 M | 40× |
| AB: + `bytes[i]` and `u8→i64` cast inlined (no helper call)  | 104.4 M |  25.8 M | 13× |
| ABC: + per-instruction position stores deleted               |  83.9 M |  17.4 M | 10.5× |
| hand-written IL of the *proposed* lowering (§3), same checks |  25.1 M |   6.5 M | **3.1×** |
| Zig `ReleaseFast` (`zig-bench --scan`)                       |   8.0 M |   3.5 M | 1× |

Read bottom-up: QBE itself is not the ceiling. The same loop, with the same
bounds check and the same overflow-checked adds, costs 25 M instructions when the
IL is shaped the way §3 describes. The 690 M instructions between that and today
are, in order of size:

1. **GC safepoint root pushes** (56% of `scan`): 5–6 `myl_native_root_push`
   calls plus a `myl_qbe_root_restore` call around *every* `bytes[i]` and every
   integer cast, neither of which can allocate.
2. **Runtime helper calls for trivial operations** (30%): `bytes[i]` is a call
   to `myl_native_list_get` that `memmove`s one byte; `u8→i64` is a call to
   `myl_qbe_int_cast`; `*`, `//`, `%`, shifts are calls to
   `myl_qbe_int_binary`; every float op first calls `myl_qbe_float_check`.
3. **Position stores** on every fallible instruction (3% of `scan`, 20% of what
   is left after 1 and 2).
4. **Address-taken operand slots** (the remaining 3× over the ideal): because a
   slot's address is passed to `root_push` somewhere in the function, QBE can
   never promote it, and since QBE has no dead-store elimination every push and
   pop is a real `movq` to the frame even when the value is also in a register.

Mechanisms 1 and 4 have one root cause — the per-safepoint root protocol — and
one fix (Wave 4). Mechanism 2 is a set of independent inline lowerings (Wave 2).
Mechanism 3 is a small change to how traps learn their pc (Wave 3). On top of
those, the tokenizer and parser pay for the **call protocol** (§2.5: ~150
instructions per guest call, four runtime calls each) and for **string
literals built at run time** (§2.6).

Phase-level counts on this checkout, for the record:

| driver | mylang instr | Zig instr | ratio | mylang cycles | Zig cycles | ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `h_loop` (empty `while`) | 40.2 M | 2.1 M | 19× | 14.4 M | 2.3 M | 6× |
| `e_scan` (byte compare) | 714.9 M | 8.0 M | 90× | 189.1 M | 3.5 M | 54× |
| `i_index` (byte read + add) | 382.8 M | — | — | 96.0 M | — | — |
| `f_calls` (1 M calls) | 370.3 M | — | — | 69.3 M | — | — |
| `b_tokens` (read + tokenize) | 1,469.1 M | 18.3 M | 80× | 359.5 M | 5.6 M | 64× |
| `c_parse` (+ parse) | 1,514.3 M | 22.3 M | 68× | 376.8 M | 8.5 M | 44× |

(`f_calls` is 370 instructions per iteration for one `bump(n)` call, one
`ROUNDS` constant read and one checked add.)

## 2. Where the instructions go

All IL below is from `mylang emit-project-qbe e_scan.my --drop-step-checks`,
i.e. the exact text a `ReleaseFast` executable build lowers.

### 2.1 GC roots are re-pushed at every safepoint, and the safepoint set is wrong

`Emitter.allocates()` in `src/qbe.zig` decides which instructions are GC
safepoints. It lists whole opcodes: `get_index`, `binary_integer`,
`cast_integer`, `make_record`, `call`, `print`, … For each one, in a function
that holds any traced local, `roots(stack)` emits one `myl_native_root_push`
call per traced local and per traced operand slot, then the op, then a
`myl_qbe_root_restore` call. In `scan`'s loop body that is, per byte read:

```
 call $myl_native_root_push(l %heap, l %root0, l %l0, ...)   ; args
 call $myl_native_root_push(l %heap, l %root1, l %l4, ...)   ; source
 call $myl_native_root_push(l %heap, l %root2, l %l5, ...)   ; fs
 call $myl_native_root_push(l %heap, l %root3, l %l7, ...)   ; match payload
 call $myl_native_root_push(l %heap, l %root4, l %l8, ...)   ; match payload
 call $myl_native_root_push(l %heap, l %root5, l %s0, ...)   ; operand: source
 ... myl_native_list_get ...
 call $myl_qbe_root_restore(l %ctx, l %root_mark)
 call $myl_native_root_push × 5                               ; again, for the cast
 %v128 =l call $myl_qbe_int_cast(l %ctx, l 0, l 1, l 64, l %v127)
 call $myl_qbe_root_restore(l %ctx, l %root_mark)
```

Two `source[index]` reads per iteration → **22 root pushes and 4 restores per
input byte**, each a real call with ~6 argument moves. Neither `get_index` on
`bytes` (an inline load) nor an integer-to-integer `cast_integer` can allocate;
`allocates()` returns true for them because the *opcode* can allocate in some
other variant (`str[i]`, `str(x)`). `binary_integer` is listed for the same
reason (string concatenation), so even `a + b` on `u32` is a safepoint.

Deleting every push/restore from the IL (build A) removes 399 M of 715 M
instructions. The root list itself is a three-store linked-list push
(`native_heap.c:120`), so the cost is entirely the call protocol and the
argument marshalling, repeated per safepoint instead of once per frame.

### 2.2 Trivial operations are runtime calls

| source | lowering today | what it should be |
| --- | --- | --- |
| `bytes[i]`, `list[i]` | `normalizedIndex` branch+phi, `loadl` length, `call myl_native_list_get` (memmove into `%agg`), `jnz`, `loadub %agg` | `cultl i, len` + cold trap, `loadub storage+i` |
| `int(u8)`, any int→int cast | `call myl_qbe_int_cast(ctx, from_signed, to_signed, width, v)` + trap check | widening: `copy`/`extub`; narrowing: one range compare + cold trap |
| `a * b`, `a // b`, `a % b`, `<<`, `>>`, `floor_div` | `call myl_qbe_int_binary(ctx, op, signed, width, a, b)` + trap check (`qbe_scalar.zig:53`) | `mul` + overflow test, `div`/`rem` + zero and MIN/−1 checks, shifts + range check |
| every float `+ - * /` | `call myl_qbe_float_check(ctx)` (calls `fegetround` and two volatile multiplies) + trap check, then the op | check the FP environment once per context at start-up |
| `str[i]` | `call myl_native_text_at` (allocates unless ASCII) | keep, but it must not force roots on unrelated ops |
| `len(x)` on a list | already inline (`loadl`) | — |

Build AB (inline index + no cast call) removes another 212 M. `i_index` and the
tokenizer's `peek`/`advance` are dominated by exactly these two ops.

### 2.3 Position stores

`storel <pc>, %position` is kept on every instruction whose body mentions a
failure path (`QBE-POSITION-1`), because `fail()` (`qbe_runtime.c:151`) reads
`active_frame->position` to build the trace. In `scan` that is every index,
cast, checked add and call: a store to memory through the `%frame` pointer per
op. Deleting them (build ABC) removes 20 M of 104 M. The store is only needed
where a *callee* can trap (a call site, so the caller's frame names the right
line) or where a collector needs to know the pc (Wave 4); an inline check that
fails can pass its own pc to the cold helper as an argument.

### 2.4 Operand slots are pinned in memory

Every operand slot `%s{i}` and local `%l{i}` is an `alloc8 8`. QBE's `promote`
pass turns an alloc into an SSA temporary only if its address never escapes.
`roots()` passes `l %s{i}` and `l %l{i}` to `myl_native_root_push`, so every
slot that ever holds a traced value anywhere in the function is address-taken
and stays in memory for the whole function — including at the many pcs where it
holds an `int`. QBE's `loadopt` still forwards the loads, so the values *are*
in registers; but QBE has no dead-store elimination, so every `storel` to a
pinned slot is emitted. That is the `movq %rax, (%r13)` spam in the empty
loop (`h_loop`: 43 instructions per iteration for two checked adds and a
compare; the arithmetic is 15 of them).

The consequence for the design: **scalar operand slots must never have their
address taken**, and traced values need storage the collector can find without
the emitter handing out slot addresses at every safepoint.

### 2.5 Calls cost ~150 instructions and there is no inlining

A guest call today (`f_calls`, `bump`):

- caller: position store, `myl_native_root_push` per traced local/slot (call),
  the call, store result, `myl_qbe_root_restore` (call), `loadl %trap` + branch;
- callee: `myl_qbe_enter_at_sized` (call → `enter_at` → `enter`: stack-bottom
  probe, byte-limit check, frame-limit check, indexed `frame_data` slot with a
  struct zeroing, function pointer, byte accounting), trap check, allocs, arg
  store, `loadl` active frame, position store, the body, `myl_qbe_leave` (call:
  frame count check, byte accounting, active-frame recompute).

Four runtime calls per guest call. Zig inlines `bump` to one `add`. The
tokenizer's inner loop calls `peek` (100 lines of IL for `if pos >= len: return
-1; return src[pos]`), `advance`, `is_digit`, `is_atom_continue` … per byte.

Two aggravations visible in the bytecode:

- A module `const` is compiled as a **function** and every read is a `CALL`
  (`0005 CALL 0 (ROUNDS)` inside the loop condition of `f_calls`). A scalar
  constant should fold to `PUSH_I64`.
- QBE has no inliner, and the bytecode has none either, so every helper the
  Python-style code factors out is a real call.

### 2.6 String literals are built at run time; `str` is u32; `lexeme` allocates twice

A string literal compiles to `PUSH_INT u32` × N then `MAKE_RECORD str fields=N`,
which lowers to `myl_native_list_new` + N `myl_native_list_append` calls
(`qbe_managed.zig:258`). `"("`, `")"`, `""` in `tokenize` and every literal the
printer emits are re-allocated on every evaluation. Zig points at `.rodata`.

`str` stores one `u32` per scalar, and `lexeme()` does `src[start:end]` (one
`bytes` allocation) then `.decode()` (validate + a second, 4× larger
allocation). At 19,155 tokens this is ~5 ms of the 90 ms `tokens` phase — real
but secondary; it is listed under "later" rather than in the waves.

### 2.7 What is *not* the problem

- The collector: `d_decode`/`g_append` show 19 k decodes cost 5 ms and
  retaining them 4 ms more. Collection is not on the profile.
- The C runtime is `-O2` and QBE runs its full pipeline; nothing is unoptimised.
- Branch prediction and cache behaviour: misses are 7–16× Zig's while
  instructions are 98×.
- Zig `ReleaseSafe` being faster than `ReleaseFast` (0.89–0.98×) is a
  curiosity of the Zig side and does not change the target: the comparison
  column is Zig `ReleaseFast`, and mylang's checks (bounds, overflow) are kept
  in every proposed lowering, so the fair comparison is really against Zig's
  safe build.

## 3. Target lowering

This is the shape of the generated code after the plan. The hand-written
`evidence/ideal-scan/scan_ideal.ssa` is this shape for the `scan` loop and
measures 25.1 M instructions.

**Frame record in the native stack.** Each guest function allocates one
32-byte record `{prev, function_meta, position, block}` with `alloc8`, links it
into `ctx->active_frame` (offset 48, frozen) with two stores, and unlinks it on
return with one store. There is no `frame_data` array, no capacity, no scratch
frame; the trace walker and the collector follow the chain. The native-stack
guard becomes one compare of the record's address against a precomputed floor
(`native_stack_bottom + slack`). `--max-frames` keeps its semantics with a
depth counter in the record (`prev.depth + 1`, compared to `ctx->frame_limit`).

**Two-tier value storage.**
- *Scalar* locals and operand slots (`int`, `bool`, `float`, capabilities,
  enums, domains over scalars) are private `alloc8 8` temporaries whose
  address is never passed anywhere. QBE promotes them; the loop runs in
  registers.
- *Traced* values (managed pointers, records/variants/arrays containing them,
  the `%agg` temporaries) live in **one frame block** whose base is stored in
  the frame record. Loads and stores address it as `block + offset`. It is
  memset once at entry.
- The emitter knows the static type of every (pc, slot) from `native_ir.zig`,
  so each `load`/`store` picks the tier. A slot index may be scalar at one pc
  and traced at another; the two tiers are separate storage, which is fine
  because the type is fixed per pc.

**Stack maps instead of root pushes.** For every safepoint pc (an instruction
whose lowering can reach `myl_native_heap_alloc`, or a call), the emitter
records the list of `(block offset, type descriptor)` that is live and traced
at that pc. `qbe_build_outputs.zig` emits it into the function's `_meta` next
to `locations`. The collector walks `ctx->active_frame → prev → …`, reads each
frame's `position`, looks up `meta->stack_maps[position]`, and traces
`block + offset` with the descriptor. The position store therefore moves to
**safepoints only** (one `storel` before a call or allocating helper) and
doubles as the trace pc. Runtime-internal roots (`myl_native_root_push` inside
C helpers such as `bytes_decode`) keep the existing root list; the collector
walks both.

**Trap pc by argument.** Inline checks that fail jump to a cold block that
calls `myl_qbe_fail_*_at(ctx, pc, …)`; the helper writes `pc` into
`active_frame->position` before building the trace. Hot paths carry no store.

**Inline primitives.** `bytes[i]`/`list[i]`: unsigned compare against the
length word, then a typed load from `storage + i*stride` (negative indices via
the unsigned compare's cold path, which adds `len` and retries). Integer casts:
`extub/extsb/extuh/…` for widening, one range compare for narrowing. `mul`:
QBE `mul` plus the standard overflow test (`div` back or the 128-bit
`mul`/`sar` check); `div`/`rem`: zero check and `MIN / -1` check; shifts: range
check. Float environment: one check at context start-up (and after any FFI
call, if `c-ffi` is linked) instead of per op.

**Static literals.** A `str`/`bytes` literal becomes a `data` object in the
manifest (header + storage, `immortal` flag in the object header so the mark
phase returns early), referenced by symbol. `MAKE_RECORD` from constant pushes
is pattern-matched at lowering.

**Bytecode-level inlining and constant folding.** A `const` scalar folds to
`PUSH_*`. A non-recursive function whose body is under a size threshold and
whose effects/capabilities are already satisfied by the caller is inlined at
the bytecode level (`RET` → store result + jump to continuation; callee locals
appended to the caller's scope). The meta table gets an `inline_frames` range
table so trap traces still print the callee frame.

Result for the `scan` loop: no calls, no stores to memory except the two
scalar locals if QBE chooses to spill, ~27 instructions per byte (two bounds
checks, two compares, two checked adds, loop test) against Zig's 8.6.

## 4. Waves

Each wave is independently landable and measurable, and each keeps the full
gate green. Guardian rules apply: a `// spec: TAG` test per behavioural change
with a matching `- [TAG] …` bullet in `SPEC.md`; new `src/*.zig` files reachable
from `guardian.toml` roots; ≤7 struct fields (group new emitter state into a
sub-struct rather than widening `Emitter`); `///` on every `pub`.

Proposed tag names are new (none collide with the current `QBE-*`/`GC-*` set).

### Wave 0 — measurement harness (½ day)

- Add `experiments/sexpr-audit/perf_ladder.py`: builds the drivers, runs
  `taskset -c N perf stat -x, -e instructions,cycles` on each and on the two Zig
  binaries, prints the ratio table above, writes `evidence/perf-ladder.json`.
  Needs `kernel.perf_event_paranoid ≤ 1`; opt-in, not part of the gate.
- Keep `il_counterfactual.py` (already in the directory) as the way to try an
  IL-level idea before implementing it: `emit-project-qbe` → patch → `mylang
  build --manifest-file=…`.
- Acceptance: the table in §1 reproduces within ±5% on instructions.

### Wave 1 — precise safepoints, inline root pushes (1–2 days) — `QBE-SAFEPOINT-1`

Smallest, safest win; removes mechanism 1 from ops that cannot allocate.

- `allocates()` in `src/qbe.zig` becomes per-variant: `get_index` only for
  `str`; `cast_integer` only for an aggregate target; `binary_integer` only for
  string/bytes `+`; `buffer_operation` only for kinds that allocate (`append`,
  `insert`, `extend`, `slice`, `decode`, `encode`, `join`, `split`, `from_hex`,
  …, not `length`/`read`/`write`/`contains`/`iteration_check`/`pop`/`clear`);
  `make_record` only for managed records and collections. Derive it from the
  lowering: every emitter that prints `myl_native_heap_alloc`, `list_new`,
  `text_*`, `bytes_*` or a call must be a safepoint. Add a Zig test that emits
  each op and asserts the presence/absence of `root_push` in the text.
- Emit the push inline (`storel prev; storel addr; storel type; storel root`)
  and the restore as one `storel`, instead of calls. Keeps the protocol,
  removes the call.
- Verification: `mylang test tests/lang --gc-stress`, the sexpr port suite under
  `--gc-stress`, `zig build test-qbe`, goldens. A wrong `allocates()` answer
  loses a live reference, so stress collection is the gate for this wave.
- Expected: `scan` 715 M → ~320 M (measured build A is 316 M; the loop has no
  true safepoint left). `tokens` roughly −40%.

### Wave 2 — inline primitives (2–3 days) — `QBE-INDEX-1`, `QBE-INTCAST-1`, `QBE-INTOPS-1`, `QBE-FLOAT-ENV-1`

- `qbe_managed.zig` `emitIndex`/`emitOperation(.read)`: inline bounds check and
  typed load for list/bytes elements; the cold path keeps calling
  `myl_qbe_fail_index_bounds` with the original index and length so the trap
  detail is byte-identical. `myl_native_list_get` stays for the C side.
- `qbe.zig` `.cast_integer` scalar branch and `qbe_scalar.zig`: inline casts,
  `mul`/`div`/`rem`/`floor_div`/`floor_rem`/shifts; the overflow cold path calls
  `myl_qbe_fail_overflow_op` exactly as `add`/`sub` do today.
- `qbe_scalar.zig` `floatBinary`/`unary_float`: drop the per-op
  `myl_qbe_float_check`; call it once from `execute_config_args` and after each
  `c-ffi` call boundary (`qbe_c_abi.zig`). Keep `R_FLOAT_ENVIRONMENT` semantics.
- Tests: guest tests in `tests/lang/` for every boundary (negative index,
  `len`, `MIN * -1`, `MIN // -1`, `x % 0`, shift by width, narrowing casts at
  both edges) comparing against the existing trap codes and detail JSON;
  differential stderr test like the one Lever 2 used.
- Expected: `scan` ~320 M → ~105 M (build AB). `i_index`, `peek`, `advance`
  become straight-line.

### Wave 3 — trap pc by argument (1 day) — `QBE-POSITION-2`

- Add `_at` variants of the cold failure helpers taking `pc`, or a leading
  `pc` argument on all of them (they are all cold). `fail()` records
  `active_frame->position = pc` first.
- `elideUnobservablePositions` shrinks to: keep the store only before a call,
  an `invoke`, a `print`, an `assert`, and (from Wave 4) every safepoint.
- Verification: the located-trap tests and the differential stderr comparison
  are unchanged; assert messages unchanged.
- Expected: `scan` ~105 M → ~85 M (build ABC).

### Wave 4 — frame records, stack maps, two-tier storage (1–2 weeks) — `QBE-FRAMES-1`, `QBE-STACKMAP-1`, `QBE-SLOTS-1`

The structural change; lands mechanisms 1 and 4 for good and makes calls cheap.

1. `QBE-FRAMES-1` (runtime + prologue). New `src/qbe_frames.zig` emits the
   record, the link/unlink stores, the stack-floor compare and the depth
   counter; `qbe_runtime.c` replaces `frame_data`/`active_frame` indexing with
   chain walking in `fail()`, `myl_qbe_leave` semantics move inline, and
   `myl_qbe_enter_at_sized` survives only for host/C-ABI wrappers. Heap-backed
   large frames (`heap_frame`) keep `myl_qbe_frame_allocate` for the block.
   `R_FRAME_LIMIT`, `--max-frames`, trace format and `omitted_frames` are
   preserved; tests in `src/qbe_test.zig` and `test/integration.zig` already
   cover them.
2. `QBE-STACKMAP-1` (collector). `native_heap.h` gains
   `trace_frames(void *ctx, myl_native_heap *)` + context; `myl_native_heap_collect`
   calls it before walking the root list. `qbe_build_outputs.metadata` emits
   `_meta_stackmaps` (per safepoint pc: count + `{offset, type}` pairs) and a
   pointer in `MylQbeFunction`. `qbe.zig` computes the maps from `states[pc]`
   and the local table. `roots()` and the `%root{i}` allocs are deleted.
3. `QBE-SLOTS-1` (storage tiers). `Emitter.load/store` take the slot's static
   type and route to `%s{i}` (scalar alloc) or `block + offset(i)`. Locals
   likewise. The `%agg{pc}`/`%aux{pc}` temporaries move into the block.
   `zero_local` becomes one memset of the block.
4. Position stores: exactly one before every safepoint (Wave 3 already limited
   them to calls); the map lookup uses it.

- Verification is the whole gate plus `--gc-stress` on `tests/lang`, the sexpr
  port and `tests/goldens`, a new stress test that allocates inside deep
  recursion (frames past the old 1024 capacity) and inside `with arena()`, and
  the arena escape tests (`qbe_arena.zig` barriers read locals through the
  block now). Type-size ratchet: `MylQbeActiveFrame` changes shape; accept the
  baseline deliberately.
- Expected: `scan` ~85 M → ~30 M (ideal 25 M); `h_loop` 43 → ~15 instr/iter;
  `f_calls` 370 → ~60 instr/iter (two calls: `bump` and the `ROUNDS` read);
  `tokens` and `parse` roughly ÷4 from Wave 3.

### Wave 5 — static literals and constant folding (2–3 days) — `QBE-LITERAL-1`, `BYTECODE-CONST-1`

- `qbe_managed.zig` `emitConstruct`: when every operand is a `push_integer`,
  emit a `data $lit_<hash> = { l 0, l N, l N, l 0, l $desc, l $lit_<hash>_s, … }`
  plus the storage, mark `immortal` in `myl_native_object` (header precedes
  the payload; add a flag bit the mark phase tests first). `str` is immutable,
  `bytes` literals too, so no write barrier concern. Cover `region` (0) so
  arena checks treat literals as heap-owned.
- `src/compiler.zig`: fold a `const` of scalar type to its `PUSH_*` at each
  use; the function stays for address-taken/generic uses.
- Expected: `tokenize`/printer stop allocating per literal; `f_calls` loses one
  call per iteration; `render` gains most.

### Wave 6 — bytecode inliner (1 week) — `BYTECODE-INLINE-1`

- New pass between `compiler.zig` and `native_ir.zig`: inline non-recursive
  callees under N instructions (start at 24) with no `begin_arena`, no
  `try_result` targets outside the body, and whose capability/effect
  parameters are plain pass-through. Rename callee locals into the caller,
  rewrite `RET` to `STORE_LOCAL tmp; JUMP cont`, keep each instruction's
  `span` so `locations[]` stays exact. Emit an `inline_frames` table
  (`pc range → callee name`) so `fail()` synthesises the callee frame in the
  trace; the differential trap tests are the acceptance test.
- Guard with a size budget per caller so `tokenize` does not explode; measure
  with `--report` build timings (the frontend cache means the bytecode is
  per-function content-addressed — check that inlining does not defeat body
  reuse, see `docs/tooling/caches.md`).
- Expected: `tokens` within ~4× of Zig; `peek`/`advance`/`is_*` vanish as
  calls.

### Later (not in this plan)

- A QBE extension exposing the overflow flag (`add` + `jo`) would cut the
  checked add from 6 instructions to 2; touching the vendored compiler is a
  separate decision.
- Bump/generational allocation in `native_heap.c` (today: `calloc` + linked
  list per object). Not on the profile for this workload.
- UTF-8-backed `str` (4× less memory, decode becomes a validate) and a fused
  `bytes.decode(start, end)`. Source-level today: keep spans, decode lazily.
- Cross-boundary inlining of the C runtime (LTO of `qbe_runtime` into the
  guest object). Only worth it once the helper calls that remain are hot.

## 5. Verification protocol (every wave)

```
zig build && zig build test --summary all
zig build test-qbe --summary all
zig build test-qbe-build --summary all
zig build fmt-check
zig-out/bin/mylang test tests/lang --gc-stress
zig-out/bin/mylang test experiments/sexpr-port --gc-stress
python3 experiments/sexpr-port/golden_compare.py          # 17 goldens byte-identical
python3 experiments/sexpr-audit/perf_ladder.py --runs 3   # instruction counts vs the table in §1
python3 experiments/sexpr-audit/compare_impls.py --runs 31 # wall clock vs Zig
```

Plus, for Waves 1–4, the differential trap check: run the bounds, division,
overflow, assert and nested-call trap fixtures before and after and diff
stderr, including the `[trap-record]` JSON line (`QBE-TRAP-DETAIL-1`).

## 6. Expected end state

| driver | today | after W1–W4 | after W5–W6 | Zig |
| --- | ---: | ---: | ---: | ---: |
| `e_scan` instructions | 715 M | ~30 M (measured floor 25 M) | ~30 M | 8.0 M |
| `e_scan` wall | 46.5 ms | ~4 ms | ~4 ms | 1.6 ms |
| `f_calls` instr/iteration | 370 | ~60 | ~15 | — |
| `b_tokens` instructions | 1,469 M | ~250 M (estimate) | ~80 M (estimate) | 18.3 M |
| `b_tokens` wall | 89 ms | ~15 ms | ~6 ms | 2.4 ms |

The `scan` row is measured (the ideal IL); the `tokens` rows extrapolate the
same mechanism mix plus the call protocol and are estimates to be replaced by
Wave 0's ladder as waves land. The realistic end point is **2–4× Zig
`ReleaseFast`** for byte-loop code with all checks kept, which is the QBE
floor; closing the rest needs a stronger optimiser than QBE, not more runtime
work.

## 7. Reproduce

```sh
# Zig reference (once)
cd experiments/sexpr-port/zig-bench && \
  ZIG_LOCAL_CACHE_DIR=/tmp/zb-cache ZIG_GLOBAL_CACHE_DIR=/tmp/zb-global \
  zig build -Doptimize=ReleaseFast -p /tmp/zb-ReleaseFast-out
# perf needs: sudo sysctl kernel.perf_event_paranoid=1
cd experiments/sexpr-audit
zig-out/bin/mylang build e_scan.my -o /tmp/e_scan --mode ReleaseFast
taskset -c 6 perf stat -e instructions,cycles -- /tmp/e_scan /tmp/sexpr-bench/input.sexp
taskset -c 6 perf stat -e instructions,cycles -- /tmp/zb-ReleaseFast-out/bin/zig-bench /tmp/sexpr-bench/input.sexp --scan
# the IL ladder
zig-out/bin/mylang emit-project-qbe e_scan.my --drop-step-checks > /tmp/scan.json
python3 il_counterfactual.py /tmp/scan.json /tmp/scan_ABC.json ABC
zig-out/bin/mylang build e_scan.my --manifest-file=/tmp/scan_ABC.json -o /tmp/scan_ABC --mode ReleaseFast
# the proposed-lowering floor
cd evidence/ideal-scan && ../../../../zig-out/bin/qbe -o /tmp/ideal.s scan_ideal.ssa && \
  cc -O2 -o /tmp/ideal /tmp/ideal.s scan_ideal_rt.c && \
  taskset -c 6 perf stat -e instructions,cycles -- /tmp/ideal /tmp/sexpr-bench/input.sexp
```

Evidence for the earlier four levers (step checks, position elision, prologue,
straight-line blocks) is in `experiments/sexpr-audit/evidence/levers.md`; this
document starts where that one ends.
