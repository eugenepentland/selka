# Independently compiled Selka components

The first progressive self-hosting component computes informational test
reachability for `tests-for`, `context`, lint notes and checked interface reports. The
normal commands use its native Selka executable. Discovery, source checking,
graph extraction and formatting remain in the Zig host.

## Build and install

Source builds currently target native Linux and need the repository's pinned
Zig from `.zigversion`, with LLVM support. Ordinary builds and component-only
builds run no Python:

```sh
zig build
```

Installation contains `tools/selka-components`, `bin/mylang` and
`libexec/mylang/components/test-index.json` with its content-named executable.
Keep those directories together when relocating the installation. `--prefix`
selects another installation root. A copied host executable alone is incomplete
for commands that need the component; other compiler commands do not launch it.

The coordinator is a small Zig executable; it is built independently of the
compiler host. File identities are hashed through bounded streaming buffers,
including the Zig executable and library tree. Source bytes are not retained in
memory while hashing. Python remains a test-driver/developer dependency only.
The installed host and component need no interpreter, including when `PATH` is empty.

The coordinator always builds with LLVM, ReleaseSafe and the native CPU target.
This avoids the pinned Zig's SHA-256 AVX/SSE transition slowdown while retaining
hardware hashing. ReleaseSafe with Zig's native backend still exhibits the
slowdown, so a custom Zig without LLVM cannot build the coordinator. This setting
is independent of the host's optimization mode and the seed/component recipes;
it does not change the Zig pin or the progressive self-hosting boundary.

The builder provisions a separate ReleaseFast seed from the immutable source
commit in `selfhost/component-seed.json`. It verifies the source archive,
toolchain and locally qualified executable before reuse. The first seed build
is substantial; subsequent component builds reuse it. The seed needs the pinned
Zig toolchain, Git history containing the pinned commit (or a verified source
archive below), and the repository's sibling `guardian-zig` build dependency.
The original historical `selfhost/stage0-pin.json` is unchanged.

Component inputs live under `selfhost/components/test_index/`. After an edit:

```sh
zig build components
zig-out/bin/mylang tests-for selfhost/components/test_index/tests.my tests::test_empty_protocol_golden
```

The `components` step never depends on the current host executable. The same builder
can be invoked directly, or installed before provisioning a seed:

```sh
zig build component-builder
zig-out/tools/selka-components --root . --zig /path/to/pinned/zig
zig-out/tools/selka-components --root . --zig /path/to/pinned/zig --uncached
```

`--uncached` recompiles in an empty, stable private build directory and checks
that the same inputs reproduce the stored artifact. `--cache-dir` (or
`MYLANG_COMPONENT_CACHE`) chooses the seed/component store; `--install-dir`
chooses where the selected manifest is published. Source distributions without
Git history can supply `--seed-source /path/to/pinned-seed.tar`, a `git archive`
of the exact pinned commit. Its digest must match the pin. For the ordinary build,
use `zig build -Dcomponent-seed-source=/path/to/pinned-seed.tar`. Archive extraction
is native and does not require an external `tar` program. `--root` defaults to the
working directory; set it when invoking the coordinator outside the source tree.

Builds snapshot the component source, key its contents and build recipe, compile
with the independent seed, and publish verified artifacts before atomically
selecting their manifest. A failed build returns failure and does not claim that
an older component contains the edit. The previously installed valid component
remains selected until a successful build replaces it.

## Reference, shadow and failure behavior

`MYLANG_TEST_INDEX_MODE=reference` selects the original Zig algorithm explicitly.
`MYLANG_TEST_INDEX_MODE=shadow` invokes Selka, compares every answer with Zig,
and fails on disagreement. The default is `component`. Library-only reference
entry points remain useful for bootstrap and tests; production CLI commands
supply an explicit adapter.

`MYLANG_COMPONENT_DIR` overrides the directory containing `test-index.json`.
Without it, the host resolves the installed package relative to its executable,
independent of the working directory. Missing manifests, unsupported schemas,
wrong artifact digests, process failures and invalid responses are command
errors. The host never silently substitutes reference or empty answers.

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

Obtain the qualified seed with `zig-out/tools/selka-components --seed-only`.
With that executable, run the pure library/codec tests:

```sh
/path/to/seed/mylang test selfhost/components/test_index/tests.my --force --no-cache
MYL_CORE_LEAKCHECK=1 /path/to/seed/mylang test selfhost/components/test_index/tests.my --release --verify-facts --force --no-cache
```

`selfhost/tests/run_test_index_component.py --component /path/to/test-index`
checks malformed messages, reply overflow, filesystem/output failures and
randomized graph parity against an independent oracle. It also times a
1,000-node, 100-test, 10,000-edge exchange. Run it against debug and release
component builds with leak checking enabled.

For the first wave, the operating budgets are a median under 50 ms for that
complete debug exchange and under 25 ms of added latency for a small warm CLI
fixture, measured against reference mode. Measure component compile and
unchanged-build times separately; the cold seed build is outside the component
edit loop. These are local qualification budgets, not hardcoded timing tests.
A real algorithm edit followed by `zig build components` must change the
component artifact while preserving the host executable's digest.

## Scope

This component is a navigation aid. It does not control actual test selection,
execution receipts, compiler object caching or early report replay. The
embedded-only `reference` command retains its pure renderer to preserve its
filesystem-independent contract. The Core runner uses a different dependency
graph, including function references. A later
migration must preserve that graph and add component identity to every relevant
cache lookup before enabling reuse. Persistent workers and an in-process C ABI
are separate future features.
