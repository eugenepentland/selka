# LLVM O3 versus Zig: language and ABI parity audit

2026-09-20. Source inspection at `b8f6ec3f`, plus isolated experiments on the
**exact 101-function whole-O3 arena closure used by the supplied chart**.
Evidence: [llvm-parity-audit-20260920](../../experiments/llvm-parity-audit-20260920/README.md).
No production compiler, runtime, language, or benchmark source was changed.

**There is substantial recoverable overhead, but parity is not demonstrated.**
The first issue is in the experiment: its supposedly root-free guest still
constructs thousands of GC root records. Removing those dead stores and replacing
three allocating width helpers reduces large render time by **32.6%**, from
48.93 ms to 32.96 ms, against Zig's 16.54 ms in the same batch. Census improves
from 22.23 ms to 20.35 ms against 12.81 ms. These are **1.59× census and 1.99×
render**, with another **37.1% and 49.8%** of their respective times to remove
for exact parity. The render ratio's 95% interval is **[1.95, 2.03]**; this is
approximately 2×, not a statistically established below-2× result.

The most useful language work is an allocation-free range/view representation
and complete width/format APIs. The most useful ABI work is retaining pointer,
effect, and lifetime facts through lowering, constructing results directly in
their destination, and specializing collection access. Merely making guest
functions private, or adding an attribute to one helper, does not close the gap.

Section 6 merges a second audit from the same day and the same working tree
that asked a different question: not how fast the output runs, but how many
turns an agent loses producing it. Its answer is that the compile/run/test loop
is already far from the bottleneck, and that the cost sits in four first-try
rejections that did not say what to write instead. The fixes for those landed
in the tree the same afternoon and are measured there.

## What the chart measures

The saved chart medians are 24.46/14.67 ms for census and 51.90/18.46 ms for
render: **1.67× and 2.81×**. Reaching parity requires roughly **40% and 64%**
less time, respectively. A 2× target is materially easier than parity.

The chart's O3 binary is `armsset/maxperf/whole-o3.bin`, not `compact-o3.bin`.
It retains ordinary object headers, uses a noncollecting invocation arena,
removes various failure/diagnostic paths, and merges guest functions into one
O3 module. Runtime C remains separately compiled at O2; the formatter remains
a separate native object. Thus this is neither an O2-versus-O3-only comparison
nor production checked mylang versus Zig. The earlier headerless-arena
`buffer_frozen` bug does **not** invalidate this chart's header-retaining arm.

The chart's build panels measure separate-unit QBE/LLVM builds. They do not
establish incremental build cost for the whole-module arena O3 configuration.

The current tree already has `u32` source spans, `byte_buffer`, byte views,
direct float append, a capacity fast path before buffer rooting, aggregate
parameter addressing, payload projection, and limited constructor forwarding.
Those are not missing features to propose again. The remaining limitations below
were checked against their implementations.

## Fresh measured results

All rows below belong to one **21-round randomized interleaved batch**, pinned to
CPU 6, after three warmups. Each process reads the same 7,419,320-byte input;
timed stdout goes to `/dev/null`. Full output, stderr, and exit status are checked
before/after timing, with status/stderr checked during timing. The benchmark
includes process launch and I/O. Counters are separate matched runs, not taken
from wall-time runs. Shared-machine timings can vary; do not subtract times
across batches.

| Variant | Census ms | Render ms | Render / Zig | Render instructions |
|---|---:|---:|---:|---:|
| Regenerated chart control | 22.23 | 48.93 | 2.96× | 360.41 M |
| Remove private root-record stores | 20.24 | 40.41 | 2.44× | 249.72 M |
| Root cleanup + width helpers | 20.35 | 32.96 | 1.99× | 225.86 M |
| Only describe heap getter's effects | 22.18 | 47.56 | 2.88× | 355.93 M |
| Zig reference | 12.81 | 16.54 | 1.00× | 181.60 M |

The regenerated control's **unoptimized LLVM IR is byte-identical to the
retained chart IR**. Runtime archive, formatter, entry, metadata, allocator,
optimization level, and linker recipe are shared by these probes. This avoids
attributing later compiler/source improvements to the diagnostic changes.

A preceding independent batch isolated two other changes:

