# D9 experimental RC selector inventory — 2026-09-26

This is a bounded, read-only inventory of source `f74abcce`, for the serial
wiring change owned by the integration agent. Default programs continue using
GC until RC acceptance. Legacy sharing always uses GC. No selector, runtime
or compiler implementation is included here.

## Resolution and the compiler-facing API

Recommend a dependency-free runtime-mode contract, separate from value
semantics. The emitter should read only the resolved process selection:

- `enabled() bool`: RC is selected.
- `counting() bool`: RC instrumentation is selected, false under GC.
- `identity() []const u8`: a canonical versioned tag, initially `gc-v1`,
  `rc-v1` or `rc-v1-counting`. The `v1` is the RC ownership/call/runtime ABI,
  not a source-language version. Bump it when that contract changes.
- One small `Selection { mode, counting }`, with getter/setter for startup
  and test save/restore. Ordinary lowering never changes it.

A mode bit alone cannot distinguish RC ABI revisions. The existing
`value_semantics` API has `enabled`, `counting` and environment carriers; it
currently has no `keyByte` function. If the serial interface prefers a compact
key byte, pair it with an explicit ABI version in every persisted identity.
No compiler branch should independently parse environment variables.

A concrete initial carrier is `MYLANG_RUNTIME=gc-v1|rc-v1|rc-v1-counting`.
An experimental CLI selector can normalize into that carrier; no project
configuration field is needed for the first experimental lane. Resolve value
semantics first. An explicit RC request with legacy sharing should diagnose the
incompatible request; an inherited experimental RC setting must not change
legacy behavior: normalize that legacy invocation and its children to GC.
Unknown carrier versions must fail clearly, rather than silently selecting GC.

Settle and export the effective selection before any frontend/build/test cache
lookup. Existing `main_value_semantics.settle` restarts the process to put the
resolved mode into the actual inherited environment; mutating only its Zig map
would miss children spawned with implicit process inheritance. The RC wiring
must preserve that property, with no restart loop between the two selectors.

The native-build Zig module deliberately cannot import the `mylang` module's
implementation (`qbe_build_cache.Contract` documents this boundary). Share an
independent contract module once at the build graph boundary, or pass the
normalized selection explicitly and decode the same versioned carrier in the
driver. Do not create two unsynchronized mutable globals. Host applications
that enter the builder directly need the same normalization/validation.

## Process and artifact boundaries

| Boundary | Current path | Required RC propagation |
|---|---|---|
| Command startup | `main.dispatch`, `main_value_semantics.settle`, `wiring/value_semantics.zig` | Resolve once before identities; preserve `--` guest arguments and explicit/inherited mode precedence. Internal commands must honor inherited selection even when their public parser accepts no RC flag. |
| Build frontend | `qbe_build.frontendCompiler/build` invokes self or `MYLANG_HOST_COMPILER` with `emit-qbe`/`emit-project-qbe` | Export the resolved selection; reject a returned manifest whose runtime contract differs. An older external compiler can ignore a new environment name, so inheritance alone is insufficient. |
| Reused manifest | `qbe_build.build` consumes internal `--manifest-file` without a frontend child | Validate runtime/ABI identity before compilation or linking; never assume this bypass inherited the current selector. |
| Tests | `native_test_session` spawns `list-interfaces`, `native-test-graph`, `check-project`, `emit-project-qbe`, `native-test-compile`, and `build --library` | Every child, selective manifest and reusable test result must share the normalized selection; keep the guest runner's ABI checks aligned. |
| Other compiler children | `doctest_command`, `packages_command.runCommand`, `invoke_command`, host frontend paths | Preserve inherited mode, including implicit-environment spawns and legacy doctest directives. Long-lived/check-session and direct library entry points must not reuse state across a changed mode. |
| Native C providers | `qbe_build.State.provider` clones environment and compiles provider C in private Zig caches through `Cache.compileC` | Compile against the selected runtime headers/definitions; ownership-aware provider adapters must advertise the contract. A fresh provider compile alone does not establish compatible return ownership. |
| Copied-host and foreign adapters | `qbe_host`, `qbe_build_host`, `qbe_build_outputs`, `qbe_build_embed`, wire/codecs/dispatch generation | Stamp their artifact identity and apply the owned guest-result conversion contract. Raw C pointers are not implicitly RC allocations. Exports and function values use the canonical owned-result entry. |
| Guest launch | `runtime_options`, `qbe_build_spawn`, `native_run`, native test executors | Runtime choice is baked into the binary/library contract, not switched by `MYLANG_OPTIONS` at launch. Guest runtime controls cannot reinterpret an allocation header as another heap mode. |

