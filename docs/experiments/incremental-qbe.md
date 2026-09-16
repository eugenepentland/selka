# Incremental QBE native compilation

QBE compiles independently linkable guest functions. The driver caches each
assembled object across compiler processes and links the current function set.
The ordinary frontend now reuses checked ordinary bodies, symbolic generic
templates and concrete specializations by default, but `mylang build` still lowers
the complete checked program and renders its QBE units on every build; the
object cache reuses assembled per-function objects. Native object reuse is the
part this page documents; per-function lazy lowering/emission, incremental native
linking and hot reload remain open ([implementation
status](../audits/velocity-implementation/final-status.md)).

## Build and run

Linux x86-64 (`amd64_sysv`) is the supported native target. QBE is part of this
build: `zig build` compiles the vendored release under `vendor/qbe` (version
pinned in `.qbeversion`) with the repository's pinned Zig toolchain and installs
it as `zig-out/bin/qbe`, beside the compiler. Nothing else has to be installed
and no Python is involved:

```sh
zig build
zig-out/bin/mylang build examples/factorial.my -o /tmp/factorial --report
/tmp/factorial
```

`mylang build` invokes QBE and Zig directly. The installed compiler embeds its
native runtime sources and adapter generators, so it builds from any working
directory. QBE is resolved in this order: `--qbe /path/to/qbe`, a `qbe`
executable sitting next to the running `mylang`, then `PATH`. The working
directory never selects a build tool, so builds outside this checkout behave the
same as inside it. Zig is resolved from `--zig /path/to/zig` or `PATH`.

See `vendor/README.md` for the upstream archive, its checksum, and how to move to
a newer QBE release.

Use `--run` instead of `-o` to execute a temporary native binary:

```sh
mylang build examples/factorial.my --run
mylang build examples/factorial.my --run -- --max-steps=100000 --gc-stress
```

The program inherits stdin, stdout, stderr, and the working directory. Its exit
status is returned by the build command. Temporary executables and build files
are removed after execution, including runtime traps and child termination;
compiled object cache entries remain reusable. No executable manifest is kept.
Runtime options go after `--`. `--run` cannot be combined with `-o` or `--library`.
When combined with `--report`, the build report goes to stderr so stdout contains
only the program's output.

For a module entry, add `--project`. `--library` produces a shared library with
native embedding APIs. Executables can link a trusted C provider using
`--provider adapter.c`; libraries receive providers through run options.
`--cache-dir` selects artifact storage (default `.mylang-cache/qbe`).
`--mode Debug` or `--mode ReleaseFast` controls C runtime optimization and cache
identity. QBE uses its normal pipeline in both modes. `--target amd64_sysv` makes
the supported target explicit; `mylang build --help` lists the build options.

```sh
mylang build examples/python-word-count/main.my --project -o /tmp/word-count
mylang build main.my --project --library -o /tmp/guest.so
mylang build main.my --provider adapter.c --mode ReleaseFast -o /tmp/app
```

The previous `scripts/qbe.py` driver was folded into `mylang build` and the
Zig-native golden parity harness; its cache namespace and Python tooling are gone.

Execution accepts `--max-steps=N`, `--max-frames=N`, and `--gc-stress`. Defaults
are 10,000,000 steps and 1,024 frames. Guest traps return failure without
terminating an embedding host; each call owns isolated execution state.

## Implementation

`native_ir.zig` analyzes typed operand states and control flow independently of
QBE. `native_types.zig` owns native type layouts, canonical names, layout hashes,
and copy/trace/drop properties. QBE operation modules consume these contracts.
Semantic checking and ownership validation remain frontend responsibilities.

The implementation includes direct scalar arithmetic and float operations,
records, arrays, variants/results, domains, generic instances, callbacks,
references and slices, managed lists/strings/dictionaries, owned buffers, pools,
regions, external capabilities/resources, and copied host calls. Typed JSON uses
the existing normative parser/codec bridge without linking a VM dispatcher.
Generated C contains runtime descriptors and ABI/boundary adapters, rather than
C implementations of guest function bodies.

The precise native collector follows typed descriptors and explicit shadow
roots. Managed containers keep stable headers and contiguous typed storage.
Owned containers release their storage explicitly; nested owner destruction uses
an allocation-free worklist. Resource teardown invokes trusted release callbacks
and preserves ownership across failed completion. Runtime helpers propagate
sticky traps and restore roots on failure.

The native contract is `mylang-qbe-native-v3`. Aggregate values larger than
4,096 bytes pass through pointers; large results use caller-owned output storage.
Functions with more than 128 parameters, or more than 4,096 bytes of native ABI
parameters, receive a packed vector of scalar bits and aggregate pointers.
Ordinary aggregate parameters retain value semantics through callee snapshots.
This internal ABI is separate from the public copied-value embedding API.

