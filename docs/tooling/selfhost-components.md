# Independently compiled Selka components

The first progressive self-hosting component computes informational test
reachability for `tests-for`, `context`, lint notes and checked interface reports. The
normal commands use its native Selka executable. Discovery, source checking,
graph extraction and formatting remain in the Zig host.
The separate `cache-plan` component plans Core dependency closures and reuse of
unaffected test keys. Canonical fact extraction, storage and execution remain in
Zig. The compiler that `zig build` builds compiles both components (GH-D5): there
is no separate seed compiler.

## Build and install

Source builds currently target native Linux and need the repository's pinned
Zig from `.zigversion`, with LLVM support. Ordinary builds and component-only
builds run no Python:

```sh
zig build
```

Installation contains `tools/selka-components`, `bin/selka` and
`libexec/selka/components/{test-index,cache-plan}.json` with their content-named executables.
Keep those directories together when relocating the installation. `--prefix`
selects another installation root. A compiler that finds no component folder
(`bin/selka` copied alone, or an installation built with
`zig build -Dcomponents=reference`, which builds and installs no component) uses
its built-in test index and cache plan and prints one line on standard error, once
per process:

```text
selka: no component folder found; using the built-in test index and cache plan
```

A folder that is present but holds a missing, malformed or wrong component stays
an error.

The coordinator is a small Zig executable; it is built independently of the
compiler host. File identities are hashed through bounded streaming buffers,
including the Zig executable and library tree. Source bytes are not retained in
memory while hashing. Python remains a test-driver/developer dependency only.
The installed host and component need no interpreter, including when `PATH` is empty.

The coordinator always builds with LLVM, ReleaseSafe and the native CPU target.
This avoids the pinned Zig's SHA-256 AVX/SSE transition slowdown while retaining
hardware hashing. ReleaseSafe with Zig's native backend still exhibits the
slowdown, so a custom Zig without LLVM cannot build the coordinator. This setting
is independent of the host's optimization mode and of the components' own build.

The builder compiles each component with the compiler named by `--compiler`; the
build graph passes the `selka` it has just built. That compiler runs with
`SELKA_CACHE_PLAN_MODE=reference` and `SELKA_TEST_INDEX_MODE=reference`, so
building the components needs no component: there is no cycle. A component's key
binds the compiler's SHA-256, the Zig executable and library tree, the native CPU,
the component's sources and the builder's own source closure. A compiler edit
therefore compiles the components again on the next `zig build`. The builder runs the
compiler with `--cpu x86-64-v3` (the AVX2 floor), so a component's code uses no instruction
beyond AVX2 whichever machine builds it and the bundle's components run on any AVX2 machine;
the key names that model and no longer reads `/proc/cpuinfo`, though the toolchain's identity
(`selka native show --digest`) still holds the builder's CPU. Like the compiler
binary, a component has no native-closure identity of its own: the compiler keys
its own builds by its toolchain, and component preparation never fails because a
machine or its libraries are unknown.

Component inputs live under `selfhost/components/{test_index,cache_plan}/`. After an edit:

```sh
zig build components
zig-out/bin/selka tests-for selfhost/components/test_index/tests.selka tests::test_empty_protocol_golden
```

The same builder can be invoked directly:

```sh
zig build component-builder
zig-out/tools/selka-components --root . --zig /path/to/pinned/zig --compiler zig-out/bin/selka
zig-out/tools/selka-components --root . --zig /path/to/pinned/zig --compiler zig-out/bin/selka --uncached
```

