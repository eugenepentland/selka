# llvm-backend — an LLVM arm for the existing QBE lowering

> **Status (2026-09-24): retired from the toolchain, kept as an oracle.** The
> compiler now translates QBE IL to LLVM IR itself (`src/qbe_build_llvm*.zig`,
> `LLVM-ZIG-1` in `SPEC.md`), so `--release` runs no Python. Nothing in the
> build, the install or the compiler reaches the Python files here: `zig build`
> no longer installs them under `lib/mylang-llvm`, `--llvm-adapter` and
> `MYLANG_LLVM_ADAPTER` are gone, and a `--qbe` path ending in `qbe_llvm.py` only
> selects the built-in backend without reading the file. They stay because they
> are the reference the Zig port was proven against byte for byte:
> `experiments/llvm-zig-20260924/equivalence.py` replays a build's
> `MYLANG_LLVM_DUMP` through `qbe_llvm.translate_text`, the golden corpus
> `test/fixtures/llvm-translate/adapter-corpus.json` was generated from it, and
> `zig build test-llvm-adapter` still runs `test_adapter.py`. The rest of this
> page describes the experiment as it was run; where it says "the adapter", the
> Zig translator now does the same thing. See
> [`docs/audits/devspeed-llvm-zig-2026-09-24.md`](../../docs/audits/devspeed-llvm-zig-2026-09-24.md).

An isolated experiment that answers one question: **how much of mylang's remaining
runtime gap comes from QBE optimizing and generating code for the current
lowering?** Guest source, frontend optimizations, object layouts, runtime, safety
checks and output all stay constant; only the backend that turns emitted IL into
assembly changes.

The plan this implements is
[`docs/audits/llvm-backend-experiment-plan-2026-09-19.md`](../../docs/audits/llvm-backend-experiment-plan-2026-09-19.md);
the findings are in `docs/audits/llvm-backend-experiment-results-2026-09-19.md`.

## How it works

The compiler's native driver already accepts `--qbe PATH` and invokes that tool
once per emitted unit as

```sh
TOOL -t amd64_sysv -o OUTPUT.s INPUT.ssa
```

`qbe_llvm.py` is a drop-in replacement for that tool. It parses the QBE IL,
emits LLVM IR for the same unit, and runs the pinned toolchain to produce the
assembly the existing assembler/linker pipeline consumes:

```text
        frozen frontend manifest (same unit IL, same metadata)
                          |
              +-----------+------------+
              |                        |
            QBE               qbe_llvm.py: IL -> LLVM IR
              |                        |
         assembly            zig cc -S -O2 -> assembly
              |                        |
              +-----------+------------+
                          |
        existing assembler/linker pipeline: identical runtime archive,
        identical generated C metadata, identical executable entry
```

One LLVM module per existing guest function unit, compiled at `-O2` (and `-O3` as
a second arm), linked by the driver exactly as the QBE arm is. QBE remains the
default backend. The follow-up fixes also change the shared frontend scratch
placement and GC descriptors; both newly built arms use those changes. Pure
aggregate scratch is eligible for entry placement; opaque runtime-call buffers
and semantic zero-length arrays retain later allocation because entry placement
exposed QBE miscompilations in resource cleanup and generic arrays.

### The IL the translator consumes

| fact | consequence in the translator |
|---|---|
| QBE temporaries are mutable cells; the frontend reassigns names | every temporary gets one private slot in the LLVM entry block and LLVM's own `mem2reg`/SROA promotion turns it back into SSA |
| `l` is a 64-bit integer that *sometimes* holds an address | internal cells retain `i64`; proven address arithmetic uses byte GEPs and registered runtime declarations use `ptr` |
| every aggregate (`:tN = align 8 { b N }`, `:myl_slice`) is the **address** of its storage within the body | call boundaries use AMD64 SysV integer coercions or `byval`/`sret`; callees receive independent aggregate storage |
| aggregate register assignment depends on the whole signature | the adapter accounts for hidden result pointers and rolls an entire aggregate onto the stack when its registers are unavailable |
| a block that runs off its end continues at the next one | the implicit fall-through is emitted as an explicit branch |
| the frontend emits every overflow/bounds/cast/allocation check itself | no `nsw`/`nuw`/`exact`/fast-math, no `inbounds`, no `noalias` pointer attribute, no TBAA |
| every `alloc*` is this activation's own stack storage, and the frontend marks the managed addresses it knows are not (`# myl-obj %temp`, and `# myl-elem %temp KIND` for a container's element storage) | a load or store either side places carries scoped `!alias.scope`/`!noalias`; objects and element storage of each kind get scopes that exclude each other; one neither side places carries none |
| an element access is an integer sum on the marked storage word | a load or store whose address is such a sum from the same block gets it as a plain `getelementptr i8` from the base, so scalar evolution sees the index |
| a checked reduction or other overflow check in a loop is a branch to a trap | a loop whose checks decide nothing else is versioned (`sticky_loops.py`): a fast copy without those branches, verified at its exits, falling back to the untouched loop |

