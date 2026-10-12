# Authenticated cleanup-only seed candidate

The immutable historical seed remains unchanged. Candidate source:
`1665d74029c406dd5b90807186a752ebac6bcbb8`, parent
`0689d3407c17df34915aeb2a92e309af3a04921c`, local branch
`codex/dl-wave2-S09-native-seed-20261012`. This backports the already-approved
owner repair from `6327267249fdfbedab4093a5787033a5485a442d` to the actual seed.
Only three source files change: exact production cleanup delta, the existing
A01 regression adapted to historical Unit's number/math/counting fields, and its
root import. No language, runtime ABI, memory mode, tool-trust or default changes.

`seed-source.patch` records that source delta. `candidate-pin.patch` proposes the
new source/archive identities through the existing native seed contract; **S09
has not applied it or changed any production seed, artifact, cache or manifest**.
This does not add a new seed override, overlay, host substitution or trust bypass.
Root will review qualification/provenance for the same approved cleanup behavior.

Exact Git archive SHA256:
`2632c3ddd2992a989a08e1a070288901c58391eade2e330af5fb14f291d063d5`,
1,404,928,000 bytes. The archive lives in owned `.tmp/S09-native-seed-candidate.tar`;
large binaries/archives are not committed as evidence. The normal native builder
read a private fixture's candidate pin, verified this archive, extracted it,
built independent native ReleaseFast `affected-compiler -j1`, and produced a
genuine qualified receipt. It never used the installed repaired host as a seed.
Seed executable SHA256:
`bd55fd21824ef40ed557e902d3f6b63d15185a3eeb625e443dc87a64f45c2b8d`.
`qualified-seed-receipt.json` is copied directly from that genuine receipt;
all 621 source-file digests and the executable were independently rechecked.

## Passed bounded qualification

- Historical-source native regression: 2/2 selected tests passed with current shared
  admission and test-rerun=true, including repeated unproved-tool multiunit links
  and success/failure cleanup. An initial invocation used the historical wrapper;
  its observation is retained but excluded from acceptance. Production source and
  archive were not changed to repair the qualification launcher.
- Real test-index pure tests: 6 debug + 6 release, with fact/leak checks and no cache.
- Real cache-plan pure tests: 14 debug + 14 release, with fact/leak checks and no cache.
- Release and installed executables passed both existing native protocol/property/
  hostile-frame oracles: test-index 19 malformed cases and 100 random graphs;
  cache-plan 21 malformed cases and 102 oracle graphs, including 100k-node closure
  and retained-index work controls. No inventory was trimmed.
- Normal builder `--uncached` rebuilt both artifacts and checked exact byte equality:
  test-index `94b2460f88bcacc1381843e133861b2be35fa1ec79a1372e67814c0f2aa6f001`;
  cache-plan `e9182cf3abe2cb596df7689f0c0ba3adedcb326c6ff6e2966398e4d628dcf1ce`.
- Five actual builder rejection controls passed using separate private copies:
  corrupt/missing seed executable, malformed receipt, changed recipe and wrong
  immutable source archive. Every case returned failure and no selected seed path.
- Seed source commit passed all 88 normal Guardian checks. Candidate pin patch passes
  read-only application checks. No active pin was refreshed automatically.

All substantial native work used current shared admission, private source caches
and on-disk TMPDIR. `qualification-results.json` separates queue and execution.
Real component qualification took 45.94s after 125s queue, maximum child-process
RSS 287032KiB. Forced native rerun took 0.70s after 86s queue. Reproducibility took
12.05s after 30s queue. Rejection controls took 2.04s with zero queue. These are
ordinary operational costs, not isolated median/p95, aggregate concurrent memory
or speedup claims. Native provisioning's recorded queue was 121s; its separate
compile wall/RSS were not instrumented and remain unavailable. No timing window,
full gate, self-built stage chain or strict ratio measurement was run.

## Source availability and archive identity

The exact seed source object is presently local-only. Root can retain 1665d740 as
an explicit merge parent of the reviewed integration while preserving current
source, then select the reviewed pin. A later published **full clone** of that
integration includes this parent; ordinary provisioning already calls
`git -C ROOT archive PIN.commit`, so no new retrieval mechanism or separate seed
ref is required. No main/push/publication was performed. Until that source object
or its exact verified archive is distributed, the pin is not deployable to fresh
clones. Shallow clones/source packages may use the existing verified
`--seed-source` / `-Dcomponent-seed-source` route with this exact archive.

Archive identity is not tree-only: inspected PAX comment is the exact 1665d740
commit SHA and archived file mtimes equal its commit time. `archive-metadata.json`
records this inspection. Different commit metadata can change the archive hash
even for identical file trees. Keep the exact seed object and digest; do not
substitute the later integration merge SHA or regenerate a different seed commit.

## Explicit cache handoff

All S09 native checks have stopped. **Coordinator has exclusive use** of:

`/home/epentland/ai/canopy/mylang-dl-wave2-20261012-S09/.tmp/S09-native-component-cache`

Use supported `MYLANG_COMPONENT_CACHE` at that exact path. Seed record:
`seeds/478fafe1514081b9d0069708251fc32f6f5590e03b9de0528e211133e96bae8d/receipt.json`.
Component artifact records:
`artifacts/d3a1e456091c068c57590200c93339c81f7dd7b51c916359d7fd0fba1cbbf37a/receipt.json`
and
`artifacts/f3478f0f0ae39b5a6e7f977e1037f73f8ca069c5da570d91ff22b578710b60eb/receipt.json`.
The native builder will reauthenticate recipes/binaries before reuse. Cache-root
path and coordinator executable digest are producer identity inputs; a changed
coordinator can rebuild components while reusing the qualified seed. No mutable
Zig cache is copied or shared across source paths/generations. S09 will not invoke
the builder or mutate this store again without a new ownership assignment.

This is qualification of a narrow native seed repair and two existing components.
It does not close DL7, full compiler bootstrap, memory-team rollout or every
selfhost workload's median/p95 ≤1.5× requirement. Root/S10 still must run required
complete verification on the exact reviewed final candidate.