`--uncached` recompiles in an empty, stable private build directory and checks
that the same inputs reproduce the stored artifact. That directory,
`<cache>/staging/component`, is the same for every key and every worktree, and
the component key binds the builder's source closure rather than its executable
([build identity](component-protocol.md#core-cache-planner-v1)). `--cache-dir` (or
`SELKA_COMPONENT_CACHE`) chooses the component store, by default
`$XDG_CACHE_HOME/selka/components` or `~/.cache/selka/components`;
`--install-dir` chooses where the selected manifest is published. `--root`
defaults to the working directory; set it when invoking the coordinator outside
the source tree.

### The children of the builder

The component compiler runs in a hermetic environment: every variable but the `SELKA_`
ones and `ZIG`, with the private `ZIG_GLOBAL_CACHE_DIR`, `ZIG_LOCAL_CACHE_DIR` and `TMPDIR` of the build, and
`SELKA_CORE_RUNTIME_CACHE` empty (the per-user object store is not used) and the two built-in modes above. Only the
locations of the stores the component compiler's builds open pass through, when the builder's own environment names them (an empty value, which disables a store,
included): `SELKA_COMPILER_SHARED_CACHE`, `SELKA_TEST_SHARED_CACHE` and `SELKA_STAGE_SHARED_CACHE`
(`inheritedEnvironment` in `selfhost/components.zig`, the list `store_location_variables`). The complete gate names the first
two as stores of its own, and `build-env project` names the third empty, so a gate's component builds never open the user's
stores. These are placement variables: a location is no part of a component's key, and the same inputs give the same bytes
under any of them (`test_store_locations_reach_the_component_compiler_and_change_no_key_or_byte` in `selfhost/test_components.py`,
and `--uncached` above on the real components). `SELKA_FRONTEND_CACHE` is not passed because the build's `--cache-dir` already
holds the front end's caches; `SELKA_CORE_TEST_CACHE`, `SELKA_VERIFICATION_SHARED_CACHE`, `SELKA_STORE_SETTINGS` and
`SELKA_COMPONENT_DIR` name no store the component compiler opens. A builder run with none of them set (by hand, outside a
gate) leaves the component compiler on the per-user stores.

Builds snapshot the component source, key its contents and build recipe, compile
with the compiler, and publish verified artifacts before atomically
selecting their manifest. A failed build returns failure and does not claim that
an older component contains the edit. The previously installed valid component
remains selected until a successful build replaces it.

## Reference, shadow and failure behavior

`SELKA_TEST_INDEX_MODE=reference` selects the original Zig algorithm explicitly.
`SELKA_TEST_INDEX_MODE=shadow` invokes Selka, compares every answer with Zig,
and fails on disagreement. The default is `component`, or `reference` with the
one-line notice above when there is no component folder. Library-only reference
entry points remain useful for bootstrap and tests; production CLI commands
supply an explicit adapter.

`SELKA_COMPONENT_DIR` overrides the directory containing `test-index.json`.
Without it, the host resolves the installed package relative to its executable,
independent of the working directory. In a folder that exists, missing manifests, unsupported schemas,
wrong artifact digests, process failures and invalid responses are command
errors. The host never silently substitutes reference or empty answers: without a
folder it says that it uses the built-in ones.

One command sends one bounded graph request in a private temporary directory.
The host verifies the executable digest, enforces a 30-second deadline and
bounded output, validates the full reply, and removes the temporary directory.
The [wire protocol](component-protocol.md) specifies identities and limits.

## Qualification

The source profile is documented in [bootstrap profiles](../bootstrap-v1.md).
The persisted regression entry points are:

```sh
python3 selfhost/test_components.py --builder zig-out/tools/selka-components --zig /path/to/pinned/zig
zig build test-components
zig build test-component-support
zig build test-units -Dtest-filter=component
zig build test-cli -Dtest-filter='CLI component'
```

Run the pure library/codec tests with the built compiler:

```sh
zig-out/bin/selka test selfhost/components/test_index/tests.selka --force --no-cache
SELKA_CORE_LEAKCHECK=1 zig-out/bin/selka test selfhost/components/test_index/tests.selka --release --verify-facts --force --no-cache
```

`selfhost/tests/run_test_index_component.py --component /path/to/test-index`
checks malformed messages, reply overflow, filesystem/output failures and
randomized graph parity against an independent oracle. It also times a
1,000-node, 100-test, 10,000-edge exchange. Run it against debug and release
component builds with leak checking enabled.

For the first wave, the operating budgets are a median under 50 ms for that
complete debug exchange and under 25 ms of added latency for a small warm CLI
fixture, measured against reference mode. Measure component compile and
unchanged-build times separately. These are local qualification budgets, not hardcoded timing tests.
A real algorithm edit followed by `zig build components` must change the
component artifact while preserving the host executable's digest.

## Scope

`test-index` is a navigation aid. It does not control actual test selection,
execution receipts, compiler object caching or early report replay. The
embedded-only `reference` command retains its pure renderer to preserve its
filesystem-independent contract. The Core runner uses a different dependency
graph, including function references, through `cache-plan`. Its verified identity
binds every relevant cache lookup. `SELKA_CACHE_PLAN_MODE` selects component,
reference or shadow execution independently of `SELKA_TEST_INDEX_MODE`.
The [incremental v2 protocol](component-protocol.md#incremental-core-cache-planner-v2)
supports persisted canonical facts, complete graph generations and unaffected
test-key reuse. Persistent workers, an in-process C ABI and application durable
execution remain separate future features.
