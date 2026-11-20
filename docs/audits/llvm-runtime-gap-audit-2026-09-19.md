# Why the LLVM experiment is still slow, and what to fix

19 September 2026. Compiler checkout `4919ea9f`; audit of the uncommitted adapter
in `experiments/llvm-backend`. This is a performance audit with isolated diagnostic
implementations, not a production backend change.

## Finding

**The 6% result understates LLVM's benefit because the adapter handicaps important
optimizations. Fixing those handicaps helps, but still leaves a large representation
and runtime gap to Zig.** The original result does not establish a QBE ceiling or
justify treating the translator-quality gate as complete.

I reproduced the existing instruction counts, inspected optimized LLVM IR and
machine code, profiled both binaries, and ran two new 31-round interleaved batches.
The combined diagnostic arm is **1.12–1.15× the existing LLVM control and
1.20–1.24× QBE**. Its runtime archive, entry, formatter and metadata are unchanged.
It still takes **3.45–5.44× Zig's time** in the second batch. Reaching 2× therefore
needs another 42–63% reduction, depending on workload.

Reproducible probes, raw observations, the frozen frontend manifest, verification,
profiles and source/tool hashes are in
[`experiments/llvm-backend/audit-20260919`](../../experiments/llvm-backend/audit-20260919/README.md).

## 1. The guest-code improvement was being partially cancelled by regressions

The initial explanation focused on shorter scalar predicates. The profiles show
something more actionable: large lexer improvements were offset by slower parser
and printer functions.

Sampled **self cycles per invocation of the entire 7.42 MB workload**, millions;
20 executions per profile, CPU 6, `cycles:u`, sampling period 200,000. These are
sampling estimates, not precise function timings. Totals include callees separately.

| Workload / function | QBE | Original LLVM | Combined probe |
|---|---:|---:|---:|
| Census: `read_string` | 45.76 | 31.33 | 28.39 |
| Census: `tokenize` | 43.65 | 27.93 | 26.79 |
| Census: `parse_node` | 11.07 | **17.53** | **8.10** |
| Census: `parse_list` | 12.61 | 13.88 | 7.32 |
| Render: `estimate_width` | 18.41 | **27.38** | **17.66** |

The unmodified LLVM adapter makes `parse_node` about 58% more expensive in the
census profile and `estimate_width` about 49% more expensive in the render profile.
The diagnostic fixes reverse those regressions. This is not evidence that all
remaining guest instructions are intrinsically expensive or unavoidable.

## 2. Concrete lowering defects and missed opportunities

### 2.1 Fixed scratch is being treated as dynamic stack allocation

`llvm_emit.py::on_alloc` preserves every QBE allocation's location. The frontend
puts aggregate scratch after the stack-admission branch, outside the entry block.
There are **211 constant-size allocations in 23 such blocks**, including **28 in
`parse_node`**. LLVM's optimized `parse_node` still has **35 allocations outside
entry**, including other aggregate temporaries.

The actual assembly repeatedly reads `%rsp`, subtracts another buffer size,
writes `%rsp`, and spills the new address. QBE also incurs dynamic stack work from
this lowering; LLVM additionally loses its normal opportunity to promote the
scratch to scalar values. The README's entry-slot argument applies to temporary
name slots, not to all the aggregate storage those slots point to.

**Fix:** classify function-lifetime scratch explicitly and allocate it in entry,
before calls. Keep truly dynamic and per-iteration allocations separate. Couple
this with physical-stack accounting: moving scratch changes the frame layout, so
the stack-floor guard must cover the complete frame. Do not blindly hoist arbitrary
loop allocations or remove the guard.

The probe moves only constant allocations from the one-shot `stackadmit` block.
After the combined changes, optimized `parse_node` has **15 entry allocations and
zero outside entry**. The saved IR is included in the evidence.