| Single change against its 50.47 ms render control | Render ms | Reduction | Control / variant, 95% interval |
|---|---:|---:|---:|
| Internalize 100 non-boundary guest functions | 49.69 | 1.5% | 1.016× [0.999, 1.033] |
| Replace three width helpers | 43.17 | 14.5% | 1.169× [1.154, 1.200] |
| Both | 42.13 | 16.5% | 1.198× [1.183, 1.223] |

Internalization alone did not resolve a render improvement; large census improved
about 3%. This does not test runtime LTO, typed pointer arguments, result
forwarding, or a different collection representation.

## 1. Fix the arena benchmark's incomplete root elimination first

[`unchecked.py::_strip_arena_roots`](../../experiments/llvm-backend/maxperf/unchecked.py)
removes root-head stores at `heap + 16` and replaces the root-mark call. It leaves
the private root records' `previous`, `address`, `type`, and inline pointer-value
stores. LLVM does not eliminate all of this integer-addressed graph.

This is present in **optimized machine code**, not just a count of dead input IR:

- `push_node` contains **414 descriptor-address stores** in optimized LLVM IR.
- Its machine-code body is **19,380 bytes**, reserving 1,256 stack bytes, before
  root cleanup; afterwards it is **1,338 bytes**, reserving 424 stack bytes.
- Removing only stores to proven private root slots eliminates **4,580 static
  store sites** across the closure. Root-clean render retires **110.69 M fewer
  instructions** and takes **17.4% less wall time**. Census takes **8.9% less**.

The diagnostic parses the frozen QBE units and checks root allocation sizes,
field offsets, unique definitions, and allowed uses before removing these stores.
The original translator is unchanged. Remaining useless allocations and address
calculations are left for LLVM to eliminate.

**Production implication:** make collecting versus noncollecting execution an
explicit lowering contract, and eliminate root operations before lowering them
to ordinary memory writes. In collecting builds, keep roots at actual safepoints
and exploit the existing collection/effect analysis. Never apply this arena-only
removal to a collecting heap. For a safe document-arena feature, ownership,
escape, retention, memory-budget, and release rules still require design.

The chart should describe this arm as having **root publication removed**, not
all rooting work removed, until the experiment is corrected and requalified.

## 2. A zero-copy byte view still allocates; make ephemeral ranges allocation-free

[`native_bytes.c::myl_native_bytes_view`](../../src/native_bytes.c) allocates a
managed list-shaped descriptor for each view and retains the backing block.
[`qbe_bytes.zig`](../../src/qbe_bytes.zig) emits that allocation for `.view`,
followed by a separate scalar-count or numeric-parse operation.

Consequently `source.view(start, end).scalar_count()` avoids copying the content
but **does allocate a view header**. A fresh `noalloc` probe against the installed
compiler rejects this composition with `E_EFFECT_BOUND`; source inspection
identifies the view allocation. Error construction in the checked scalar-count
bridge can also allocate a string, so an all-input `noalloc` API needs a
nonallocating error representation as well.

The width probe substitutes just three existing guest helpers:

- `scalar_len`: clamp endpoints, count/validate UTF-8 directly over the range,
  retain the existing zero fallback on invalid text, and create no view object.
- `literal_width`: count scalars directly, preserving the empty-width fallback.
- `int_width`: count signed decimal digits without formatting an allocated string,
  including `INT64_MIN`.

These substitutes call the existing scalar-count runtime and retain Unicode
scalar semantics. They are a diagnostic bundle: **14.5% is their combined
render saving**, not an attribution to view allocation alone. The C helpers are
separately compiled, so this improvement does not depend on inlining them.
They intentionally do not preserve allocation-failure accounting in the arena
experiment, and are not production patches.

**Recommended language/library contract:** an owner-retaining `ByteView` value
with range/length, or lowering that fuses a nonescaping view with its immediate
consumer. Keep a managed owner reachable for as long as any derived address is
used. Do not silently make a escaping interior pointer safe merely by retaining
its numeric address. Views, views of views, literals, empty/reversed ranges,
growth through permitted aliases, and GC stress all need coverage.

