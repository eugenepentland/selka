# Schematic tool: where the runtime gap to Zig and Rust still is — 2026-09-22

Fresh measurement of the schematic SVG renderer (`src/schematic/guest`) against the
byte-identical Zig and Rust ports, on the compiler at `acbee603`
(`local-reasoning/integration`, which contains every merged `perf/roadmap-*` item),
built ReleaseFast in a private worktree. Every arm reproduces the fixture's exact
49,617-byte SVG on every timed run. Evidence, scripts and raw rounds:
[`experiments/schematic-parity-gap-20260922`](../../experiments/schematic-parity-gap-20260922/README.md).

## Headline

1. **The default `mylang build` policy renders the fixture in 2.40 ms against Zig's
   1.31 ms and Rust's 1.50 ms: 1.84× Zig, 1.60× Rust** (mean of three inputs
   1.84× / 1.64×). That is the LLVM O3 + LTO, GC, no-step-accounting build.
2. **The shipped `schematic-svg` runner does not get that build.** It passes
   `--step-accounting --qbe PATH` and no `--backend`, so the guest is compiled by
   QBE with instruction accounting: **7.57 ms, 5.80× Zig**. Step accounting alone
   triples the LLVM build (2.40 → 7.15 ms). Two flags the runner already accepts
   (`--backend llvm --llvm-opt 3 --lto`) plus dropping or batching the step budget
   recover 5.2 of the 6.3 ms gap in production without touching the compiler.
3. **Disabling safety is not the fix.** Stripping every overflow, cast, bounds and
   allocation check (1,425 guarded sites) saves **4%**; removing the per-call frame
   record and position stores (3,872 IL lines) saves **13%**; both together leave
   the render at **2.03 ms, 1.64× Zig**.
4. **Measured on the work itself, the gap is 4.3×, not 1.84×.** Both processes spend
   about 0.9 ms starting and stopping. Inside the guest entry point mylang spends
   1,232 µs where Zig spends 287 µs and Rust 292 µs; with every check stripped it is
   still 988 µs (3.4×). The remaining cost is representation and code shape:
   aggregate values that travel through memory two or three times per read,
   container headers reloaded on every element access, byte-granular I/O bridges,
   and a checked-append output path — not the checks themselves.
5. Per phase, mylang is at **1.4× on routing, 2.5× on placement, 5× on parsing,
   5.7× on SVG text emission and 7.2× on model construction**. Routing is the only
   phase near parity, and it is the phase the earlier fixes targeted.

## 1. Standing

Fresh process, input reads through complete SVG file output, `taskset -c 6`, three
warmups, 31 randomized interleaved rounds, every run's SVG hash checked. Ratios are
medians with 95% paired-bootstrap intervals
([`results-base.json`](../../experiments/schematic-parity-gap-20260922/results/results-base.json)).

| arm | policy | fixture, ms | × Zig | mean of 3 inputs |
|---|---|---:|---:|---:|
| `zig-o3` | Zig ReleaseFast, native CPU, static | 1.305 | 1.00 | 1.00× |
| `rust-o3` | rustc `-C opt-level=3 -C codegen-units=1` | 1.504 | 1.15 [1.11, 1.19] | 1.12× |
| `rust-o3-native` | + `target-cpu=native`, `lto=fat`, `panic=abort` | 1.449 | 1.11 [1.07, 1.15] | 1.11× |
| `go-fast` | `go build` | 1.906 | 1.46 [1.42, 1.48] | 1.45× |
| **`gc-lto`** | **`mylang build` default: LLVM O3 + LTO, GC, unbounded** | **2.401** | **1.84 [1.78, 1.88]** | **1.84×** |
| `arena-lto` | same, `main` wrapped in `with arena()` | 2.309 | 1.77 [1.71, 1.81] | 1.74× |
| `qbe` | `--backend qbe`, unbounded | 2.777 | 2.13 [2.05, 2.18] | 2.10× |
| `gc-lto-bounded` | LLVM O3 + LTO with step accounting, `--max-steps=1e8` | 7.152 | 5.48 [5.34, 5.62] | 5.40× |
| `qbe-bounded` | QBE with step accounting | 7.526 | 5.77 [5.57, 5.99] | 5.65× |
| **`prod-default`** | **exactly the runner's argv: `--step-accounting --qbe PATH`** | **7.574** | **5.80 [5.56, 5.95]** | **5.71×** |

