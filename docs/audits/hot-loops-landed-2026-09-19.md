# Register-resident hot loops: what landed and what it measured — 2026-09-19

The landing report for `hot-loop-plan-2026-09-19.md`. That note priced a ladder of
counterfactual IL rewrites and ordered them so each stage could be measured on its
own; this one records which stages landed, what each was worth on the census, and
the one item that was measured and rejected. Every number is `perf stat` or an
interleaved wall-clock harness on this checkout, `taskset -c 6`, the 927,415 byte
EDA input, minimum of the stated runs, with the program's output compared
byte-for-byte against the baseline for every variant.

The machine ran a concurrent experiment throughout (`experiments/cascade/`, load
average 4–6 on 20 cores), so absolute times and cycle counts drift between
batches. Instruction counts are load-independent and are the primary measure;
cycle and wall ratios are only comparable inside one batch, and each table below
is one batch.

## 1. The ladder, measured as each stage landed

| census variant | instructions | ÷ Zig | Δ baseline | cycles | ÷ Zig | Δ baseline |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline (`d14ea1a3`) | 228,595,708 | 9.98× | — | 65,112,879 | 8.10× | — |
| + value-carrying roots (stage 1) | 206,981,054 | 9.04× | −9.5 % | 59,076,467 | 7.35× | −9.3 % |
| + loop-budget inlining (stage 2) | 181,059,053 | 7.91× | −20.8 % | 54,543,778 | 6.79× | −16.2 % |
| + load elimination twice (stage 3) | 176,832,124 | 7.72× | −22.6 % | 53,550,041 | 6.66× | −17.8 % |
| + cold-path positions (stage 4) | 163,378,558 | 7.13× | −28.5 % | 50,877,432 | 6.33× | −21.9 % |
| + no dead sticky trap test | 160,596,918 | 7.01× | −29.7 % | 51,076,649 | 6.36× | −21.6 % |
| Zig `ReleaseFast` (frozen `zig-bench`) | 22,899,740 | 1.00× | | 8,037,217 | 1.00× | |

The plan's counterfactual ladder predicted 207.5 M / 59.3 M for value roots,
181.7 M / 56.1 M with `advance` inlined, 177.5 M / 55.0 M with the second load
elimination, and 162.7 M / 53.1 M as the position-store upper bound. The landed
code reproduces every row within a percent except the last, where it is better on
instructions and level on cycles: the peephole in §3 removed the dead sticky-trap
tests the counterfactual had kept.

Wall clock, minimum of 40 interleaved runs, `/bin/true` 0.952 ms and Zig 2.933 ms
under the same harness in that batch:

| variant | wall | reported ratio | compute-only ratio |
| --- | ---: | ---: | ---: |
| baseline | 17.061 ms | 5.82× | 8.13× |
| value roots | 15.791 ms | 5.38× | 7.49× |
| value roots + inlined + loadopt twice | 14.545 ms | 4.96× | 6.86× |
| landed (all stages) | 13.936 ms | 4.75× | 6.55× |

Two later batches put the same pair at 17.909 → 14.740 ms (5.65× → 4.65×) and
19.246 → 16.400 ms (5.73× → 4.88×), so the wall improvement is 15–18 % against a
plan estimate of 12.6 %; the absolute ratio is a property of the batch, not of
the code.

## 2. What each stage is

- **Stage 1 — value-carrying roots**, `QBE-ROOTS-2`. A `myl_native_root` record
  gained the fourth word the plan specified (`src/native_heap.h`, with the layout
  frozen by two `_Static_assert`s in `src/qbe_runtime.c`). A push now reads the
  local or operand slot into that word and points the traced address at the copy,
  so no root push takes a slot's address and QBE promotes the scalar slots that
  carry the loop. Aggregate roots keep the address form — the collector walks
  their storage rather than reading a value — and a traced one-word local is now
  cleared with `storel 0, %l{n}` instead of a `memset` call that would take the
  address anyway (`zeroTracedLocal`, shared with the arena epilogue). The
  collector is unchanged: it still reads the traced pointer through `address`.