## Layout

| file | role |
|---|---|
| `qbe_llvm.py` | the QBE-compatible tool: IL parsing, type inference, the CLI, and the `zig cc` invocation |
| `llvm_emit.py` | LLVM IR emission for one unit |
| `sticky_loops.py` | loop versioning before emission: the fast copy without overflow-check branches, its exit verification and the fallback (LLVM-STICKY-REDUCTION-1) |
| `amd64_sysv.py`, `runtime_signatures.py` | aggregate ABI classification and exact C helper declarations |
| `test_adapter.py` | executable ABI, alignment, pointer and stack-guard regressions |
| `inventory.py` | opcode/type/signature/symbol inventory of a manifest — the supported-subset contract |
| `verify_units.py` | translates and assembles every unit of a manifest |
| `verify_semantics.py` | builds each arm from the same compiler and diffs stdout/stderr/status |
| `verify_traps.py` | builds the repository's differential trap fixtures with both arms in every accounting mode and diffs them |
| `verify_binaries.py` | prebuilt benchmark arms checked against an oracle, stored goldens, malformed input and actual GC stress |
| `measure.py` | interleaved wall-clock and counter batches across QBE, LLVM and the Zig reference |
| `qualify_all.sh` | the whole qualification in one command: sweep, byte-equality, suites, traps, cost, paired measurement |
| `qualify_sweep.py` | builds every `.my` entry under the language tree with both arms and records every failure |
| `qualify_affected.py` | builds, runs and tests the entries the as-found sweep could not build, in both arms |
| `qualify_equiv.py` | runs each guest suite through both arms in separate caches and compares verdicts by name |
| `qualify_traps.py` | the trap, ceiling, GC-stress and exit-status matrix for both arms |
| `qualify_cost.py` | cold-cache build time, driver phase split and binary size for both arms |
| `qualify_identity.py` | the compiler and `src/qbe.zig` hashes every stage records at its start and end |
| `tests/abi/` | hand-written QBE probes that pin the target ABI, with `README.md` recording the measured table |
| `evidence/` | hashes, inventories, raw samples |

## Commands

```sh
# 1. Freeze the frontend input for the benchmark closure.
./zig-out/bin/mylang emit-project-qbe experiments/sexpr-port/main.my \
  --drop-debug --drop-step-checks --drop-frame-checks > /tmp/census-manifest.json

# 2. Every emitted unit translates and assembles.
python3 -B experiments/llvm-backend/verify_units.py /tmp/census-manifest.json

# 3. Build one arm of the benchmark.
./zig-out/bin/mylang build experiments/sexpr-port/main.my \
  -o /tmp/census-llvm --cache-dir=/tmp/cache-llvm --mode ReleaseFast --keep-symbols \
  --qbe=$PWD/experiments/llvm-backend/qbe_llvm.py

# 4. Both arms agree on every benchmark workload.
python3 -B experiments/llvm-backend/verify_semantics.py --work /tmp/vs --json /tmp/vs.json

# 4b. Both arms agree on every trap, accounting and GC-stress fixture.
python3 -B experiments/llvm-backend/verify_traps.py --work /tmp/traps --jobs 8

# 5. The matched measurement batch (QBE, LLVM -O2, LLVM -O3, Zig ReleaseFast).
python3 -B experiments/llvm-backend/measure.py --work /tmp/measure --rounds 31 \
  --json /tmp/measure.json
```

Useful environment variables: `MYLANG_QBE_LLVM_OPT` (the optimizer level passed to
`zig cc`, default `-O2`), `MYLANG_QBE_LLVM_KEEP_IR=PATH` (keep the translated IR,
which is otherwise deleted), `MYLANG_QBE_LLVM_SIGNATURES=PATH` (a closure
signature sidecar, so a unit knows how its callees are declared).

## Toolchain

There is no standalone `clang`, `opt` or `llc` on this machine. The LLVM used for
the experiment is the one inside the pinned Zig release:

```console
$ zig version
0.17.0-dev.1683+5ceec001b
$ zig cc --version
clang version 22.1.8
Target: x86_64-unknown-linux7.0.0-gnu2.43.0
```

`zig cc -x ir` is **not** accepted, but a `.ll` file is compiled from its
extension: `zig cc -S -O2 -fPIC -g0 unit.ll -o unit.s`. The production Zig
version is unchanged. The frozen Zig reference in the comparison
(`experiments/sexpr-port/zig-bench`, ReleaseFast) is compiled by the same Zig
release, so both arms share the same LLVM code generator behind a different
frontend.

## Known limitations