`prod-default` was built with the argument list `src/host_native.zig` composes for
the `schematic-svg` runner; its receipt says `"backend": "qbe", "lto": false`. The
explicit `--qbe PATH` pins the backend, so the ReleaseFast default of item 1 of the
[roadmap](../performance-roadmap.md) never applies to the tool. The arena arm is
4% faster than GC with overlapping intervals on two of three inputs; the render
makes about 134 managed allocations and never collects, so allocation policy is not
where the gap is. Peak RSS: mylang 4.3–4.5 MB, Zig 2.0 MB, Rust 2.4 MB, Go 2.1 MB.

Tuning the Rust comparator (native CPU, fat LTO, abort on panic) changes it by 4%,
so the ports' build flags are not hiding headroom on the native side.

## 2. What safety costs: the strip ladder

`strip_il.py` rewrites the emitted manifest before `mylang build --manifest-file=`:
a guarded check is a `jnz` whose one successor is a pure failure block (optional
position store, one `myl_qbe_fail_*` call, `jmp @failure`), and the jump is replaced
by the fall-through; the frame mode is the earlier audit's `patch_frames.py`
(record link/unlink, stack-floor test, metadata store, position stores). The
stripped binaries produce identical SVG; they cannot report the removed failures.
Same batch as the ladder's own Zig and Rust arms
([`results-ladder.json`](../../experiments/schematic-parity-gap-20260922/results/results-ladder.json)).

| arm | removed | fixture, ms | × Zig (1.237) | vs `gc-lto` |
|---|---|---:|---:|---:|
| `gc-lto` | — | 2.390 | 1.93 | — |
| `s-overflow` | 736 add/sub/neg/div overflow sites | 2.385 | 1.93 | −0.2% |
| `s-cast` | 290 narrowing-cast sites | 2.348 | 1.90 | −1.8% |
| `s-bounds` | 313 list/array index sites | 2.354 | 1.90 | −1.5% |
| `s-alloc` | 86 allocation/capacity sites | 2.395 | 1.94 | +0.2% |
| `s-checks` | all 1,425 check sites | 2.288 | 1.85 | **−4.3%** |
| `s-frames` | frame record, floor test, 1,909 position stores (3,872 lines) | 2.083 | 1.68 | **−12.8%** |
| `s-all` | everything above | 2.030 | 1.64 | **−15.1%** |

The four check classes together are worth 0.10 ms; the frame protocol 0.31 ms. A
build policy that drops both — which the user has said is acceptable for this tool
— lands at 1.64× Zig. Nothing in the language's dynamic checks explains the other
0.8 ms.

## 3. Where the time is

### 3.1 Process floor

Uniform invocation of every arm (same Python parent, same environment, CPU 6,
31 rounds; [`results-floors2.json`](../../experiments/schematic-parity-gap-20260922/results/results-floors2.json)):

| probe | what runs | median, ms |
|---|---|---:|
| `empty-zig` | `pub fn main() void {}` ReleaseFast | 0.798 |
| `empty-rust` | `fn main() {}` O3 | 0.954 |
| `mylang-plain` | `def main() -> int: return 0`, LLVM O3 + LTO | 0.938 |
| `mylang-prov-empty` | schematic provider registered, three files loaded by the provider, one host call | 0.963 |
| `mylang-prov-read` | + the guest's `io.load` of all three documents (block reads, per-byte append) | 1.039 |
| `zig-o3` | full render | 1.153 |
| `rust-o3` | full render | 1.291 |
| `gc-lto` | full render | 2.322 |
| `s-all` | full render, all checks and frames stripped | 1.993 |