- **Stage 2 — loop-aware inline budget**, `BYTECODE-INLINE-3`. The flat budget
  stays at 48 instructions; a callee up to 64 instructions may also be inlined
  where the call site falls inside a loop of the caller. `loopBody` marks the
  contiguous pc range ending at each backward branch (the lowering is structured,
  so that range is the loop), and `inlineTarget` requires the mark for a callee
  over the flat budget. `advance` (52 instructions) is spliced into the scan
  loops and its cold call sites keep their call.
- **Stage 3 — load elimination twice**. `vendor/qbe/main.c` runs
  `fillalias; loadopt; filluse` a second time, because one pass only sees the
  alias information computed before it, and a load it replaces leaves later loads
  through the replaced value's own address with a stale alias base. Three lines;
  it changes code generation for every guest, so it was gated on the full suite
  plus the differential trap check.
- **Stage 4 — positions on the cold path**, `QBE-POSITION-2`. `sinkPositions`
  moves an instruction's frame-position store from the top of its body to the
  front of each `myl_qbe_fail_*` call in it. A body naming any other call keeps
  its store at the top, because a callee, runtime helper or provider can trap on
  its own and the trace then reads this frame's position. Every pc a trace,
  `assert` message or frame-limit report can name is the pc the store named
  before. A build with step accounting is untouched: the budget check can fail at
  any instruction.
- **The dead sticky-trap test**, `QBE-STICKY-1`. The test after an instruction is
  now emitted only when its own body can leave `ctx->trap` set and fall through.
  A guest call can return with the trap set (its failure path unwinds through its
  own epilogue), and so can a runtime helper that reports failure by return value
  (`myl_qbe_int_binary`, `myl_qbe_int_cast`, a provider read). A body that only
  names `myl_qbe_fail_*` helpers, or whose every call is followed by the
  `jmp @failure` that unwinds it, cannot — so a widening cast, an inline range
  check and an inline overflow check carry no `loadl %trap` anymore. This is
  stage 1b's second item, and it is worth more than the plan expected: it is
  2.4 % of the census and 12.4 % of the scan loop in instructions.
- **Stage 0 — a symbolised build**, `QBE-SYMBOLS-1`. `mylang build
  --keep-symbols` drops the linker's `-s` so `perf report` can attribute samples
  to guest functions. The flag rides in the existing build-argument scan, so the
  frozen `Options` field set does not grow for a measurement switch.

## 3. The item that was measured and rejected

Stage 1b's first item — giving every remaining operand address-take
(`%v =l copy %s{k}`, 109 sites on the census: `myl_native_equal`,
`myl_native_list_append`, renderer operands, record-constructor barriers) its own
entry-block scratch — **was not landed**. The counterfactual is
`evidence/hot-loops/operand_scratch.py`, and it measures 164.31 M instructions
against 163.40 M for the compiled form, +0.6 %: the extra load and store per site
costs more than unpinning the operand slots those sites use, on this workload.
The plan's own note that the sites "are not in the tokenizer's hot functions" is
what predicts this, and the measurement confirms it.

That counterfactual also found a QBE hazard worth recording, because it is
invisible until it faults: **an `alloc8` outside the entry block is not a slot.**
`seladdr` assigns frame slots and deletes alloc instructions only in the start
block (`vendor/qbe/amd64/isel.c:893-905`), so any other `alloc` reaches `salloc`
(`vendor/qbe/util.c:542-565`) and lowers to a dynamic `subq %rsp` with a fresh
address on every execution — inside a loop, a stack walk down to the guard page.
The first version of the script emitted the alloc at the site and segfaulted on
the census; the committed version declares the scratch in the entry block. Any
future per-site scratch must do the same.

## 4. Stage 5: the profile, and why field caching is not next

`mylang build --keep-symbols` plus `perf record` on the landed census, ten runs,
822 samples:

| symbol | what it is | overhead |
| --- | --- | ---: |
| `myl_f_22a60c4d…` | `sexpr.tokenizer::read_string` | 16.3 % |
| `myl_f_54d5bf28…` | `sexpr.tokenizer::tokenize` | 14.4 % |
| `[k]` | kernel | 6.4 % |
| `myl_f_2e34b709…` | `sexpr.parser::parse_list` | 5.8 % |
| `myl_native_text_from_utf8_checked` | UTF-8 validation of every `str` | 5.6 % |
| `myl_f_8eb428ca…` | `sexpr.parser::parse_node` | 3.5 % |
| `trace` | collector marking | 3.5 % |
| `myl_f_cab2aecf…` | `sexpr.tokenizer::is_atom_continue` | 2.7 % |
| `myl_native_list_append` | | 2.7 % |
| `myl_f_c7216ff8…` | `sexpr.tokenizer::read_atom` | 2.7 % |
| `memmove` | | 2.7 % |
| `myl_native_heap_alloc_at` | | 2.5 % |
| `myl_native_heap_collect` | | 2.0 % |
| `myl_f_3edf7935…` | `main::tally` | 1.6 % |
| `myl_f_b6931256…` | `sexpr.tokenizer::lexeme` | 1.4 % |
| `myl_native_heap_destroy` | teardown | 1.4 % |

The two tokenizer loops are 31 % between them and the per-token work around them
— `lexeme`, `is_atom_continue`, `list_append`, UTF-8 validation — is another
12 %; allocation, marking and teardown are 9 %. **Field traffic through class
pointers is not visible as its own cost**, which is what the plan's §1 already
measured from the other direction (a hand-written register-resident `advance`
is worth 0.8 % of instructions and no cycles). The next pass is the per-token
one the plan named in "what this plan does not reach": `lexeme` allocates twice
and validates UTF-8, and every `Token`/`Span`/`Result` is a stack aggregate
blitted through `%agg{pc}`.

For the record, the plan's option 2 — caching scalar fields in promotable slots
per `(local, field)` — remains unbuilt, and this profile is the evidence that it
should stay that way until the per-token work is done.

## 4a. The per-token pass, and what it measured

Following §4's own list, `lexeme`'s double allocation was the first item. On this
census every token text cost two heap objects: `src[start:end]` copied the byte
range into a fresh `bytes` (`myl_native_bytes_slice`) and `.decode()` then
widened that copy into a `str`. A counter pinned the shape: 53,135 allocations
and 15.2 MB per run, of which 11,056 were `bytes` (element size 1, 2.6 MB) and
11,082 were the `str` points (element size 4, 3.6 MB) — 42 % of all allocations
and 41 % of the bytes were that intermediate copy. The allocation histogram (by
element descriptor, 72-byte `list` headers separately) is in
`evidence/hot-loops/`.

`QBE-DECODE-RANGE-1` removes it: `src[a:b].decode()` lowers to
`myl_qbe_bytes_decode_range`, which clamps the endpoints and validates and widens
the source range in place. The fusion fires only when the slice's value is stored
into a temporary whose only reader is the `.decode` two instructions later and no
branch enters either instruction; the emitter leaves a null byte string in the
slot the slice would have filled, so the store that follows and any root push
over that slot still see a traceable value. Everything else keeps the slice.

The second item was the UTF-8 conversion, which took two passes. The first was
its high-bit scan: `ascii()` in `src/native_text.c` looked one byte at a time,
the only part of an ASCII conversion that touches every input byte, while the
widening loop beside it was already vectorised by LLVM; it now scans a word at a
time with the usual SWAR mask. The second was the fallback itself: any input with
one high-bit byte sent the whole buffer through the branchy per-byte decoder
twice. On this census 585 of the 5,145 quoted strings contain a high-bit byte and
they hold 69 % of the string bytes, yet their code-point count is within 0.5 % of
their byte count — so the fallback was decoding nearly all-ASCII text one byte at
a time. Both fallback passes now skip ASCII runs a word at a time and call the
decoder only around a multi-byte sequence, validating the same bytes in the same
order. That one is worth **−5.5 % of the census**, more than the whole of stage 1.

