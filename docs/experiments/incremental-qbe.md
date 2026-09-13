# Incremental QBE native compilation

QBE compiles independently linkable guest functions. The driver caches each
assembled object across compiler processes and links the current function set.
The frontend still checks and lowers the complete program on every build.
This provides native object reuse; persistent frontend queries, incremental
linking, and hot reload remain separate future work.

## Build and run

Linux x86-64 (`amd64_sysv`) is the supported native target. Install QBE from the
pinned release in `.qbeversion` and use the repository's pinned Zig toolchain.
The language compiler owns the native build driver:

```sh
zig build
zig-out/bin/mylang build examples/factorial.my -o /tmp/factorial --report
/tmp/factorial
```

`mylang build` invokes QBE and Zig directly. Python is not required for application
builds. The installed compiler embeds its runtime sources and adapter generators,
so it can build from outside this checkout. QBE and Zig must still be installed;
`--qbe /path/to/qbe` and `--zig /path/to/zig` select explicit executables.
By default, QBE is resolved from `PATH`, then `.mylang-cache/toolchain/qbe`.

The optional development helper `python3 scripts/install_qbe.py` downloads and
verifies the pinned release archive before building it. Its installed executable
can be selected with `--qbe .mylang-cache/toolchain/qbe`. The official release
archive and checksums are at <https://c9x.me/compile/releases.html>.
Installing QBE is separate from `mylang build`.

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

The previous `scripts/qbe.py` driver remains a development comparison tool. New
application commands use `mylang build`; its cache namespace is independent of
the Python driver's cache.

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
zig build test-qbe-build -Dqbe=/path/to/qbe
zig build test-qbe -Dqbe=/path/to/qbe
MYLANG_TEST_ASAN=1 python3 scripts/test_native_memory.py
python3 tests/qbe_benchmark.py --compiler zig-out/bin/mylang \
  --c-compiler /path/to/frozen-c-compiler --qbe /path/to/qbe \
  --output /tmp/qbe-performance.json
```

The QBE target exercises the installed `mylang build` command with Python absent
from PATH and the compiler relocated outside the checkout. It checks object-cache
reuse and corruption repair, failed-build output preservation, source diagnostics,
module builds, providers, typed JSON, and shared-library APIs. Other acceptance
checks cover VM/native parity, embedding,
managed allocation stress, providers, resources, and normative JSON conversions.
C runtime tests include undefined-behavior checks; the optional memory command
adds AddressSanitizer. The default interpreter test suite does not require QBE.

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