Zig's entire render is 0.36 ms above its own empty-process floor; mylang's is
1.38 ms above its floor, and 1.06 ms with everything stripped. The floors differ
by 0.14 ms (dynamic libc and the runtime's heap set-up against a static Zig
binary), the provider adds 0.03 ms, and the guest's own input path — 102
`read_block` calls followed by 40 K `append_byte` iterations — costs 0.08 ms where
Zig's `readFileAlloc` costs 0.02.

### 3.2 Per phase

Linker `--wrap` interposition around 13 guest functions in a non-LTO O3 relink of
the same objects, CPU clock (`CLOCK_PROCESS_CPUTIME_ID`), medians of 31 interleaved
rounds. The relinked control runs within 0.3% of the original binary and within 2%
of the LTO arm (2.338 / 2.345 / 2.381 ms), so the attribution transfers. The Zig
and Rust ports carry the same timers in source (`ports/main-phases.{zig,rs}`);
their SVG hashes are unchanged. Values are inclusive microseconds
([`phases-o3.json`](../../experiments/schematic-parity-gap-20260922/results/phases-o3.json),
[`phases-o3-s-all.json`](../../experiments/schematic-parity-gap-20260922/results/phases-o3-s-all.json),
[`native-phases.json`](../../experiments/schematic-parity-gap-20260922/results/native-phases.json)).

| phase | mylang, checked | mylang, all stripped | Zig | Rust | checked ÷ Zig | stripped ÷ Zig |
|---|---:|---:|---:|---:|---:|---:|
| read documents (`io::load` ×3 / `readFileAlloc`) | 71 | 65 | 23 | 13 | 3.1× | 2.8× |
| parse (`sexpr::parse` ×3) | 172 | 169 | 34 | 37 | 5.0× | 5.0× |
| model (`schematic::build`) | 373 | 273 | 52 | 54 | **7.2×** | 5.3× |
| — `circuit::collectPins` | 122 | 76 | | | | |
| — `circuit::normalize` | 101 | 101 | | | | |
| — `validate::model` | 51 | 25 | | | | |
| placement (`layout::build`) | 220 | 176 | 89 | 86 | 2.5× | 2.0× |
| routing (`layout_routes::build`) | 37 | 32 | 26 | 20 | 1.4× | 1.2× |
| SVG text emission (`svg::render` less placement, routing, flush) | 280 | 216 | 49 | 49 | **5.7×** | 4.4× |
| output copy and write (`io::flush` / file write) | 59 | 48 | 14 | 32 | 4.2× | 3.4× |
| **guest total (`main::main`)** | **1,232** | **988** | **287** | **292** | **4.3×** | **3.4×** |

Two things stand out. Stripping every check and frame does not move parsing or
`normalize` at all: their cost is not in checks. And the phases the earlier fixes
targeted — routing's pin lookup and row buckets — are now within 1.4× of Zig,
while the phases nobody has touched (model construction, SVG emission, parsing)
carry 0.7 of the 1.2 ms gap.

Attribution of the 1.21 ms fixture gap (LTO arm 2.38 ms against Zig 1.17 ms in
this batch):

| bucket | ms | share |
|---|---:|---:|
| model construction | 0.32 | 27% |
| outside the guest entry: process floor, runtime init and teardown, provider | 0.27 | 22% |
| SVG text emission | 0.23 | 19% |
| parsing | 0.14 | 11% |
| placement | 0.13 | 11% |
| document reads | 0.05 | 4% |
| output flush | 0.05 | 4% |
| routing | 0.01 | 1% |

Of the 0.95 ms inside the guest, the checks and frame protocol are 0.24 ms
(checked 1,232 → stripped 988 µs); the other 0.70 ms is code shape.

### 3.3 Self-PC profile