The third item was the aggregate path, and it is largely a copy cost: a managed
`list` element is copied on every `append`, `get`, `set` and `pop`, and those
copies went through a `memcpy` call. `copy_element` switches on the element size
so the compiler inlines the word, record and node-sized moves the language
actually uses — `Token` is 40 bytes, `Node` 56, a `Span` 24, and the switch covers
all three. The same change made `myl_native_list_append` take a fast path when the
list already has room: nothing can allocate there, so nothing can collect, and
neither root record the call used to push is needed.

What is left of the aggregate traffic is the `%agg{pc}` scratch itself: 164
pointer reads of a per-pc aggregate slot and 130 `blit`s (4,140 bytes of copies in
the whole program, executed once per node or token). Making those cheaper needs
the constructor to write into its destination instead of a scratch the next
instruction copies out of, and the copy that dominates is the `match` arm binding
the payload into a local before the append — eliding it is payload forwarding, not
a local rewrite, and the two blits it would remove measure under a percent.

| census variant | instructions | ÷ Zig | Δ round | cycles | ÷ Zig | Δ round |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| committed `5b2da1d3` | 144,608,940 | 6.31× | — | 45,575,638 | 5.62× | — |
| + mixed-text decode | 136,770,600 | 5.97× | −5.4 % | 44,438,255 | 5.48× | −2.5 % |
| + list fast path | 133,908,591 | 5.84× | −7.4 % | 43,246,745 | 5.33× | −5.1 % |
| + inlined element copies | 133,267,929 | 5.81× | −7.8 % | 43,506,192 | 5.37× | −4.5 % |
| Zig `ReleaseFast` | 22,924,822 | 1.00× | | 8,106,429 | 1.00× | |

Against the session's starting point (`d14ea1a3`: 228.6 M / 65.1 M) the census
now sits at **−41.7 % instructions and −33.2 % cycles**, or 5.81× / 5.37× Zig.

The instruction profile after the fusion moved as the allocation histogram
predicted: `myl_native_heap_alloc_at` fell from 11.6 % to 2.3 % of instructions
and the copy helpers (`memmove`, `memcpy`) from 8.4 % combined to 1.5 % and out of
the top list, while the two tokenizer loops rose to 26.3 % and 23.5 % — they are
now half the program, and what is left in them is the per-byte work §3 describes.
After the runtime work the next symbols are `parse_node` 5.1 %, `parse_list`
4.9 %, `is_atom_continue` 3.6 %, then the collector: `trace` 3.4 %, `cfree`
2.5 %, `heap_collect` 1.6 %.

Still open from §4's list, in the order they now measure: the tokenizer loops
themselves (≈50 % of instructions, where each byte reloads `len(lx.src)` three
times and the byte itself twice — the loads are separated by branches, which is
what QBE's block-local load elimination cannot cross, and the only fix is proving
that a named class instance and a managed list cannot alias each other), then
the aggregate traffic that survives the small-copy inlining, and the frame record
each remaining call pays.

## 5. Where the scan loop stands against the 1.5× floor

The plan's §3 floor study is unchanged and was reproduced: a hand-written QBE IL
implementation of the same `scan` loop with every mylang check kept measures
**1.50×** the scalar Zig control in cycles in a clean batch (1.73× in a loaded
one), and 1.21–1.47× with no checks. In instructions, one interleaved batch
(minimum of eleven runs) gives:

| `scan` (927 KB, same output) | instructions | ÷ Zig | cycles | ÷ Zig |
| --- | ---: | ---: | ---: | ---: |
| Zig scalar control (`zigctl/scan_scalar.zig`) | 7,948,060 | 1.00× | 2,901,665 | 1.00× |
| hand-written QBE IL, no checks at all | 12,908,817 | 1.62× | 4,277,821 | 1.47× |
| hand-written QBE IL, every mylang check kept | 18,517,731 | 2.33× | 5,023,735 | 1.73× |
| compiled today (`mylang build e_scan.my --mode ReleaseFast`) | 39,386,731 | 4.96× | 9,642,672 | 3.32× |

