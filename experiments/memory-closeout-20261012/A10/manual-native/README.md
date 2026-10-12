# Counter-only native replay

`manual_native.py` provides a separately identified native build for the missing
size-aligned C0 counter supplement. It does not repair, replace or relabel the
frozen compiler. A09 retains all eight original failed native builds and all 15
original uninstrumented timing binaries.

The old driver deletes uncached unit objects before linking on the current host.
C0's `--release --emit-llvm` has already written the exact single native unit at
that point: `pipeline.zig` passes `units[0].llvm` both to the driver and the LLVM
output file. No LLVM transformation, repartitioning or guest-source migration is
performed by this adapter.

Runtime preparation reads the exact supplied Git revision, uses the runtime
fragment order in its `driver.zig`, and verifies those concatenated bytes against
`driver.runtime_source` in the frozen ELF compiler. The number-text object is
extracted directly from `number_runtime.prebuilt` in that compiler; no helper is
rebuilt from a different revision. A tiny exporter invokes the unchanged revision's
`count_runtime.source`, with its exact header/body/anchor checks, then adds the
original zero-RC macro prefix. Every source, exported runtime, object, tool and
compiler hash is recorded. A wrong source/compiler runtime pair refuses.

The native commands reproduce the reviewed C0 and Support6 release recipe:

- Runtime: `zig cc -c -O2 -g0 -falign-functions=64`, native-link target and CPU flags,
  `-std=c11 -pthread`.
- LLVM: `zig cc -c -O3`, the same target/CPU flags, `-Wno-override-module`.
- Link: `zig cc -O3`, the same target/CPU flags, `-pthread -Wno-override-module`,
  runtime object then program object, exact embedded number object when required,
  and `-lm` only for the original sine/cosine dependency condition.

Target is `x86_64-linux-gnu.2.31`; CPU flags are `-march=native -mllvm
-x86-experimental-pref-innermost-loop-alignment=6`. Layout/sanitizer overrides and
foreign C inputs are outside this narrow adapter. Actual argv, cwd, tool output,
private Zig cache locations and object hashes accompany each build. This route
makes no native-cache admission claim, changes no host closure check and never
writes into the frozen compiler installation or its old native caches.

Call `prepare(repository, revision, compiler, zig, directory)` once per exact
compiler/runtime identity, then `link(runtime_dir, llvm, output, directory)` for
each preserved counted release LLVM file. Both accept `Path` objects. Output
paths must be fresh. CLI equivalents are `prepare` and `link` subcommands; each
must run inside an existing shared build admission. There is no nested admission.
A09's supplement must bind the original source/input/LLVM producer identities and
retain its separate ordinary build-failure records.

`validation.json` records two intermediate Support6 controls. Normal compiler
builds and manual-native binaries from their exact emitted LLVM produce identical
complete counters-v1 documents and expected output for the four-million-lookup
JSON array workload and a 513-element parallel workload repeated 32 times with one
worker. Both have RC0 and no managed exit leaks. The shorter parallel control is
adapter validation, not the calibrated full-workload result. Wrong runtime and
wrong LLVM ABI inputs refuse before native execution. Raw inputs, native argv,
reports and outputs are under `raw/`, compressed without changing their identities.

A09 owns the subsequent fresh 15-case C0 supplement. The final candidate must use
this same adapter with its own exact runtime and embedded number object, after
reviewing its driver recipe and repeating the normal/manual equivalence controls.
The intermediate controls are not final C1 qualification. These binaries and
incidental execution durations are never used for wall-time or RSS comparisons.
Allocation counts remain distinct from copy-event instrumentation, whose later
recursive-copy accounting correction is already recorded by A09.