`LD_PRELOAD` SIGPROF sampler over 4,000 fresh runs of the LTO arm (hardware
counters are unavailable on this host; 1 ms tick granularity; two sampler
variants agree within noise;
[`profile2-gc-lto.json`](../../experiments/schematic-parity-gap-20260922/results/profile2-gc-lto.json)).
Share of all CPU samples: `io::flush` 8–10%, `sexpr::at` 8.5–9.6%, `text::write`
6.7–7.3%, `sexpr::form` 5.5–6.9%, `text::escaped` 4.7–6.2%, `text::decimal`
4.3–5.4%, `svg::passive` 3–4%, `layout_routes::build` 3.8–4.4%, `circuit::label`
2.7–3.0%, `layout::partPin` 0.9–5.5%; 26–31% of samples fall outside the
executable, in libc's `memcpy`/`memset`/`malloc` and the dynamic loader. The
stripped and native binaries are too short-lived for a tick sampler to profile,
which is why §3.2 uses in-process clocks.

## 4. The mechanisms, with the machine code

**Aggregate values travel through memory two or three times per read.** The single
hottest address in the program (5.3% of samples) is the last store of
`sexpr::at`: the 48-byte `Node` is loaded from list storage into frame scratch
with two overlapping 32-byte moves, the frame record is unlinked, and the scratch
is reloaded and stored again into the caller's return slot. `sexpr::form` then
copies the returned record a third time to compare its 4-byte `kind`. The
overlapping-move-then-reload pattern also defeats store forwarding, which is why
one store instruction carries the samples. `layout::partPin` does the same with
the 112-byte `Pin`: four vector loads into scratch, a two-field compare, four
vector stores into the return slot, and the caller copies again. The unbounded
manifest has 381 `blit` copies, 190 aggregate scratch slots and 58,960 bytes of
per-function scratch; `layout_routes::build` alone is 9,598 IL lines and 42 KB of
machine code. Zig's `at` is inlined and reads `nodes[index].kind` in place.

**Container headers are reloaded on every element access.** The output copy loop
in `io::flush` is 14 instructions per byte: it reloads the buffer object pointer,
its length, and its storage pointer each iteration, normalizes the index, tests
bounds, and stores into the 256-byte block. The input loop in `io::load` is 13 per
byte and writes the buffer's length back to its header on every append. The
object pointers live in root records and frame scratch whose addresses escape to
the runtime, the LLVM adapter's first design rule is to emit no `noalias`, TBAA,
`inbounds` or `nsw`/`nuw` annotations at all (`experiments/llvm-backend/qbe_llvm.py`),
and the inline append path stores to the header inside the loop, so LLVM can
neither keep the header in registers nor hoist it. Zig's ports do a `memcpy`-class read and one
`writeStreamingAll`.

**Byte-granular I/O bridges.** The host contract moves documents in 256-byte
blocks and the guest re-appends them byte by byte; the output is copied byte by
byte into 256-byte blocks. About 75,000 element operations — 0.13 ms of the
0.15 ms these two phases cost — where the native ports do three reads and one
write.

**Checked append on the emission path.** Every `text.write` goes through
`io.append`: a failed-flag test, a 4 MiB limit test, the inline capacity test, a
length and generation bump, with `myl_native_bytes_copy_octets` for the literal's
octets; `text.escaped` funnels each byte through `appendByte` with the same tests;
`text.decimal` calls a runtime helper; the buffer grows by doubling from a small
reservation. Zig's port reserves 64 KB once and appends slices. This phase is
5.7× and the checks explain only a fifth of it (280 → 216 µs stripped).

**Inlining budget.** 62 of the 124 guest functions survive as symbols in the LTO
binary (37 in the stripped one); Zig keeps two (`main.parse`, `main.render`). The
check and frame code inflates every body past the inliner's thresholds, so
`at`, `form`, `partPin` and `innerPin` stay as calls returning records in memory.

**Frame protocol and checks.** 0.31 ms and 0.10 ms respectively (§2). Roadmap item
2's frame-record replacement was measured and reverted; the position stores
(1,909 static) and the record are still on every call.

**Process floor.** 0.14 ms over a static Zig binary, plus provider set-up; small
in absolute terms but a fifth of this 1 ms workload.

## 5. What closes it, in order