So the compiled loop moved from the plan's 6.2× / 4.3× (measured against the same
scalar control) to 4.96× / 3.32×, and the emitted-IR gap to the checked floor is
still about 2.1× in instructions. The remainder in this loop is not the root
protocol: `e_scan` allocates nothing in its loop, so stages 1, 2 and 4 are inert
there, and the −12.4 % it did get came from the sticky-trap peephole. What is
left is duplicate work the hand-written IL does once — each of the two
`source[index]` reads in one condition reloads the receiver, its length and the
index and redoes the bounds check, and the loop's overflow-checked increments
recompute their operands — which is a bytecode-level redundancy question, not a
backend one.

## 6. Verification

- **Differential trap check.** `evidence/hot-loops/trapdiff/` builds twenty trap
  programs with the baseline worktree and with the landed compiler and compares
  stdout, stderr and exit status across six build/run modes and five `mylang run`
  modes: 202 comparisons, 0 mismatches. It caught a real defect during landing:
  the first `stickyTrap` predicate cleared its state on the trailing empty line,
  so every guest call lost its sticky test and a trap returned from a callee
  silently continued in its caller. Positions and trap traces were the only
  visible difference, which is why the harness compares them byte for byte.
- **Full gate.** `zig build test --summary all` (58/58 steps; 1,307 selected
  tests passed, guardian included), `zig build test-qbe`, `zig build test-qbe-build`,
  `zig build fmt-check`.
- **Collector stress.** `mylang test tests/lang --gc-stress` (213 passed) and
  `mylang test experiments/sexpr-port --gc-stress` (79 passed); the census prints
  byte-identical output under `--gc-stress`.
- **Fused decode.** `tests/lang/python_bytes.my` gained an executed case for a
  decoded slice — a multi-byte code point, clamped endpoints, a reversed range
  and invalid UTF-8 — and `src/qbe_test.zig` pins the lowering: the fused call
  for the in-place form, and the slice kept when the temporary has another
  reader.
- **Port goldens.** `experiments/sexpr-port/golden_compare.py` 17/17 byte-identical,
  `compare.py` agrees with the Python reference reader on all four fixtures.

## 7. Reproduce

```sh
# build the census and the scan benchmark
cd experiments/sexpr-port
../../zig-out/bin/mylang build main.my -o /tmp/census --mode ReleaseFast
cd ../sexpr-audit
../../zig-out/bin/mylang build e_scan.my -o /tmp/scan --mode ReleaseFast

# instructions and cycles, interleaved, minimum of N
taskset -c 6 perf stat -e instructions,cycles -- /tmp/census /tmp/sexpr-bench/input.sexp
taskset -c 6 perf stat -e instructions,cycles -- /tmp/zb-out/bin/zig-bench /tmp/sexpr-bench/input.sexp

# the scalar Zig control the scan ratios are quoted against
cd experiments/sexpr-audit
zig build-exe -OReleaseFast -femit-bin=/tmp/zig-scan-scalar zigctl/scan_scalar.zig

# a symbolised profile
cd experiments/sexpr-port
../../zig-out/bin/mylang build main.my -o /tmp/census-sym --mode ReleaseFast --keep-symbols
taskset -c 6 perf record -F 5000 -e cycles:u -o /tmp/census.perf \
  sh -c 'for i in 1 2 3 4 5 6 7 8 9 10; do /tmp/census-sym /tmp/sexpr-bench/input.sexp >/dev/null; done'
perf report -i /tmp/census.perf --stdio --sort symbol

# the differential trap check
cd experiments/sexpr-audit/evidence/hot-loops/trapdiff
MYLANG_BASE=<baseline compiler> MYLANG_NEW=../../../../../zig-out/bin/mylang python3 run.py
```
