# Candidate runtime evidence

The immutable expanded baseline and the audit's 80 fastest targets remain in
their original locations. New measurements use schema `expanded-v2`, an explicit
candidate ID, and a compiler build receipt. The old `expanded-v1` verifier still
checks the historical compiler pin; it cannot silently accept a new compiler.

Build and record the compiler from a full committed source revision:

```sh
python3 benchmarks/runtime/build_compiler.py \
  --source-revision FULL_GIT_COMMIT \
  --work .mylang-cache/runtime-candidate \
  --output .mylang-cache/runtime-candidate/compiler-receipt.json
```

The helper runs `scripts/build-slot.sh build zig build -Doptimize=ReleaseFast -Dcompiler-only=true -j2`
with private Zig caches and disk TMPDIR. It checks source bytes against the
revision before/after the build and records compiler/assets, Zig, command,
environment, and log hashes. This is local provenance, not an independent build
attestation. A receipt for changed compiler bytes or source files is rejected.

`--optimize Debug` explicitly builds a Debug compiler for faster exploratory
iterations and records that mode in the receipt. ReleaseFast remains the default
and the final compiler build policy. Guest build modes are recorded separately
and remain ReleaseFast (LLVM O3/LTO or QBE). A Debug compiler does not establish
equivalent guest bytes by itself; check relevant guest hashes or emitted code
before drawing that conclusion.

```sh
python3 benchmarks/runtime/expanded/run.py \
  --candidate-id current-main-20261003 \
  --compiler-receipt .mylang-cache/runtime-candidate/compiler-receipt.json \
  --work .mylang-cache/runtime-candidate/runner --build-only
python3 benchmarks/runtime/expanded/run.py \
  --candidate-id current-main-20261003 \
  --compiler-receipt .mylang-cache/runtime-candidate/compiler-receipt.json \
  --work .mylang-cache/runtime-candidate/runner --skip-build \
  --output benchmarks/runtime/candidates/current-main-20261003.json
python3 benchmarks/runtime/compare_candidate.py \
  benchmarks/runtime/candidates/current-main-20261003.json \
  --check-artifacts --output benchmarks/runtime/candidates/current-main-20261003-comparison.json
```

`--only CASE ...` produces a subset with both original sizes, all six arms and
the full checksum qualification. The comparison tool accepts this focused scope
without claiming it is a complete assessment. `--quick` is a diagnostic smoke
run and cannot become a candidate comparison. Milestones retain 15 randomized
rounds and three warmups. Calibration and iteration/checksum contracts are
unchanged.

For each selected plan the original frozen winner's executable is hash-checked.
If the current arm has identical bytes, its existing rounds serve as that
reference. Otherwise the original winner runs at the same calibrated count as a
supplemental guest, randomized alongside the six current configurations. This
also applies when the original winner was MyLang: a candidate is never treated
as an unchanged reference just because the backend name matches. Supplemental
reference rounds and warmups are saved separately. No archived timing round is
paired with a new timing round.

The comparison records candidate/frozen-target and candidate/concurrent-original-
reference ratios separately, plus a six-arm current-winner dashboard. Paired
intervals use ratios of medians with the same resampled round indices. An
interval overlapping one is inconclusive. Within 5% means near target for
triage, and does not satisfy the numerical goal. An exploratory interval below
one needs independent confirmation before a demonstrated-faster claim.

Every guest invocation acquires
`/home/epentland/.cache/mylang/runtime-parity-timing.lock`; timings exclude lock
wait. Do not wrap the runner in another `flock` on that same lock, which would
deadlock. CPU 2 remains the timing default, with sibling activity/frequency
receipts. Build slots reserve the configured timing CPUs.

Optionally reuse reference executable bytes:

```sh
python3 benchmarks/runtime/expanded/run.py [the same identity/work arguments] \
  --reuse-reference-manifest /path/to/original/runner/manifest.json \
  --expected-reference-manifest-sha256 EXACT_SHA256
```

Both arguments are required. All reference executable, relevant port/dependency
source, and compiler/tool receipts must match. The new identity and build log
record a verified copy and the original build command; they do not claim a new
reference compilation. All MyLang guests are rebuilt. Reuse arguments remain
part of identity, so pass them again with `--skip-build`.

Original winner executables must remain available at the historical paths saved
in the immutable baseline. Missing or changed originals fail rather than
substituting fresh compiler bytes under old identities.

Optional micro/application diagnostics accept both original sizes:

```sh
python3 benchmarks/runtime/expanded/profile.py CANDIDATE.json \
  --cases integer_math call_direct string_equal alloc_short \
  --profiles small large --arms my-llvm my-qbe \
  --output-dir .mylang-cache/runtime-candidate/profiles
```

The default CPU-clock rate is 99 Hz with a four-second per-case duration target.
The profile records actual duration, iteration caps, sample counts, raw loss and
throttle records. Separate cycles/instructions/branch/cache counter captures
either save their counts and scaling fields or explicitly report unavailable/
partial hardware access. These instrumented whole-process runs include setup,
launcher and teardown; they are neither kernel-only attribution nor performance
evidence, and no captured-symbol fraction is called CPU coverage.