| # | change | evidence for the size | roadmap |
|---|---|---|---|
| 1 | **Ship the LLVM policy in `schematic-svg`** (`--backend llvm --llvm-opt 3 --lto`, which the runner already parses) and **stop requesting step accounting** for the tool, or batch it | 7.57 → 2.40 ms today; step accounting is 4.75 of the 7.15 ms bounded time | 1 (policy), 8 |
| 2 | **Read aggregates in place and forward return slots**: `xs[i].field` and `at(nodes, i).kind` as a field load through the element's address; record-returning helpers write the caller's destination once; pass by-reference locals for read-only records | model 7.2×, parse 5.0×, placement 2.5×; `sexpr::at` + `form` + `partPin` are 16–20% of samples; 381 blits | 6 remainder |
| 3 | **Keep container headers in registers**: let the adapter emit alias scopes for header fields versus element storage (and `inbounds`/`nsw` after the explicit guards, which its current no-annotation rule forbids), and keep the length/storage of a loop's receiver in SSA values when the body cannot mutate it | 13–14 instructions per byte in both I/O loops; the same reload pattern in every `while i < len(xs)` loop | 5, 6 |
| 4 | **Bulk I/O host calls carrying `bytes`**: one owned payload per document, one `write_bytes(buffer)` for the output | read 3.1×, flush 4.2×; 0.13 of 0.15 ms is the per-byte loops | new |
| 5 | **Output emission fast path**: reserve the output once, lower `text.write` of a literal to a capacity test plus `memcpy`, and `escaped` to a scan-and-copy | 280 µs against 49; only 64 µs of it is checks | 5 |
| 6 | **An unchecked build policy** for the four check classes and the frame protocol, taken at emission time rather than by manifest rewriting | −15% (2.39 → 2.03 ms), byte-identical output | 2, new flag |
| 7 | **Inliner room**: after 2 and 6 the IL shrinks; mark record accessors for inlining and measure the survivor count | 62 → 37 survivors when stripped | — |
| 8 | Static linking and lazy runtime init | 0.14 ms floor difference | — |

Items 2–5 address the 0.70 ms that stripping cannot reach; item 6 the 0.36 ms it
can; item 1 is the only one that changes what the user's tool does today. A
production build that lands 2 through 6 should bring the guest's own work from
4.3× to roughly 1.5× Zig on this workload, and the process ratio under 1.3×;
that is a projection from the per-phase sizes above, not a measurement.

## 6. Method and limits

- Compiler: worktree at `acbee603` built `-Doptimize=ReleaseFast` to a private
  prefix; the only local change demotes four duplicate `// spec:` tags to
  `// spec-case:` in one Zig test file so Guardian would allow the install
  (`worktree-spec-case.patch`). Guest sources are the tree's `src/schematic/guest`.
- Arms are built through `emit-project-qbe` (with or without `--drop-step-checks
  --drop-frame-checks`) and `mylang build --manifest-file= --keep-symbols`, with
  `src/schematic/native_schematic.c` as the provider; `builds.json` records every
  argv, binary and manifest hash.
- Native comparators are the retained `.tmp/full-svg-benchmark-20260921` ports
  (rustc 1.98.1, Zig 0.17.0-dev.1683, Go 1.27.0), hash-verified against their
  recorded provenance; the tuned Rust arm and the phase-timed ports were built
  from the same sources.
- Timing is wall clock of a fresh process from a Python parent, one CPU pinned,
  arms and inputs interleaved in random order; ratios use paired bootstraps over
  rounds. Different batches are not compared against each other.
- Phase times are CPU-clock intervals inside the process and exclude the parent's
  spawn cost; the mylang phases come from a non-LTO relink whose wall time
  matches the LTO arm within 2%, so inlining differences at phase boundaries are
  possible but small.
- `perf_event_paranoid` is 4, so there are no instruction or cycle counts; the
  profile is a tick-granularity self-PC sampler and is quoted as ranges.
- One machine (i7-12700H, CPU 6, `powersave` governor), one circuit and two
  mutations; this is a constant-factor audit of a 1 ms workload, not a scale
  study, and it does not equalize memory policy (mylang runs under a 256 MiB
  budget).