Provide range-based scalar counting, equality, integer/float parsing, and
append/write operations; specify nonallocating invalid-input results. Float
width should use the same formatter into caller-owned scratch as direct append,
without `str(float)` plus slicing. The current `decimal_width` and `measure_width`
still allocate; their isolated benefit is unmeasured here. Explicitly decide
whether eliminated temporary allocations should cease charging allocation budgets.

Do not replace scalar width with byte length: the mylang printer's Unicode
layout contract is not identical to Zig's byte-width convention for every input.

## 3. Carry real type and effect information across the ABI

There is a concrete information loss between the new aggregate parameter
optimization and the LLVM adapter:

1. [`qbe.zig::argumentType`](../../src/qbe.zig) spells copyable aggregate
   arguments as `l`, the same QBE type used for 64-bit integers.
2. The adapter's pointer-origin analysis seeds aggregate-typed parameters,
   allocations and known pointer-returning runtime calls. An ordinary `l`
   parameter does not carry the aggregate-pointer fact.
3. Guest definitions consequently take `i64` for context, aggregate addresses,
   and ordinary scalar values. The frontend also transports floating values as
   integer bits. Pointer arithmetic/type/effect facts must be reconstructed from
   lower-level code or are unavailable.

LLVM can remove many casts, and a cast count is not a cost measurement. The
limitation is loss of alias, object-relative address, alignment, and memory-effect
facts. LLVM's own [frontend guidance](https://llvm.org/docs/Frontend/PerformanceTips.html#other-things-to-consider)
recommends sparse pointer/integer conversion and GEP address arithmetic.

**Recommended implementation:** extend the native manifest/signature sidecar
with semantic parameter/result kinds and proven properties. Lower LLVM guest
pointers as `ptr`, floats as native FP values where appropriate, and known
aggregate accesses as typed layouts plus GEPs. QBE can retain its existing
machine representation. This is a way to improve the experimental backend
without first committing to a wholly separate frontend.

Distinguish these independent facts: reads/writes memory; may collect; may trap;
may retain an address; mutates the argument's storage; mutates objects reachable
from that argument. `noalloc` does not imply purity, and a read-only local does
not make its reachable graph immutable or its pointer exclusive.

Do not sprinkle `noalias`, `inbounds`, overflow flags, or `readonly` onto all
arguments. Each needs a proof consistent with callbacks, aliases, value snapshots,
and the language's trapping behavior. The [LLVM attribute contract](https://llvm.org/docs/LangRef.html#parameter-attributes)
is a correctness condition, not a speculative optimization hint.

A small effect probe demonstrates the scale, without promising more: marking
the pure `myl_qbe_heap` address getter `memory(none) nounwind willreturn` saves
**2.8%** large-render wall time, with no resolved census gain. This helper only
returns the address of the context's embedded heap. Its opaque calls are common
in the printer, but annotating this one function is not enough for parity.

Separate stable host/FFI/callback boundaries from private release code. Preserve
external signatures and use internal specialization only inside a known closure.
Internalizing current integer-shaped guest functions alone had a small result;
better type/effect information and runtime visibility are separate work.
Version the changed ABI and hash signature/effect/layout summaries into caches;
do not reuse native-v5 artifacts across incompatible signatures.

## 4. Forward result destinations and specialize typed collection access

The existing aggregate parameter addressing is useful and already present.
The remaining issue includes aggregate results and collection snapshots:

- The frozen `parse_node`/`parse_leaf` return aggregate is **72 bytes**;
  `next_raw` returns **64 bytes**. The adapter already implements indirect
  returns with `sret`, so introducing indirect returns is not new work.
- [`ret_aggregate`](../../experiments/llvm-backend/llvm_emit.py) copies the
  materialized source aggregate into the return destination using `memmove`.
  Constructors, `Ok`/`Err`, `return`, and `?` should be able to fill the ultimate
  destination when ownership/evaluation facts permit it.
- The source-level record constructor optimization currently forwards into a
  suitable adjacent local; variant construction remains a separate path.
- The printer still calls `__wrap_myl_native_list_get`, which copies a node to
  caller storage, even in the unchecked arena arm. Generic collection helpers
  use runtime element descriptors; guest LLVM cannot see their implementations.

Try direct element projection or a short-lived address when no list mutation,
reallocation, callback, resource drop, or collection can invalidate the observation.
Keep actual snapshots where later mutations can be visible. A frozen sequence
of parsed children would make these facts easier to establish, but first price
a library/application prototype against the existing list API.

