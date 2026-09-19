# Speed results — mylang port vs the Zig reader

Produced by `bench.py` and `bench_compiler_modes.py` on 2026-09-18. Raw samples:
`evidence/bench.json`, `evidence/bench-compiler.json`. Charts:
`evidence/sexpr-speed-comparison.png`, `evidence/sexpr-speed-compiler-modes.png`.

**Context.** 20 CPUs, load average 1.89 at start; Zig
`0.17.0-dev.1683+5ceec001b` for both sides; compile figures are medians of 3
repetitions, execution figures medians of 25 runs pinned to one CPU with
`taskset`. Input: 927,415 bytes (the real 185 kB EDA module repeated).

**Same work, verified.** On the benchmark input both binaries print the identical
rendering (`sha256 78a74270e2ec8842471e8e1ec5f94c8a42c631f0addec5ac2ec4bb97870240a7`)
and the identical census (`forms=4050 nodes=15105 … value_sum=6544.65235`), so
the execution timing compares the same parse+walk and the same parse+render.

## Compile time (seconds)

The mylang compiler itself is a Zig program, and a plain `zig build` installs it
in **Debug**. The table therefore gives both: first as installed, then with the
compiler built ReleaseFast (the fair comparison).

| implementation | guest mode | cold (all caches empty) | project-cold (toolchain warm) | warm (no change) | after one-constant tweak |
| --- | --- | ---: | ---: | ---: | ---: |
| Zig | ReleaseFast | 79.2 | 12.6 | 0.016 | 11.8 |
| Zig | ReleaseSafe | 79.1 | 11.9 | 0.017 | 11.4 |
| mylang, **Debug compiler** | ReleaseFast | 2.84 | 2.89 | 0.72 | 0.77 |
| mylang, **ReleaseFast compiler** | ReleaseFast | **2.20** | **2.22** | **0.081** | **0.108** |
| mylang, **ReleaseSafe compiler** | ReleaseFast | 2.18 | 2.15 | 0.080 | 0.104 |

Building the compiler ReleaseFast versus Debug changes the *guest* build by
1.3× cold, **8.9× warm**, and 7.1× after a tweak: the compiler's own frontend
cost drops from 0.49 s to 0.04 s per build. ReleaseSafe is within noise of
ReleaseFast for the compiler.

## Execution time (milliseconds per run, 927 KB input)

| implementation | mode | census (parse + walk) | render (parse + print) |
| --- | --- | ---: | ---: |
| Zig | ReleaseFast | 3.80 | 5.60 |
| Zig | ReleaseSafe | 4.10 | 6.06 |
| mylang | ReleaseFast | 274.6 | 314.7 |
| mylang | Debug | 926.2 | 1046.6 |

At ReleaseFast, mylang takes **72× longer** for the census and **56× longer** to
render. Absolute throughput: Zig ~244 MB/s for parse+walk, mylang ~3.4 MB/s.
Execution does not depend on the compiler's own mode (the emitted code is the
same), so these are the installed-compiler figures.

## Where mylang's build time goes (`--report`, ReleaseFast compiler)

| build | frontend | codegen | link | functions | total |
| --- | ---: | ---: | ---: | --- | ---: |
| cold | 0.04 s | 2.13 s | 0.03 s | 66 compiled, 0 reused | 2.20 s |
| project-cold | 0.03 s | 2.15 s | 0.03 s | 66 compiled, 0 reused | 2.22 s |
| warm | 0.04 s | 0.01 s | 0.03 s | 0 compiled, 66 reused | 0.08 s |
| after tweak | 0.04 s | 0.04 s | 0.03 s | 1 compiled, 65 reused | 0.11 s |

The interesting consequence: **mylang's cold build is codegen-bound, not
frontend-bound.** Its own analysis is only ~40 ms; ~2.1 s goes to QBE plus the
assembler/linker over 66 functions, and that cost is identical in every compiler
mode. Warm and tweak builds collapse to cache lookup plus a fixed ~30 ms link.
The one-constant tweak really does exercise the object cache: 1 function
recompiled, 65 reused.

## Reading the numbers

* **Cold, empty toolchain cache**: Zig 79 s vs mylang 2.2 s. Almost all of the
  Zig figure is compiling Zig's standard library into a fresh global cache — a
  property of a cold toolchain, not of the reader.
* **Project-cold, warm toolchain**: Zig 12.6 s vs mylang 2.2 s — mylang ~5.7×
  faster on a clean checkout.
* **Warm, nothing changed**: Zig 16 ms vs mylang 81 ms. Both are cache hits;
  Zig wins by ~5×.
* **After a one-constant tweak**: Zig 11.8 s vs mylang 0.11 s — mylang ~109×
  faster, because its per-function content-addressed cache recompiles one
  function while Zig redoes the module.
* **Execution**: Zig is ~55–75× faster. This is the honest cost of the design:
  the mylang reader builds a GC-managed AST of tagged aggregates with managed
  `str` payloads, where the Zig reader parses into arena-allocated slices. The
  port is a third of the source (1013 vs 3035 lines) and byte-identical in
  behaviour, but it pays for that at runtime.

## Where the runtime gap comes from

An execution-gap audit — phase decomposition, per-operation micro-drivers, and a
patched-compiler counterfactual — is in
[`../../sexpr-audit/RESULTS.md`](../../sexpr-audit/RESULTS.md). Headline: tokenizing
is 92% of mylang's run and 193x slower than Zig's; the generated code costs ~10-54 ns
per trivial operation against Zig's ~1 ns, because every IR instruction carries a
position marker plus a step-budget check that can never fire in an unbounded build,
and because per-instruction basic-block labels block register promotion.

## Caveats

* **mylang has no ReleaseSafe guest mode.** `mylang build --mode` accepts only
  `Debug|ReleaseFast`, so the guest axis cannot use ReleaseSafe; ReleaseSafe
  appears on the *compiler* axis instead (`bench-compiler.json`).
* **Pre-installed runtime.** mylang's cold build reuses the runtime archive and
  format objects that `zig build` installs once per content hash; the Zig side
  compiles std during a cold build. The project-cold column is the fair,
  toolchain-warm comparison.
* **Trimmed Zig project.** `zig-bench/` vendors only the sexpr closure
  (3035 lines including the driver and `infra/fs.zig`), because charging the Zig
  reader for the other ~200k lines of the EDA application would not be a
  comparison of this reader.
* **Compiler install times are informational.** `zig build -Doptimize=...` is
  cache-assisted for the second and later installs (measured 0.5–0.6 s), so
  `install_seconds` in `bench-compiler.json` is not a cold compiler build.
* Wall-clock on a shared machine; load average is recorded in `bench.json` and
  execution is CPU-pinned, but treat sub-10 % differences as noise.