LLVM documents that entry placement is necessary for its usual SROA/mem2reg
promotion. See [LLVM frontend performance guidance](https://llvm.org/docs/Frontend/PerformanceTips.html#use-of-allocas).

### 2.2 `memset` is hidden behind an incorrect LLVM declaration

The translator emits this for clearing an aggregate:

```llvm
call void @memset(i64 %address, i64 0, i64 72)
declare void @memset(i64, i64, i64)
```

The native calling sequence happens to work for these zero-fill calls on this
target. LLVM cannot recognize it as the usual library operation with a pointer
destination, `int` byte value and pointer return. It remains an opaque external
call, makes the address escape, and prevents initialization and aggregate
optimizations. `parse_node` contains two such calls even after `-O2`.

**Fix:** emit `llvm.memset.p0.i64` with a real `ptr`, `i8` fill and `i64` length,
or use the exact C signature. The probe uses the intrinsic for the observed
zero-fill calls. The combined optimized `parse_node` has no external memset calls.
Build a checked runtime-signature table for other C helpers too; inferring C
parameter types from pointer-width guest operands is not sufficient for LTO/FFI.

### 2.3 Integer address arithmetic really does lose optimization information

Simple `ptrtoint`/`inttoptr` round trips already disappear in optimized IR. There
is no reason to count every cast as an extra machine instruction. The problem is
the remaining **integer arithmetic on addresses**, especially offsets into local
aggregates, which obscures object-relative accesses and prevents scalarization.

The GEP probe first obtains optimized SSA IR, then recovers byte-address GEPs only
where an address has an actual `ptrtoint` origin. It adds no `inbounds`, `noalias`,
fast-math or overflow promises. A second-optimization-pass control separates this
rewrite from simply running LLVM twice.

GEP recovery alone is small. **On top of scratch, memset and aggregate fixes,
GEP recovery adds another 5.4–7.5% speedup over the corresponding two-pass
control.** The interaction matters: fixing only casts leaves the other barriers.

**Fix:** preserve address identity from the typed lowering through pointer-valued
slots, parameters and returns; emit `getelementptr i8` for byte offsets and typed
loads/stores. Retain integers for actual integers and explicit pointer-to-integer
operations. Establish object provenance rather than applying textual rewrites to
arbitrary arithmetic. LLVM explains both the arithmetic similarity and the extra
aliasing constraints in its [GEP documentation](https://llvm.org/docs/GetElementPtr.html#how-is-gep-different-from-ptrtoint-arithmetic-and-inttoptr).

### 2.4 Byte-array aggregate values produce poor returns and copies

The adapter loads, returns and stores whole values as `[N x i8]`. For example,
the original `parse_node` assembly contains byte loads/stores around a 72-byte
result, alongside vector copies and spills. The problem is the SSA value and
call-boundary representation; using byte arrays merely to reserve storage is fine.

The `words` probe represents sizes divisible by eight as `[N/8 x i64]`. This
changes the private guest ABI and is a diagnostic, not a recommended public ABI.
It improves wall time by roughly 2–3% alone in the first batch.

**Fix:** implement explicit target ABI lowering. Use scalar register returns for
small aggregates and a caller-provided `sret` buffer for large ones; copy directly
into the destination where legal. Avoid loading a large array into an SSA value
and immediately spilling it into another temporary. LLVM also recommends avoiding
large aggregate SSA values in its [frontend guidance](https://llvm.org/docs/Frontend/PerformanceTips.html#avoid-creating-values-of-aggregate-type).

### 2.5 Whole-module optimization alone is not the missing multiplier

Combining all 66 guest functions into one LLVM module, making their definitions
local to the linked executable, and optimizing together gives about **0–2%** over
the per-function control. This leaves the runtime outside LLVM's visibility.
All 66 benchmark functions were already emitted as `export`; the adapter's
`noinline` fallback is not responsible for this result.

Whole-module visibility can still complement better IR and runtime effect
information. It did not independently supply a large win here. This probe does
not test runtime LTO, PGO, or a clean typed LLVM frontend.

## 3. Matched measurements

The first batch isolated memset, aggregate word representation, scratch placement,
and guest-module visibility. See `evidence/probes-measure.json` for every arm.
The second batch isolates GEP recovery and includes a QBE scratch-placement arm.
Each batch has 31 randomly interleaved rounds, two warmups per arm/workload, and a
separate seven-round hardware-counter batch. CPU affinity errors fail the harness.

**Second batch: median milliseconds.** Combined means whole guest module, static
scratch, memset intrinsic, word aggregates, and GEP recovery.

| Workload | QBE | Original LLVM binary | Rebuilt LLVM control | Combined | Zig | Control / combined |
|---|---:|---:|---:|---:|---:|---:|
| Census 927 KB | 9.18 | 8.50 | 8.55 | **7.40** | 2.15 | **1.155×** [1.127, 1.177] |
| Render 927 KB | 14.26 | 13.34 | 13.36 | **11.77** | 2.81 | **1.135×** [1.112, 1.151] |
| Census 7.42 MB | 84.40 | 78.00 | 77.96 | **69.36** | 14.10 | **1.124×** [1.096, 1.152] |
| Render 7.42 MB | 127.82 | 119.46 | 119.05 | **106.52** | 19.57 | **1.118×** [1.109, 1.127] |

Intervals resample paired rounds. Ratios are ratios of medians. A 1.155× speedup
means a 13.4% time reduction, not a 15.5% time reduction. Do not add improvements
from the ablation arms together.

The original binary and rebuilt control retire the same instruction counts in
the first batch: 76.09 M / 126.02 M / 662.08 M / 1,061.68 M. The common linked
runtime, metadata, entry and formatter hashes are in `evidence/builds.json`.

The combined arm retires 68.57 M / 112.18 M / 601.94 M / 950.96 M instructions in
the second batch. User cycles are 20.78 M / 34.21 M / 214.48 M / 334.94 M. Thus the
new changes eliminate costly work, not just enough cheap instructions to lower IPC.

**Timing scope differs slightly from the original harness:** this audit captures
bytes, while the original times `capture_output=True, text=True`, including Python
UTF-8 decoding and newline conversion. Both include process launch, pipes and
output collection. This especially affects the 5.6 MB rendered output and its
Zig denominator. Compare arms within each batch, not absolute milliseconds between
reports. A follow-up product benchmark should report a verified-output run plus
timing with stdout redirected to a common file or null sink, and separately report
the CLI/output-delivery measurement if that is the intended experience.

## 4. The remaining runtime and representation costs are substantial

Using resolved userspace profile periods (excluding about 4–5% unresolved/kernel-
labelled samples), the original LLVM census spends **31.3% in `trace` plus
`myl_native_heap_collect`**, and the render spends **20.0%**. After the combined
fixes their shares increase to **36.6% and 23.4%**. Their absolute sampled cost
barely changes: about 74 M cycles per large run. Guest functions still account for
about 41% / 39% of the combined census/render profiles; other time is in text,
collections, allocation, copying and library work.

This is a measured remaining cost, not a floor inferred merely because two
executables share a runtime archive. Guest representation can change how often
that runtime runs and how much it traces.

Memory evidence points in the same direction:

| Large workload | Original LLVM maximum RSS | Combined maximum RSS | Zig maximum RSS |
|---|---:|---:|---:|
| Census | 76.1 MiB | 76.3 MiB | 16.3 MiB |
| Render | 117.9 MiB | 118.1 MiB | 21.7 MiB |

RSS is a single corroborating run per cell, not an interleaved estimate. Seven-run
median minor faults are approximately **21,905 vs 4,131** for LLVM/Zig census and
**32,629 vs 5,528** for render. The lowering fixes essentially do not reduce them.
This supports allocation/page-touch costs; it does not establish a cache-miss,
DRAM-bandwidth, or dependency-stall breakdown.

Specific sources of excess work:

* `sexpr.tokenizer::tokenize` materializes the complete token list. `lexeme`
  decodes each text into managed scalar storage. The Zig parser consumes
  `Tokenizer.next()` incrementally and keeps source slices. Equivalent output
  does not make these equivalent intermediate representations.
* Coallocated strings still carry a 96-byte managed-object header plus a 72-byte
  collection header and four bytes per scalar. Tiny atom strings remain expensive.
* `native_heap.c::trace` interprets descriptors recursively, including calls for
  scalar fields that cannot contain references. `native_descriptors.zig::emit`
  emits all structural fields; `native_types.zig` already computes `Layout.trace`.
  `Span` and scalar fields are an obvious opportunity for a separate compact GC map.
* The printer builds managed text pieces and joins scalar text before UTF-8 output.
  Bulk `print(str)` helped previously, but cannot remove the preceding construction,
  copying, joining and encoding.

## 5. Correctness and evidence gaps to fix before adopting the backend

**The private aggregate argument convention is not merely an interoperability
limitation.** QBE aggregate parameters have by-value semantics. Passing their
address to the callee without a copy can change program behaviour even when both
ends use the same convention.

The three-file reproducer under `audit-20260919/byvalue-*` stores 11 in a caller's
aggregate, calls a callee that stores 99 into its aggregate parameter, then reads
the caller's value. **QBE prints 11; the current adapter prints 99.** This is a
translator correctness failure. The benchmark can still agree because its
emitted code does not expose that particular difference.

Implement genuine by-value copies (`byval`/local copies and target classification)
and explicit result lowering. Then execute the mixed caller/callee ABI tests;
reading QBE assembly alone does not qualify the LLVM convention. A faster custom
guest ABI is a separate, explicit experiment.

The report's LLVM GC-stress limitation can also be removed: the **built binary**
accepts `--gc-stress` in `qbe_runtime.c::mylang_qbe_run_providers`. No
`mylang run --qbe` support is needed. I exercised this directly.

The diagnostic binaries passed **1,440 checks across 16 arms**: the 17 existing
goldens, seven additional Unicode/number/malformed/empty inputs, census and render,
and actual binary GC stress for inputs below 2 KB. All timed outputs also match.
This does **not** qualify the probes as a production backend: it does not replace
full-language tests, ABI tests, loop-allocation proofs, memory-budget tests, or
physical-stack exhaustion and accounting tests. The by-value failure above remains
in the underlying adapter; these experiments have not silently fixed it.

Other reporting corrections:

* Falling IPC is an arithmetic result of instructions dropping faster than cycles.
  It does not alone identify memory serialization. The profiles reveal both real
  wins and regressions that the original explanation missed.
* Matching O2/O3 code does not show that optimization passes were unimportant;
  both levels run many of the same passes. The optimized IR visibly differs from
  the raw emitted slot-based IR.
* `instructions:u` includes userspace runtime/library instructions. `task-clock`
  is not a user-only counter. Those comments in `measure.py` should be corrected.
* The original `measure.json` stores summaries and intervals, not its raw samples,
  despite the documentation. It cannot independently reproduce those intervals.
  This audit retains wall samples, round orders and raw perf reports.
* The adapter uses host `zig cc` defaults; the assembly contains AVX instructions.
  Do not describe this as a pinned common baseline CPU feature set without passing
  and recording explicit target/CPU flags. This audit preserves the original flags.

## 6. Recommended implementation order

| Priority | Change | Acceptance evidence |
|---|---|---|
| 0 | Correct aggregate argument/result ABI, C helper signatures, and deterministic complete signature discovery | By-value reproducer prints 11 in both arms; mixed C/QBE/LLVM ABI tests; full guest/trap/accounting suite; actual LLVM GC stress |
| 1 | Entry scratch with complete stack accounting; real memset; pointer/GEP addressing; destination-based aggregate results | Remove dynamic scratch in `parse_node`; retain checks and root lifetimes; reproduce ablation gains in matched runs |
| 2 | Separate compact GC trace maps from general structural descriptors; skip pointer-free records/scalars and dispatch variants directly | Fewer visits and lower absolute GC cycles at equal allocations; stress/alias/cycle/arena tests; unchanged equality/formatting/drop behaviour |
| 3 | Streaming tokens and source spans or borrowed lexemes with explicit source lifetime; decode only when required | Identical parser diagnostics, numeric/Unicode semantics and printer bytes; fewer allocations, lower live bytes/RSS and large-input cycles |
| 4 | Compact text/collection storage and a printer byte builder | Preserve scalar-indexed string semantics and Unicode; reduce page faults, joining/encoding work and large-render ratio |
| 5 | Re-evaluate LLVM adoption with corrected lowering, then consider runtime LTO/PGO | Measured whole-application benefit, cold/warm build cost, explicit feature flags and reproducible raw samples |

Do not remove fields from the existing general-purpose type descriptors just to
speed up GC: they are also consumed by equality, region traversal and drop logic.
Give GC its own filtered map or a specialized tracing function. Likewise, do not
turn off collection or bounds/overflow checks to claim the 2× target.

The next large investment should reduce allocation and tracing demand. The
measured LLVM cleanup is worth doing to make the experiment credible, but its
remaining 3.45–5.44× ratios require changes beyond selecting another optimizer.
