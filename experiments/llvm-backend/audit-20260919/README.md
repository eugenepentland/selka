# LLVM lowering and runtime audit probes

The audit is [llvm-runtime-gap-audit-2026-09-19.md](../../../docs/audits/llvm-runtime-gap-audit-2026-09-19.md).
These are bounded experiments using the existing adapter. They do not change the
compiler, the original adapter, the guest benchmark or the runtime.

## What the arms change

| Arm component | Change |
|---|---|
| `control` | Re-emit all 66 units with a complete signature table; compile separately at O2 |
| `memset` | Recognized LLVM zero-fill intrinsic instead of the opaque integer-argument declaration |
| `words` | Multiples-of-eight byte-array aggregates become word arrays, including private guest result ABI |
| `stack` | Move constant QBE scratch from the one-shot stack-admission block into entry; never move loop allocations |
| `whole` | Combine guest units into one module, define them `dso_local`, allow normal inlining; runtime remains separately linked |
| `twopass` | Run O2 twice, as the control for the post-SSA GEP rewrite |
| `gep` | Run O2, recover GEPs from actual ptrtoint origins, then run O2 again |
| `qbe-stack` | The scratch-placement change applied to original QBE IL, compiled by QBE |

Hyphenated components combine those changes. All LLVM arms retain the adapter's
aggregate-argument convention; that convention has a demonstrated by-value bug.
The word-array and stack probes need ABI and physical-stack qualification before
production use. GEP recovery is a diagnostic for this emitted subset, not a
general-purpose integer-to-pointer rewrite pass. It must preserve object provenance.

## Evidence

* `evidence/probes-measure.json`: first batch, 12 arms, 31 wall rounds and seven
  counter rounds. Separate changes and the first combination.
* `evidence/pointer-measure.json`: second batch, 10 arms, 31 wall rounds and seven
  counter rounds. GEP changes, two-pass controls, final combination and QBE probe.
* Both files retain **all wall observations, round order, raw perf output,
  per-round counters, output hashes and binary/input hashes**. No cross-batch
  ratio is used in the audit. `control_over_arm` is the ratio of medians; its
  interval resamples rounds. Timings capture bytes, not Python-decoded text.
* `evidence/builds.json`: all 14 diagnostic binary hashes and the four common
  linked objects/archive hashes. The control reproduces original instruction counts.
* `evidence/manifest.json.gz`: frozen frontend input, gzip timestamp zero.
* `evidence/provenance.json`: compiler/adapter/QBE/Zig hashes, tool versions,
  machine details and the by-value witness's outputs. The adapter was uncommitted;
  the repository commit alone is insufficient provenance.
* `evidence/validation.json`: 1,440 golden/differential checks, including 672
  direct binary GC-stress executions. 16 arms include original QBE and LLVM.
* `evidence/profiles.json` and `*.full.txt`: all symbol periods and readable
  reports, 20 repetitions per arm/workload. A period of 200,000 cycles means
  these are sampling estimates. Around 4–5% of original samples are unresolved or
  kernel-labelled; the audit's runtime fractions exclude those samples.
* `evidence/rss.json`: single-run peak RSS and coarse user/system times, plus
  faults. Counter-batch median minor faults are in the measurement files.
* `evidence/parse_node*.ll`, `read_atom.opt.ll`, and the two parser disassemblies:
  concrete IR/assembly evidence. The combined IR is after the final O2 pass.

Scratch binaries and raw perf data are under `.tmp/llvm-audit-20260919/`.
No Guardian build gate was exercised: all compilation used the installed compiler,
QBE and `zig cc`, not `zig build`.

## Reproduction in this workspace

Run from the repository root. Match `evidence/provenance.json` first; these commands
depend on the pinned installed toolchain, original build receipt/cache and input
files still available in this workspace. If rebuilding elsewhere, rebuild the
baseline with the same frozen manifest and use its receipt/cache, exact formatter,
runtime and Zig reference, then record the new provenance.

```sh
mkdir -p .tmp/llvm-audit-repro
gzip -dc experiments/llvm-backend/audit-20260919/evidence/manifest.json.gz \
  > .tmp/llvm-audit-repro/manifest.json

python3 -B experiments/llvm-backend/audit-20260919/build_probes.py \
  --manifest .tmp/llvm-audit-repro/manifest.json \
  --receipt /tmp/final-measure/llvm-o2.qbe-manifest.json \
  --formatter zig-out/lib/mylang-runtime/021d85425fa9b09fc0ae1a7688e3a48a8b349d0315d1105135cb323f3bd98b74.o \
  --work .tmp/llvm-audit-repro/probes \
  --arms control,memset,words,stack,stack-memset,whole,whole-memset,whole-words,whole-stack-memset-words,twopass,gep,whole-stack-memset-words-twopass,whole-stack-memset-words-gep,qbe-stack

python3 -B experiments/llvm-backend/audit-20260919/verify_probes.py \
  --work .tmp/llvm-audit-repro/probes \
  --out .tmp/llvm-audit-repro/validation.json

python3 -B experiments/llvm-backend/audit-20260919/measure_probes.py \
  --work .tmp/llvm-audit-repro/probes \
  --out .tmp/llvm-audit-repro/probes-measure.json

python3 -B experiments/llvm-backend/audit-20260919/measure_probes.py \
  --work .tmp/llvm-audit-repro/probes \
  --out .tmp/llvm-audit-repro/pointer-measure.json \
  --arms control,twopass,gep,whole-stack-memset-words,whole-stack-memset-words-twopass,whole-stack-memset-words-gep,qbe-stack
```

Do not benchmark while compiling or profiling. The measurement script fails if
affinity cannot be set to the requested CPU or an output/status differs. Hardware
counter events explicitly use `cpu_core` for this machine's CPU 6; adapt them when
moving to different hardware. The original Zig binary is reused by recorded hash,
not silently rebuilt from possibly different sources.

## Aggregate by-value correctness witness

The caller initializes an aggregate to `{11,22}`, calls a callee that overwrites
its parameter with 99, and then reads the caller's original first word. QBE prints
**11**. The adapter prints **99**, because it passed the caller's storage directly.
This is a semantic difference within a consistently compiled LLVM program, not
just a mixed-object ABI problem.

```sh
mkdir -p .tmp/llvm-byvalue-repro
for arm in qbe llvm; do
  if test "$arm" = qbe; then
    tool=./zig-out/bin/qbe
  else
    tool=./experiments/llvm-backend/qbe_llvm.py
  fi
  for part in caller callee; do
    "$tool" -t amd64_sysv \
      -o ".tmp/llvm-byvalue-repro/$arm-$part.s" \
      "experiments/llvm-backend/audit-20260919/byvalue-$part.ssa"
  done
  zig cc experiments/llvm-backend/audit-20260919/byvalue-main.c \
    ".tmp/llvm-byvalue-repro/$arm-caller.s" \
    ".tmp/llvm-byvalue-repro/$arm-callee.s" \
    -o ".tmp/llvm-byvalue-repro/$arm"
  ".tmp/llvm-byvalue-repro/$arm"
done
```

## Limits

Validation covers the benchmark's observable behaviour, not the entire language.
It does not replace the adapter's broader trap/accounting tests or the missing
mixed-object ABI gate. No production code or default backend was changed, and no
2×-Zig result is claimed. The useful result is the measured removal of lowering
barriers and the identification of the allocation/tracing work that remains.