Current native manifests identify `qbe-units-v1` and
`mylang-qbe-native-v8`; `qbe_build.validate` checks those strings. Add an explicit
runtime/ownership contract field or an equally unambiguous versioned ABI variant,
and validate it on all manifest consumers. Missing tags may mean the historical
GC ABI only in a deliberately documented compatibility path; they must never
be accepted as RC. Add a link/load check for externally supplied guest libraries
and ownership-aware provider artifacts; keep source-level legacy GC graphs out
of an RC heap even when machine layouts happen to match.

## Cache and hash inventory

| Cache/artifact family | Existing identity site | Required dimension |
|---|---|---|
| Frontend/semantic/receipt namespace | `main.build_identity`, `valueSemanticsIdentity`, `cowCountingIdentity`; `cache_key.Contract` | Effective runtime tag including ABI version and instrumentation, before opening stores. This conservatively separates checked facts too, avoiding accidental reuse of native stand-ins. |
| Lean whole-project emission replay | `main.manifestReplayTicket` | RC identity in slot/key as well as store namespace. |
| Native stand-in records | `qbe_fragments.recordKey` | RC identity alongside value semantics/COW counting. |
| Function emission keys | `qbe_fragments.Keys.local`, `Flags`, `Keys.body/interface`, final allocation-fact keys | RC mode/ABI changes emission even if bytecode is unchanged. Future owned/borrowed entry certificate, result shape and dependencies must enter caller-visible interface facts; callee changes must invalidate callers. |
| Validated run manifest | `native_run_cache.keyFor/manifest_generation` | RC tag; this path currently explicitly frames `MYLANG_VALUE_SEMANTICS` and can bypass ordinary emission. |
| Test libraries/results | `native_test_environment.compiler_inputs/capture`, `native_test_session` fingerprints and receipts | Normalized RC carrier, ABI and counting state; an unchanged compiler binary can build both modes. Audit import/query memo dependencies before allowing cross-mode reuse. |
| Native object/LLVM/assembly/link cache | `qbe_build.environmentJson`, `qbe_build_cache.Contract/key`, `native_run` executable keys, `qbe_build_link` | Mode/ABI/counting in effective native environment/contract; do not rely solely on changed IL because runtime and generated C may otherwise be identical inputs. Preserve canonical/shadow cache-contract agreement. |
| Installed runtime archives | `qbe_build.runtimeInstalledHash/installedRuntime/resolveRuntime`, `runtime_flavors`, `emitRuntime` | Include runtime mode/ABI/counting in addition to source hash, toolchain, optimization, target and QBE/LLVM/full/thin-LTO flavor. A content hash of one source tree cannot distinguish two preprocessor modes. |
| Runtime source bundle | `build_qbe_assets`, `qbe_build.runtime_units`, `build.zig` install/prebuild | Bundle the new C/header closure and explicitly compile/link required units. The asset tool includes C/headers automatically, but the runtime unit list is explicit. Mode-specific C flags must reach both archive build paths and provider/generated C compilation. |

`qbe_build.generation_identity` currently identifies native ABI, driver and
bundled source content, while entries include the build environment. Modes can
share that generation if every entry is fully partitioned; changing generations
per selector is not necessary and would evict the other mode's warm entries.
Likewise a shared materialized source tree is safe when its bytes are identical;
compiled runtime archives must still be partitioned.

The installed formatter object may remain shared only if its source and ABI are
proved mode-independent. Use conservative separation initially. A missing RC
prebuilt archive must compile an RC archive from bundled source, never fall back
to a matching-looking GC archive. Keep QBE and all LLVM/LTO archive flavors in the
selection test matrix. New RC helpers also need accurate declarations available
to `qbe_build_llvm_runtime.Table`; do not guess LLVM signatures.

`build_qbe_assets.driverFile` currently selects `qbe_build*`, `native_link*` and
`qbe_frame_map.zig`. If a newly named shared selector/ABI module changes native
compilation or linker behavior, explicitly include it in that narrower driver
identity, not only the broad compiler identity. Runtime header bytes already
contribute to the runtime content hash.

## Serial wiring acceptance and handoff

Before parallel implementation, freeze the selector API, runtime manifest tag,
C ownership ABI version and compiler call-contract representation together.
Compiler work then depends only on that interface and the versioned native fact
surface. The integration owner retains CLI/environment/build/install wiring.

High-value wiring tests are: GC default and explicit GC; RC value mode; explicit
RC/legacy rejection plus inherited-RC legacy normalization; a flag after `--`
remaining a guest argument; normalized mode observed by every compiler child;
GC→RC→counted RC→GC reuse under one cache root; fresh and reused `--manifest-file`
validation; old external compiler/provider contract refusal; installed/fallback
runtime selection for both backends; and borrowed-entry certificate edits
invalidating caller fragments. Keep GC and legacy behavior unchanged while RC
is experimental, and never treat a GC fallback as a passing RC test.