* **The ABI supports the emitted aggregate subset.** Opaque byte records and the
  two-integer slice use the AMD64 SysV integer aggregate convention. This is not
  a general QBE translator for floating-point aggregate members, unions or other
  targets. Executable tests cover small and large records, mixed scalar arguments
  and register exhaustion. The former shared-address aggregate argument bug is
  fixed; internal consistency alone was insufficient to establish correctness.
* **Per-unit optimization only.** `qbe_llvm.py` sees one unit at a time, so it
  cannot inline across guest functions. Whole-guest-module LLVM optimization would
  need a manifest-aware build path and is a separate, later arm.
* **No whole-program LTO, PGO or host-specific tuning.** The comparison arms all
  target the same baseline x86-64 features.
* **The runtime is shared between newly built arms.** Follow-up GC changes require
  native artifact ABI v5 and layout identity v2. Old binaries retain their old
  runtime for before/after comparisons; do not mix their descriptor objects with
  the new runtime. Current arm runtime hashes are recorded in the measurement.
* **Unknown runtime helpers fail translation.** `runtime_signatures.py` reads a
  helper's signature from the C header that declares it, or from the Zig
  `@export` that defines it; a helper whose declaration is in neither, or whose
  types the generator does not recognise, refuses translation rather than
  guessing, and has to be extended from the declaration the compiler emits.
* **Indirect calls follow the call site's own evidence.** `call %temp(...)`
  lowers with the argument spellings the IL carries and the destination's
  aggregate annotation, so the callee's unit must have been compiled from the
  same convention — which holds while every guest function takes pointer-width
  parameters. A target whose signature contradicts its call site would be a
  mis-compilation rather than a refusal, so `test_adapter.py` pins the scalar,
  aggregate-result and aggregate-argument shapes against direct calls.
* **`phi` is lowered as an edge store.** The emitted IL uses `phi` for float
  normalisation, and the value is written on the edge out of the block that
  supplies it, so the merge block reads a slot its entering predecessor filled.
  Any future IL that reads a phi destination on a path its predecessors do not
  cover would need the same treatment checked again.

## Evidence

| file | contents |
|---|---|
| `evidence/unit-inventory.json` | every opcode, type, signature and external symbol in the census and scan closures |
| `evidence/runtime-symbols.json` | all 233 symbols the census closure references, each resolved to the C header or the generator that defines it (37 runtime functions, 132 metadata records, 42 literals, 20 descriptors, 1 renderer, `memset`) |
| `evidence/measure.json` | the final 31-round interleaved batch: arm hashes, input hashes, per-arm medians and IQRs, counter medians, and bootstrap intervals for every ratio |
| `evidence/verification.txt` | the tool versions, adapter hashes, fixture hashes and the result of each correctness gate |

## Results

The findings, the benchmark table and the decision thresholds are in
[`docs/audits/llvm-backend-experiment-results-2026-09-19.md`](../../docs/audits/llvm-backend-experiment-results-2026-09-19.md).
The implemented fixes and their matched before/after results are in
[`docs/audits/llvm-runtime-fixes-2026-09-19.md`](../../docs/audits/llvm-runtime-fixes-2026-09-19.md).

## Qualification

The 20 September 2026 qualification — whether this arm is ready to be the
default backend — is in
[`docs/audits/llvm-backend-qualification-2026-09-20.md`](../../docs/audits/llvm-backend-qualification-2026-09-20.md),
with its raw evidence under `evidence/qualification-20260920/`. Verdict: **ready
as an opt-in release backend, not yet ready to be the default** — every runnable
gate passes (326-entry build sweep with zero LLVM-only failures, four guest
suites equal test for test, every trap code identical, doctest and the port's
own golden/reference comparisons green in both arms) and LLVM is a repeatable
17–20% ahead on the census/render pair, while a 2.97× cold build and a
single-workload performance picture are what remain before a default switch.

It re-ran on the current language level: a 326-entry build sweep over every `.my`
entry under `tests/lang`, `tests`, `examples` and `experiments/sexpr-port`, guest
suites through both arms, a trap/ceiling/GC-stress/exit-status matrix, the port's
own golden and reference comparisons, cold-cache cost, and a paired wall-clock and
counter measurement. Two translator gaps it found and fixed are part of this
directory now: indirect calls (`call %temp(...)`, i.e. every function value) and
the signed sized-load mnemonics, and the runtime signature registry reads Zig
`@export`ed helpers instead of needing each one hand-registered.

```sh
experiments/llvm-backend/qualify_all.sh /tmp/llvm-qual-run
```

The original evidence is historical. Follow-up validation enables requested
budget accounting at build time, runs compiled binaries with `--gc-stress`, and
treats every failed build as a failed gate. Three invalid historical trap sources
have valid replacements under `tests/traps/`; the report records the source and
hash actually used. Measurements now retain individual wall/counter samples and
round order. `--sink=capture` captures bytes without Python text decoding;
`--sink=null` times output to `/dev/null` with output verification before and
after. `instructions:u` and `cycles:u` include the C runtime and libc.