Measure optimized copies/frame sizes and an isolated wall comparison. Static
`blit` counts are investigation pointers, not executed bytes or speedups. Do not
attribute the old printer's huge body solely to aggregate copying: this audit
demonstrates that residual root records were a major part of it.

## 5. Give LLVM visibility into small runtime operations, then improve the scanner

Whole-module guest O3 still calls separately compiled O2 runtime code. It cannot
generally specialize those calls for known element sizes, delimiters, or
noncollecting allocation. Consider typed LLVM fast paths or compatible runtime
bitcode plus release LTO. Keep allocation/growth/failure handling in cold helpers.
Preserve the C ABI for public boundaries and give checked and arena runtimes
distinct effect summaries.

ThinLTO supports an incremental cache, but this audit did not implement it or
measure its compile cost. Evaluate release runtime gains and build costs together;
the chart's warm separate-unit build timings are not an LTO measurement.
See [Clang ThinLTO caching](https://clang.llvm.org/docs/ThinLTO.html#incremental).

After root/width cleanup, profiles still point to the tokenizer, range scanner,
width counting, appends, and copy/allocation work. In particular,
[`myl_native_bytes_find_any`](../../src/native_bytes.c) builds a 256-bit membership
table and scans one byte at a time for multi-byte delimiter sets. `read_string`
repeatedly supplies the constant pair quote/newline. Test specialization for a
small constant set, a prepared scanner, or a bounded vector scan. Preserve exact
first-match, escape, newline, and end-of-input behavior. This needs no new SIMD
syntax in the language. Its speedup is **not measured** here.

After the two successful changes, large census retires **133.34 M instructions
versus Zig's 155.02 M**, yet consumes **52.63 M cycles versus 41.84 M**. Large
render retires **225.86 M versus 181.60 M**, with **87.81 M versus 52.00 M cycles**.
Thus both excess work and execution efficiency remain; instruction parity alone
will not establish runtime parity. Memory bandwidth, dependency chains, cache
behavior, and front-end stalls need processor-specific measurements before
declaring this memory-bound. The sampled profiles contain unattributed samples
and harness activity; they locate functions, not precise exclusive wall time.

## 6. The agent loop: what a session pays that the runtime does not

Source: an agent session on the installed `zig-out/bin/mylang` (built
2026-09-20 15:37 from the same dirty tree) that wrote four first-try programs,
ran the S-expression port's guest tests and timed a hot loop against CPython,
followed by the implementation ledger in
[`agent-usefulness-reports/ledger.md`](agent-usefulness-reports/ledger.md).
The packages themselves are specified in
[`agent-usefulness-implementation-plan-2026-09-20.md`](agent-usefulness-implementation-plan-2026-09-20.md).

### The loop is not where the turns go

| Action | Wall time |
| --- | --- |
| `check` on a 25-line single file | 80 ms |
| `run` on it (native build plus execution) | 414 ms |
| `mylang test experiments/sexpr-port/tests`, 114 tests across 7 programs | 4.0 s |
| Sieve to 5,000,000, `mylang build` output | 0.15 s |
| Same sieve under CPython 3.14 | 0.50 s |

Single-file timings on a warm cache; the sieve is one hot integer loop over a
`list[bool]` and says nothing about the printer workload above. The point is
the order of magnitude: an agent waits well under a second per edit, so the
runtime ratios in sections 1 to 5 are not what an agent feels while writing
the program. They matter once the program runs at scale.

### Where the turns go: rejections that do not name the alternative

Every repair round the session paid came from a Python habit meeting a small
surface difference. Every fix was one line.

| First-try spelling | What the installed compiler said | Turns lost |
| --- | --- | --- |
| `text.split()` | `E_ARITY: list method argument count does not match its signature`; the receiver is a `str` and no signature is shown | 1 |
| `union` cases on separate lines without commas | `E_SYNTAX: unexpected token; expected a dedent` at the second case | 1 |
| `import strings` at the top of a headerless script | `E_MODULE_HEADER: file must begin with a module declaration` | 1 |
| `b == strings.ord("m")` | `E_TYPE: expected int, found Result[int, strings.Error]` | 1 |
| `lambda w: -counts[w]` | `E_LAMBDA_CAPTURE` naming the fix (top-level function, explicit state parameter) | 0 |
| unused `x: int = 0` | `W_UNUSED_BINDING` naming the `_ =` idiom | 0 |

The two rejections that carried their fix cost nothing; the four that did not
cost a turn each. `mylang lint --profile=agent` on the port also reported
`L_UNTESTED_EXPORT` on accessors that tests reach only transitively, because
the rule counted direct callees of `test_` functions rather than the
reachability index `tests-for` already computes.

### What landed in the tree in response

Six workstreams implemented the small packages the same afternoon. The ledger
is the authority on their state; the numbers below are copied from it and, for
the four repair rounds, re-verified at the time of this merge against the
binary `zig build` installed green at 16:34 UTC (sha256 prefix `ff0ede1a`).

| Package | Change | Ledger evidence |
| --- | --- | --- |
| S1(a) | Python's no-argument `split()` on `str` | `a64_split_noargs.my` prints 42, matching CPython; was `E_ARITY` |
| S1(b) | Prelude `ord`/`chr`; `ord` of a one-scalar literal folds to an `int` and the runtime form traps `R_TEXT_SCALAR` | `chr(65), ord("m"), ord("m") == 109` prints `A 109 True`; re-verified: `ord("ab")` on a run-time value traps `R_TEXT_SCALAR` with exit 1 |
| S1(c) | A headerless script may import embedded standard modules | headerless `import strings` checks; a project import still reports `E_MODULE_HEADER` |
| D1 | Call-site rejections name the receiver, render the callee signature and carry an `alternative` note (`role` inside `diagnostic-v1`) | structured C3 0.000 → 0.114 on D1 and D2 alone; re-verified: `"a b".split(" ", 2)` now reports `` `str.split(separator: str) -> list[str]` takes 1 argument, but this call passes 2 `` with an `alternative` note describing both spellings |
| D2 | Parser hints for union/enum commas, bare `MAX = 42`, `def` in a `class`, `from` imports | each probe rejects with the accepted form as an `alternative` note; the union hint re-verified: "union cases are separated by commas / alternative: insert a comma after the previous case" |
| L1 | `untested-export` reads the shared reachability index; agent profile counts transitive reach, strict says "reached only transitively" | port fixture 22 → 8 findings, and the 8 equal `tests-for`'s zero-reach set; on the port's own `main.my` graph the count stays 42 before and after because that graph reaches no test (re-verified) |
| M1 | Opt-in `--friction-log` / `MYLANG_FRICTION_LOG` writing `friction-log-v1` lines, plus `velocity/friction/harvest.py` | a replay of this session yields exactly 4 rounds and 0 for the two self-fixing codes; no source or message text in the record |
| V0 | `velocity/score.py` scores lane C from `diagnostic-v1` | re-run on the frozen binary reproduces every recorded verdict across 110 probes |

Lane C of the idiom suite before and after, 110 probes, one detector:

| Metric | Frozen baseline | Current tree |
| --- | --- | --- |
| C1 first-try fidelity | 0.239 (16/67) | 0.254 (17/67) |
| C2 silent wrong answers (gate) | 0 | 0 |
| C3 rejections carrying a structured alternative | 0.000 (0/80) | 0.304 (24/79) |

Two corrections the ledger makes to the session's own claims: the port's raw
byte-code comparisons number 63 (29 letter codes), not the 33 a narrow `== NNN`
grep found; and the "ten transitively reached accessors" premise for L1 does
not reproduce on the port's own graph, which contains no tests, so L1's
acceptance was restated around a fixture that does. C3 did not reach the plan's
0.5 target: the remaining 55 rejections have no accepted spelling known at the
failure site, and reaching the target needs per-form coverage beyond D1 and D2.

Build state matters for reading those numbers. `zig build` gates its install on
a green Guardian run, and at the end of the implementation session's sixth
round the ledger listed three compile errors blocking that (in `src/sema.zig`,
`src/buffer_operations.zig` and `src/project.zig`), so its "after" numbers came
from a manually staged `mylang-current`. At the time of this merge the tree
builds: `zig build --summary all` reported 18/18 steps, Guardian's 88
diff-scoped checks passed, and the install at 16:34 UTC is the binary the
re-verifications above used. One earlier attempt in the same minute failed at
Guardian and installed nothing, so the tree was still moving; treat the green
build as a snapshot. The full `zig build test` gate and the lane C rerun with a
regenerated manifest have not been run on this build, so nothing in this
section has passed the full gate.

### Where the two audits meet

1. **`ord` is the source half of section 2's range work.** Byte-level guest
   code compared against raw integers because `strings.ord` allocates, returns
   a `Result` and carries `effects(managed_allocation)`, so it could not appear
   in `noalloc` code at all. The prelude fold is QBE-neutral by specification
   (`PRELUDE-SCALAR-3`): `code == ord("m")` emits the same instructions as
   `code == 109`. The runtime half, a view that allocates no header and
   range-based equality and parsing, is still section 2's work; only when it
   lands can the tokenizer's comparisons become range operations rather than
   folded scalars.
2. **The `noalloc` rejection in section 2 is a D1-class gap.** The probe
   composing `view(...).scalar_count()` was rejected with `E_EFFECT_BOUND`, and
   it took source inspection to learn that the view header was the allocation.
   An effect-bound rejection should name the operation that contributes the
   effect and which effect, from the per-operation facts the checker already
   has. This is not implemented and is the natural next D1 item, because the
   agents doing section 2's work will hit it on every attempt.
3. **Section 3 and F1 are the same principle.** Carrying real type and effect
   facts across the ABI, and reporting declared versus inferred effects
   honestly in `list-interfaces`, both expose facts the compiler knows with
   their provenance instead of a conservative mask. F1(a) is not started.
4. **Disjoint code, except two files.** The agent-loop packages touch the
   checker, parser, lint and CLI; the runtime work touches the QBE lowering and
   C runtime. S1(a) and S1(b) are the overlap: `native_text_methods.c` gained
   `split_whitespace` and `qbe_text.zig` the `text_ord`/`text_chr` operations,
   the same files section 2's width primitives will change. Sequence those
   edits or expect merge work.

## Recommended sequence and acceptance

1. Correct and requalify the arena root-elimination experiment. Preserve its
   distinction from the checked GC backend and regenerate the chart.
2. Implement nonescaping range-consumer fusion or a value `ByteView`, plus
   nonallocating width primitives. Confirm output, Unicode width, numeric
   boundaries, errors, budgets, rooting, and GC stress in the checked runtime.
3. Add typed ABI/effect summaries, starting with pointer parameters and reviewed
   small runtime helpers. Keep direct/indirect calls and host wrappers coherent.
4. Price result-destination forwarding and typed list access independently;
   compare runtime-bitcode visibility with explicit LLVM fast paths.
5. Specialize the fixed delimiter scanner and profile the remaining runtime.
   Consider immutable AST storage or region allocation only with evidence for
   their incremental benefit and a safe lifetime contract.

The agent-loop packages in section 6 run beside this sequence, not inside it.
They need no chart requalification; their gate is the lane C rerun with a
regenerated manifest plus the full `zig build test`, and their next item is the
effect-bound diagnostic named in section 6, which section 2's own work will
exercise. Land that before the range work starts so its implementers do not pay
the same inspection round.

Avoid spending the next cycle on generic field reordering, blanket inlining,
an unchecked language keyword, or replacing all records with classes. The
existing layout audit found no alignment-reordering savings for the inspected
parser population; the measured problems above are more specific.

For a practical parity gate, choose a tolerance (for example <=1.10× Zig across
representative inputs with reported uncertainty), while continuing to report
the exact 1.00× ratio. Freeze both toolchains, CPU target, sources, binary and
input hashes, output/error contracts, allocator mode, and raw round order.
Use independent schematics, Unicode width boundaries, escape-heavy data, and
deep trees. Require checked-GC results separately from arena results. The present
experiments establish promising mechanisms on one repeated-board workload;
they do not establish language-wide or checked-runtime parity.

The main valid-input gates passed **584/584**, **438/438**, and **146/146**
comparisons across the respective probe groups (the same corpus reused), plus
**110/110** focused integer/Unicode comparisons. These are focused diagnostic
checks, not a compiler-wide qualification. No Guardian gate was exercised.