Large guest frames use execution-owned heap storage instead of native stack
allocations. Execution runs on a dedicated guarded stack, with native stack and
logical frame budgets producing `R_FRAME_LIMIT`. Unsupported lowering still
produces `E_QBE_UNSUPPORTED`; execution never falls back to another backend.
QBE is now the only native backend: the C emitter, its `emit-c`/`emit-project-c`
commands and `scripts/native.py` were removed on 2026-09-13.

## Object reuse and diagnostics

`emit-qbe` and `emit-project-qbe` produce a versioned JSON manifest with separate
function IL, stable linker names, source-location tables, typed descriptors, and
public-interface metadata. An error produces no partial manifest.

Function symbols derive from qualified semantic names. Function IL uses local
instruction numbering and stable callee symbols. Function-object keys contain
IL, ABI version, compiler/tool fingerprints, target, mode, and runtime/driver
fingerprints. Cache hits verify object checksums; corrupt or missing entries
rebuild. Compiler/runtime changes conservatively invalidate cached objects.

Those fingerprints are established without rereading large inputs on each build.
The compiler identity and the runtime-tree content hash are computed when the
compiler itself is built — over its own sources, the Zig version and the optimize
mode — and embedded as constants; external tools are identified by path, size and
modification time. Rehashing a multi-hundred-megabyte toolchain per build used to
cost far more than the native work it guarded.

## Bundled runtime inputs

The compiler embeds only what a native build compiles: its runtime C sources and
headers, plus the Zig runtime units the driver builds and their transitive
`@import`/`@embedFile` closure. Compiler tests and guest fixtures are not bundled.

A build materializes that tree once, into `<cache-dir>/runtime/<content-hash>/`,
and reuses it on every later build in that cache. Extraction stages into a
private directory and renames it into place, so concurrent builds sharing a cache
directory never observe a partial tree; a build that loses the race reuses the
winner's tree. Runtime objects compile with the tree's path mapped to a fixed
prefix, so a cached object does not depend on where the cache lives.

Source coordinates live in a separate metadata object. Moving source lines can
update diagnostics while reusing every function object. Type descriptors and
host/codec adapters are independently generated metadata/support objects.

`--report` gives actual compiled/reused function counts, object keys, metadata
reuse, and phase timings. Linking always uses the exact current function set,
so cached deleted definitions do not remain linked. Complete outputs use
same-filesystem replacement. `<output>.qbe-manifest.json` is descriptive and is
not atomically paired with executable publication. Toolchain installations must
remain immutable during a build. Remote cache trust, eviction, and a persistent
semantic dependency graph are not implemented.

## Acceptance and performance

```sh
zig build test-qbe-build
zig build test-qbe
MYLANG_TEST_ASAN=1 python3 scripts/test_native_memory.py
python3 tests/qbe_benchmark.py --compiler zig-out/bin/mylang \
  --c-compiler /path/to/frozen-c-compiler --qbe zig-out/bin/qbe \
  --output /tmp/qbe-performance.json
```

Both QBE steps default `-Dqbe` to the QBE they build from `vendor/qbe`; pass
`-Dqbe=/path/to/qbe` only to test against a different build.

The QBE target exercises the installed `mylang build` command with Python absent
from PATH and the compiler relocated outside the checkout. It checks object-cache
reuse and corruption repair, failed-build output preservation, source diagnostics,
module builds, providers, typed JSON, and shared-library APIs. Other acceptance
checks covered the removed interpreter's VM/native parity, embedding,
managed allocation stress, providers, resources, and normative JSON conversions.
C runtime tests include undefined-behavior checks; the optional memory command
adds AddressSanitizer. That interpreter comparison suite was removed with the VM
on 2026-09-14.

`experiments/qbe-native/suite.json` freezes workload hashes, expected outputs,
five warmups, 21 alternating C/QBE samples, and a maximum QBE/C runtime ratio of
1.10 **for each workload**. Measurements use already loaded libraries, excluding
compilation and process startup. Missing coverage fails the gate. The initial
baseline is retained even when later results improve. Passing these six runtime
workloads is necessary but does not establish complete language or API parity.

The completion run passed `zig build test-qbe`, `zig build test`, and the
AddressSanitizer/UndefinedBehaviorSanitizer native memory tests. The QBE gate
includes 88 lowering cases, 589 VM comparisons across 105 shared native fixtures,
62 provider comparisons, 47 resource lifecycle comparisons, and copied host,
embedding, codec, JSON, and cache acceptance tests.

[Retained completion measurements](../../experiments/qbe-native/completion-results.json)
contain tool fingerprints and every sample. All six frozen workloads passed the
1.10 limit on this Linux x86-64 host:

| Workload | QBE / C median runtime |
| --- | ---: |
| Integers | 0.315 |
| Calls | 0.288 |
| Aggregates | 0.202 |
| Floats | 0.593 |
| Collections | 0.707 |
| JSON | 0.880 |

These measurements exclude compilation, loading, and process startup; they are
acceptance evidence for the frozen suite, not a general performance guarantee.
