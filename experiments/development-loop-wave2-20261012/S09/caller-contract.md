# Bootstrap evidence diagnostic adapter

Call `bootstrap_evidence_bridge.evaluate_bootstrap(root, cache, expected_commit,
zig=...)` through S05's request-local allowlist. This is a developer qualification
helper; it is not part of source installation or an installed compiler command.
It never launches the bootstrap compiler, changes an external installation,
acquires admission or writes an external cache.

The reviewed owner protocol/source contract is frozen at
`dff9304b9cd7bc72e66f9feb20f1b05281d67333`; another commit requires a contract
review and fails conservatively until supported.

The result schema is `bootstrap-evidence-diagnostics-v1`. `complete` is always
false: matching source, authentic artifact bytes and old passing subsets cannot
establish full bootstrap or performance. `status=partial` means the diagnostic
observation succeeded; `status=invalid` means at least one evidence boundary
failed. CLI exits zero for partial observations and two for invalid ones. Neither
status grants S05 a bootstrap-completion capability. Unknown owner evidence stays
missing. A caller-supplied JSON boolean is never accepted as qualification.

`inputs` lists exact paths, roles, content digests and byte counts. The caller must
bind these paths, the adapter's actual loaded code, expected owner source, mode,
ABI, seed, tools and environment to its request-local live snapshots before using
them. The helper rechecks content, metadata/alias tokens and source membership;
it provides no watcher authority or reusable success after returning. Unsupported
parent-symlink ABA or mutations after its final observation need the caller's
live authority; this adapter cannot waive that requirement. Untracked component
sources participate in the complete component source map.

Producer-format2 receipts are checked against their canonical sorted compact
ASCII JSON key and selected manifest digest. The exact cache-root field remains
part of identity. Seed recipe keys select existing locally qualified receipts;
embedded qualifications must match those receipts and the actual seed executable.
One request shares immutable verified seed preparation across the seven packages;
conflicting qualifications under one recipe fail. Final content checks remain
fresh. Full live tool-library and runtime/ABI qualification is explicitly not
established by this bridge.

Both archived receipt formats are adapted directly, with compressed *and*
uncompressed hashes and declared lengths checked. Archives are never executed or
extracted. Duplicate JSON keys, unsafe basenames, duplicate archive entries,
missing or altered executable/receipt bytes, wrong owner source, dirty tracked
source, source ABA and late source membership fail conservatively. Streaming
file reads use 64 KiB chunks. Limits: JSON/source 8 MiB, component 64 MiB,
seed/tool/host 512 MiB, compressed archive 32 MiB, decompressed archive 128 MiB,
128 archives per receipt, 4096 component files and 2 GiB aggregate read work. Bound
exhaustion produces invalid diagnostics, never complete success.

The current read-only external observation authenticates seven selected artifact
chains and 60 archived gzip files. Parser's diagnostic_tests.my differs from its
receipt source map. Body has 36 changed source paths and selects schema 10 despite
source schema 11; its 32 displayed paths explicitly report truncation. Five other
package source maps agree, which is content evidence, not adopted-stage parity.
The archived body-wave receipt says full_gate pending; gate-repair receipt has no
passing integrated gate. The observed native host hash is recorded but no current
source recipe/ABI qualification is supplied by this helper.

## Required owner deliverables

Bootstrap owner, coordinated through S09/root, must supply:

1. A clean frozen source revision, rebuilt source-current schema 11 package and
   parser fixture closure, authenticated native host build receipt and qualified
   seed/tool/resource/runtime/ABI closure.
2. Machine-readable complete language/compiler ownership, correctness,
   diagnostics, facts and leaks qualification under the exact adopted modes;
   unsupported forms fail visibly, without native fallback.
3. Seed→stage1→stage2→stage3 manifests, reproducibility/artifact equivalence and
   corpus/diagnostic parity. Current partial components do not substitute for
   these stage outputs.
4. Owner-approved migration from legacy FD30 admission to current exclusive
   timing, preserving authentication/provenance and every mandatory workload.
5. Raw repeated samples and every-workload median **and** p95≤1.5× the frozen Zig
   reference. A passing short runtime row or instruction proxy cannot close a
   failed compiler/test row.

Memory owner is active at the observed 3cc4953b0 revision with dirty integration
work. A07 must provide the frozen ABI/ownership contract, A08 the compatible cache
identities, A09 the coordinated timing window and A10 the explicit rollout
contract before related shared edits. `memory-owner-observation.json` records a
point-in-time status and committed ledger hash; it does not accept an uncommitted
candidate or interpret active cherry-pick conflicts as a final owner failure.
No ownership transfer or shared-source adoption was authorized in this wave.
