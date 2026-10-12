# S09 wave2 handoff

B0 `c1857310e0bf623545380c8de24515f1b9970021`.
Implementation/evidence commit `8634ec91d8dac148365bd3412d82daf40e4e4e7b`.
Owned files: only `experiments/development-loop-wave2-20261012/S09/*`.
No external source, cache, manifest, ledger or installed compiler was changed.

## New bridge delivered

Unlike the prior source audit, this wave implements and exercises a read-only
adapter against actual locally qualified seed receipts, selected native artifact
bytes, canonical producer-format2 receipt keys, complete current component source
maps, and both historical compressed receipt formats. It checks content again
before returning, includes metadata/alias and directory-membership changes, and
bounds aggregate read work. Eighteen private adversarial tests pass.

API: `bootstrap_evidence_bridge.evaluate_bootstrap(root, cache, expected_commit,
zig=...)`. Result `bootstrap-evidence-diagnostics-v1` always has complete=false.
The supported owner contract is pinned to
`dff9304b9cd7bc72e66f9feb20f1b05281d67333`; unknown owner revisions require review.
Status partial means diagnostics were authenticated; invalid means a boundary
failed. Neither grants a full-bootstrap capability. CLI returns 0 for partial
observations, 2 for invalid ones. See `caller-contract.md` for scopes and limits.

S05 requested this known-function adapter for request-local long-qualification
diagnostics. It returns 391 input paths/roles/digests/byte counts for the caller's
live snapshots and actual-loaded-code identity. It creates no scheduler, external
store or reusable success authority. Caller source/tool/mode/ABI/environment and
live stability remain mandatory. S05/coordinator own final wiring and declared
test/action inputs; register the private adversarial suite if the adapter becomes
an adopted action dependency. Ordinary gates must not read the active external
installation implicitly.

## Actual observed qualification

`external-evidence.json` is a real, read-only diagnostic result: status partial,
complete=false. It authenticates seven selected manifest→artifact→producer→seed
chains and 60 gzip archives (44 body-wave, 16 gate-repair), checking compressed and
uncompressed digests and declared lengths. The actual qualified seed executable
is `c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`.
Full live Zig-library/runtime/ABI closure is not established by this adapter.

Five package source maps agree with their selected receipts. Parser's
`diagnostic_tests.my` changed; body has 36 changed source paths (32 displayed with
an explicit truncation flag), and its installed manifest selects schema 10 while
its reviewed current source requires schema 11. Source-current semantic stage
adoption is therefore unqualified. Existing source-map agreement is content proof,
not language parity or permission to integrate those stages.

The observed external host digest is
`590fb4260dd4f11fe97efd66f40fc2c4dbf94d7542c84b24bb6b6944585e2ce7`.
Its current build recipe, optimization mode and ABI are not qualified here. The
body-wave archive explicitly says full gate pending; the gate-repair receipt
supplies no passing integrated gate. Both remain historical partial evidence.
No archived counter or JSON boolean is accepted as current full compiler proof.

`memory-owner-observation.json` records active owner revision
`3cc4953b0a2be79fd9c91a6c1ba8e7dc11aa0526`, dirty integration status and committed
ledger hash. All three owner milestones are pending. Staged source and temporary
conflicts were observed during active owner integration; this is a point-in-time
record, not a diagnosis or takeover request. A07 owns ABI, A08 caches, A09 timing,
A10 rollout. Root was notified; no shared-file transfer is assumed.

## Checks and measurement scope

`commands.md` records exact commands and tool identity. Python 3.14.4 runs only
qualification/developer code; source installation and installed commands remain
Python-free. The standard developer environment supplies pinned Zig, private
local cache, on-disk TMPDIR, shared global cache and shared admission.

- Adapter tests: status 0, 18/18 passed; `adapter-tests.log`.
- Actual external diagnostic run: status 0, partial; 391 paths and 1,014,187,527
  streamed bytes including final checks, within 2 GiB aggregate budget.
- Implementation commit: normal whole-tree Guardian hook 88/88 passed under shared
  gate admission, ticket 87, 45 seconds queue. No complete native verification gate
  or timing window was requested.
- Whitespace check passed. `artifact-hashes.json` binds the exact committed files.

No compiler was rebuilt; no seed, host, guest or ratio command was executed. No
cold/warm/edit speedup, measured CPU/RSS, isolated latency, median or p95 is
qualified. Byte work is diagnostic I/O scope, not completed compiler work and
not a performance proxy.

## Actionable owner deliverables and integration order

Integrate the implementation/evidence commit, then this handoff/hash commit.
These unique files need no external source ownership transfer. S05 can consume
partial diagnostics only; root owns any shared action registration.

Bootstrap owner must supply a clean frozen source-current schema 11/parser
installation, authenticated current host and seed/tool/resource/runtime/ABI
receipts, full correctness/diagnostic/fact/leak parity, complete semantic ownership,
and seed→stage1→stage2→stage3 manifests/equivalence. The existing legacy FD30 ratio
launcher must be migrated through an explicit joint ownership decision before
S10 schedules every required workload. Every median and p95 must be ≤1.5× frozen
Zig, with raw samples and declared estimator. Historical partial passing rows,
instruction proxies and matching wire schemas do not waive those requirements.

Memory owners must provide frozen A07 ABI/ownership, A08 cache compatibility,
A09 timing coordination and A10 rollout handoffs before shared adoption. Their
active dirty checkout is not an admissible final candidate. The adapter preserves
conservative failure and complete=false until these external obligations are
independently met; it does not implement a parallel port.

DL7, genuine current frontend-stage adoption, full bootstrap parity and strict
selfhost performance acceptance remain open. No new stage integration patch is
claimed or requested from insufficient evidence. Required complete verification
belongs to the exact final integrated wave2 candidate under root/S10.
