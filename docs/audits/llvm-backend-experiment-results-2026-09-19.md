# LLVM backend experiment: results

19 September 2026. Answers the question in
[`llvm-backend-experiment-plan-2026-09-19.md`](llvm-backend-experiment-plan-2026-09-19.md):
**how much of mylang's remaining runtime gap comes from QBE optimizing and
generating code for the current lowering?**

Everything below is measured, not projected. Reproduction commands, raw samples
and hashes: [`experiments/llvm-backend/`](../../experiments/llvm-backend/README.md)
and `experiments/llvm-backend/evidence/`.

## Decision

**A repeatable 5.4–8.9% whole-program speedup, with correctness intact: inside the
plan's own `<10%` band.** The evidence does not support adopting LLVM as an
optimized/release backend for this lowering, and it does not support a universal
QBE floor either — the mechanism is now known, and it points at the IR rather than
at the code generator.

The translator removes a quarter to a third of all retired instructions, and that
buys only 4–10% of wall time, because the instructions it removes are the cheap
ones. Instructions and cycles fall far more than wall time on every workload
(§3), and IPC *falls* on every workload — LLVM's code is shorter and less
parallel, which is the signature of a program whose cost has moved into memory
rather than into the code generator. Per §9 of the plan, that means the next
investment belongs in representation and runtime work, not in a second backend.

## 1. What was built

An isolated LLVM route for the whole benchmark closure, with the compiler's
default backend and public language untouched:

| component | role |
|---|---|
| `qbe_llvm.py` | a drop-in replacement for the QBE tool the native driver invokes (`-t amd64_sysv -o out.s unit.ssa`): parses one emitted QBE unit, emits LLVM IR, runs the pinned `zig cc` to produce the assembly the existing assembler/linker pipeline consumes |
| `llvm_emit.py` | LLVM IR emission, with every temporary in one entry-block slot that LLVM's own `mem2reg`/SROA promotion turns back into SSA |
| `tests/abi/` | hand-written QBE probes that pin the target ABI the arm has to reproduce |
| `evidence/` | the unit inventory, the build receipts, and the raw measurement JSON |

No compiler source changed; no default backend changed; no public language
surface changed. The LLVM used is the one inside the pinned Zig release (clang
22.1.8, `zig cc -S -O2 -fPIC -g0 unit.ll -o unit.s`), so both arms share a code
generator and differ only in the frontend that reaches it.

## 2. Correctness

Correctness gates ran before any performance conclusion:

| gate | command | result |
|---|---|---|
| every emitted unit translates and assembles | `python3 -B experiments/llvm-backend/verify_units.py /tmp/census-manifest.json` | **66 units, 0 failed** |
| every referenced symbol resolves to a definition | `symbol_census.py` + `resolve_symbols.py` | **233 symbols, 0 unresolved** (37 runtime functions, 132 metadata records, 42 literals, 20 descriptors, 1 renderer, `memset`) |
| guest-behaviour suite through the LLVM arm | `mylang test experiments/sexpr-port --qbe=…/qbe_llvm.py` | **79 passed, 0 failed** (identical to the QBE arm's 79) |
| four benchmark workloads, both arms | `python3 -B experiments/llvm-backend/verify_semantics.py` | **4 cases, 0 without agreement**; stdout identical byte for byte (118 / 700 425 / 124 / 5 603 400 bytes) |

The comparison is byte-for-byte stdout, stderr and exit status from binaries both
built by the same compiler with the same flags, the same runtime archive and the
same generated C metadata.

### Traps, accounting and GC stress

The repository's differential trap fixtures
(`experiments/sexpr-audit/evidence/hot-loops/trapdiff`) exist because a change to
the root protocol or the position stores can move a trap address, drop a
sticky-trap test or reorder a frame chain without changing any value a passing test
would print. Every fixture was built by both backends in six modes — ReleaseFast,
ReleaseFast with `--max-frames` and with `--max-steps`, and Debug with and without
the same ceilings — and both binaries had to agree on stdout, stderr and exit
status (`experiments/llvm-backend/verify_traps.py`):

| check | result |
|---|---|
| built-binary comparisons across 21 fixtures | **108 comparisons, 0 mismatches** |
| `mylang run` plain vs `--gc-stress` control | **21 controls, 0 mismatches** |

The fixtures cover bounds (inline, list, negative index), checked overflow (add,
sub, mul, neg, a mul chain), division and remainder by zero, narrowing and
float-to-int casts, `assert` text, an out-of-range shift, a trap inside an inlined
and a non-inlined callee, a sticky call, and a deep call chain.

**Deep recursion and the logical budget.** A new `recursion.my` fixture descends
20 000 frames as a *ReleaseFast* build, whose physical frames are the backend's own
size — this is where an LLVM-arm frame could overflow the physical stack before the
logical budget traps. Both arms trap identically instead, with the same located
`R_STEP_LIMIT` message and status at `--max-steps` of 100, 1 000 and 50 000: the
step budget is what stops the descent, so the stack-floor guard holds under the
LLVM arm's frame sizes as well as QBE's. `--max-frames` is a `mylang run` control
and a standalone ReleaseFast binary refuses it with `R_NO_FRAME_ACCOUNTING` in both
arms, byte for byte.

Two limits of this gate, stated rather than hidden: `mylang run` does not accept
`--qbe`, so GC stress is exercised as a control on both arms rather than as an
LLVM-arm gate (the LLVM arm's allocation paths are covered by the port's 79 guest
tests and the four benchmark workloads, which all run under `--gc-stress`'s
counterpart, the ordinary collector); and the fixtures are cheap enough that
physical-stack exhaustion is not reached, so the frame-size difference is bounded
rather than fully explored.

### What the port's own test suite found

The port's guest suite was the strongest signal in the whole experiment. It
caught two miscompilations that the four benchmark workloads did *not*:

* **Aggregate results declared as `i64`.** The IL annotates a call's destination
  with the aggregate's name (`%v =:t43894… call $f(…)`). Ignoring that annotation
  declared a function returning a struct as returning `i64`; LLVM then lowered the
  callee through `sret`, which moves the hidden result pointer into `%rdi` and the
  hidden `ctx` from `%rdi` to `%rsi`, so the callee read `ctx = 0`. 28 of the 80
  internal call sites in the census corpus had this shape.
* **`phi` was dropped.** `%v105 =l phi @nan108 9221120237041090560, @finite108
  %v110` is the *only* definition of `%v105`, and the frontend wraps **every float
  arithmetic result** in that shape. Treating the phi as a no-op left the slot
  unwritten, so every float arithmetic result was `undef`.

Both are now lowered correctly; the second is lowered by storing each phi input on
the edge out of the block that supplies it, which is where the value is known.

## 3. Benchmark

Matched batch, 31 interleaved rounds, parent and children pinned to one physical
CPU, all four arms in every round; the counter batch is separate because
`perf stat` doubles a 10 ms run's wall time. `MyLang` is the QBE arm; `LLVM` is the
arm this experiment built. Raw values:
`experiments/llvm-backend/evidence/measure.json`.

### Wall time (median ms, IQR)

| workload | QBE | LLVM O2 | LLVM O3 | Zig ReleaseFast |
|---|---:|---:|---:|---:|
| census 927 KB | 9.38 ±0.29 | 8.85 | **8.62** | 2.19 |
| render 927 KB | 15.04 ±0.78 | 14.13 | **14.09** | 3.20 |
| census 7.42 MB | 83.93 ±0.96 | 78.35 | **78.10** | 14.34 |
| render 7.42 MB | 132.43 ±1.94 | 125.60 | **125.20** | 25.44 |

### Ratios, same batch

| workload | QBE/LLVM O2 | QBE/LLVM O3 | QBE/Zig |
|---|---:|---:|---:|
| census 927 KB | **1.060×** [1.016, 1.092] | **1.089×** [1.054, 1.108] | 4.284× [4.180, 4.394] |
| render 927 KB | **1.065×** [1.042, 1.089] | **1.067×** [1.019, 1.082] | 4.706× [4.577, 4.779] |
| census 7.42 MB | **1.071×** [1.060, 1.079] | **1.075×** [1.070, 1.081] | 5.852× [5.776, 5.899] |
| render 7.42 MB | **1.054×** [1.051, 1.060] | **1.058×** [1.052, 1.064] | 5.205× [5.155, 5.249] |

Brackets are 95% bootstrap intervals that resample **rounds**, preserving the
pairing inside each interleaved batch.

### Counters, separate matched batch

| workload | arm | instructions | cycles | IPC |
|---|---|---:|---:|---:|
| census 927 KB | QBE | 112.3 M | 28.8 M | 3.90 |
| | LLVM O2 | **76.1 M (−32%)** | 25.4 M (−12%) | 3.00 |
| | Zig | 19.4 M | 5.2 M | 3.70 |
| render 927 KB | QBE | 169.7 M | 44.3 M | 3.83 |
| | LLVM O2 | **126.0 M (−26%)** | 40.6 M (−8%) | 3.11 |
| | Zig | 22.7 M | 6.8 M | 3.34 |
| census 7.42 MB | QBE | 952.2 M | 274.9 M | 3.46 |
| | LLVM O2 | **662.1 M (−30%)** | 247.7 M (−10%) | 2.67 |
| | Zig | 155.0 M | 41.1 M | 3.77 |
| render 7.42 MB | QBE | 1411.2 M | 412.4 M | 3.42 |
| | LLVM O2 | **1061.7 M (−25%)** | 382.4 M (−7%) | 2.78 |
| | Zig | 181.6 M | 52.3 M | 3.47 |

### Compiler cost and size

| arm | cold build | rebuild | executable |
|---|---:|---:|---:|
| QBE | 5.93 s | 5.94 s | 1 361 632 B |
| LLVM O2 | 12.09 s | 12.09 s | 1 307 768 B |
| LLVM O3 | 12.08 s | 12.07 s | 1 307 768 B |

The LLVM arm costs about 2.05× the QBE arm's build time for the whole closure
(66 units; the driver still runs one translator process per unit and still
assembles and links exactly the same way). Its executable is 4% smaller.

## 4. Reading the result

**The speedup is real but small, and the counters say why.** LLVM removes a
quarter to a third of retired instructions (25–32%) and yet buys only 5.4–8.9% of
wall time. IPC falls on every workload (3.90 → 3.00 on the census, 3.46 → 2.67 on
the large census), so the instructions removed were the cheap, parallel ones and
the remaining ones are more serialized — what a program whose cost has moved to
memory looks like. Cycles fall far less than instructions (7–12%), and halving the
instruction count again would not reach 2× while cycles move that little.

**Where LLVM does better, concretely.** For `is_digit`, the QBE arm compares twice
and materializes two 0/1 longs:

```asm
	cmpq	$48, %rsi
	setge	%cl
	movzbq	%cl, %rcx
	cmpq	$57, %rsi
	setle	%al
	movzbq	%al, %rax
```

The LLVM arm collapses the pair into one range test:

```asm
	addq	$-48, %rsi
	xorl	%eax, %eax
	cmpq	$10, %rsi
	setb	%al
```

That is the LLVM arm's advantage throughout: it sees through the two comparisons
the frontend emits for `48 <= c` and `c <= 57`. It is a code-generation win on
code that is not the bottleneck.

**Where the time actually is.** The unchanged runtime fraction is visible in the
ratio: the guest is 4.3–6.0× Zig, and the runtime is identical between arms, so
even a large guest-side win yields a modest end-to-end improvement. The instructions
removed are 25–32%; the runtime work is not touched by either backend.

**No `nsw`/`nuw`/fast-math** and no `inbounds` were emitted, exactly as the plan
requires: the frontend emits its own overflow, bounds and cast checks, and the
translator must not introduce undefined behaviour ahead of them. This is one
candidate for the residual guest-side gap, and it is a frontend/representation
change, not a backend one.

## 5. Limitations

* **Per-unit optimization.** The tool sees one unit at a time, so it cannot inline
  across guest functions. Whole-guest-module LLVM optimization is a separate arm
  needing a manifest-aware build path.
* **Aggregate call boundaries are the arm's own convention**, not the target's C
  ABI: the IL passes an aggregate argument as the address of the temporary, and the
  arm takes that address in a register. Both ends of the comparison are built from
  the same IL, and the guest never crosses a C boundary itself (the generated entry
  point hands it only the context pointer and capability words), so the comparison
  is unaffected — but an LLVM-arm object is not a drop-in replacement for a QBE-arm
  object.
* **`perf stat` perturbs short runs** (a 9.7 ms census measures 23.5 ms under it),
  so wall time and counters are collected in separate matched batches, per §8.5 of
  the plan.
* The workloads are the sexpr census and rendering on 927 KB and 7.42 MB. They do
  not establish schematic-layout performance.

## 6. What to do next

The measurement supports the plan's third threshold — "a result inside noise or
<10% speedup, after translator-quality checks, supports prioritizing representation
and runtime work for this lowering" — and the translator-quality checks were done:
the emitted IR promotes cleanly (the optimizer reduces 27 temporary slots to the
one source allocation in `is_digit`), nothing is left as an unresolved
pointer/integer cast in the hot loops, and the remaining gap is not a code
generation artefact. So: **prioritize representation and runtime work.** Concretely, the evidence points at:

1. **Object count and collection pacing**, not copies: LLVM cannot remove work the
   IR never contains, and the census allocates 1 392 stack slots and calls the heap
   32 times for a 927 KB input.
2. **The integer/pointer model.** Every `l` is an `i64` address in this IL, and
   every memory access is an `inttoptr`. A typed representation would let a backend
   use real pointers, `getelementptr` and TBAA — that is a frontend change with a
   measured ceiling, and this experiment is what makes the ceiling interesting.
3. **The runtime fraction**, which is identical in both arms and therefore sets
   the floor on any end-to-end ratio.

A second backend is not supported by this evidence: it costs 2.05× the build time
and 25–32% of the instructions to buy 5.4–8.9% of wall time.

## 7. Reproduction

```sh
cd /home/epentland/ai/canopy/mylang
python3 -B experiments/llvm-backend/verify_units.py /tmp/census-manifest.json
python3 -B experiments/llvm-backend/verify_semantics.py --work /tmp/vs --json /tmp/vs.json
python3 -B experiments/llvm-backend/measure.py --work /tmp/measure --rounds 31 \
  --json experiments/llvm-backend/evidence/measure.json
```

Requires `/tmp/rt2x/input.sexp` and `/tmp/rt2x/input8.sexp` (927 415 and 7 419 320
bytes; SHA-256 recorded in the evidence JSON). The Zig reference is built on demand
from `experiments/sexpr-port/zig-bench`.
