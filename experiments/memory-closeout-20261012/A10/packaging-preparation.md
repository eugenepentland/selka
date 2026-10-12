# Independent owned-component build preparation

This is an implemented optional route, not package-wide retirement. No production
owned-compiler pin has been fabricated or selected. The historical manifest
`selfhost/component-seed.json` remains byte-identical.

`selka-components --owned-compiler-pin FILE` requires a separate source manifest
with `memory_mode: "zero-rc-v1"` and the independent native ReleaseFast
`seed-compiler` recipe. The root coordinator added that source-only build step in
`3005e4628`; it must be present in the eventual actual pinned revision. The new
route verifies the archive, Zig executable/library and locally built compiler
exactly as the historical route does, and never adopts the installed host.

The manifest has the existing format, commit, zig, archive_sha256 and recipe
fields, plus memory_mode. Its commit and archive digest must identify the real
qualified integrated compiler revision; a schema describes those fields, not a
placeholder manifest accepted by an installation. The entire pin enters seed
qualification, component flags record zero-rc-v1, guest build passes
`--experimental-zero-rc`, and installed manifests expose memory_mode.

`selfhost/test_component_native.py --owned-compiler-pin FILE` selects the same
independent compiler and explicit ownership flag for pure-language tests and
release protocol probes, then rejects installed component manifests with another
memory mode. Protocol payloads and historical source semantics are unchanged.

Before selecting this route by default, the coordinator must:

1. Integrate the source-only seed step, source/library fixes and A08 component
   migrations, then freeze a real compiler source revision.
2. Qualify both component sources and their pure-language/property/native protocol
   suites, source and emitted ABI, symbols, memory counters and leak checks.
3. Generate the exact immutable archive and its digest, add a **new** manifest
   `selfhost/component-owned-compiler.json` containing that qualified source pin,
   and test a fresh isolated builder cache using the new route.
4. Route root build component provisioning and native qualification through the
   same pin. Register the new manifest in build_test_inputs.zig component_inputs,
   component_builder, component_native and golden cache dependencies as applicable.
5. Requalify installed normal commands and independently provisioned component-only
   builds. Retire the historical active builder selection during milestone 3.

No self-hosting branch was merged and no historical Git seed was rewritten.
The optional compatibility route and ordinary RC defaults are still unfinished
milestones 2/3, even though this packaging preparation is executable.

Worker validation: native coordinator builds successfully; all 21 fake-tool
blackbox tests pass, including pin preservation, recipe independence, actual
mode forwarding, distinct cache identities and malformed-route refusal.
These fake-tool tests establish orchestration behavior, not actual zero-RC
qualification of either installed component.
