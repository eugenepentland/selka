# S09 bootstrap bridge contract

This inventory fixes development base `fbfcaa7a923186a8e773c3760f81c10aa345a432`
and external port `dff9304b9cd7bc72e66f9feb20f1b05281d67333`. It does not adopt
external compiler sources or confer deployment qualification. `source-audit.json`
contains hashes of immutable git objects and exact coordinator case names.

| Boundary | Protocol/schema | C0 deployment | External snapshot |
| --- | --- | --- | --- |
| test-index | 1/1 | Already adopted; component default | Retained |
| cache-plan | 2/2 | Already adopted; component default | Retained |
| lexer-pilot | 1/2 | Absent | Opt-in reference/shadow/component |
| parser-pilot | 1/2 | Absent | Opt-in reference/shadow/component |
| declaration-index | 1/1 | Absent | Opt-in reference/shadow/component |
| type-interface | 1/1 | Absent | Opt-in reference/shadow/component |
| body-check | 1/11 | Absent | Opt-in partial checked-body profile |

The five frontend modes default to reference. Selected unsupported body forms
must fail rather than silently execute native checking. Whole-language ownership,
Core/LLVM production, and seed→stage1→stage2→stage3 remain unqualified. The port
README still describes body checking as native, and the component guide has a
stale schema8 tail. Actual schema11 comes from the builder, body wire/host contracts
and `a9a2c63b9`; prose is insufficient producer authority. Its strict ratio tool
already defaults to schema11, while its budget guide still describes schema5.

## Seed and producer closure

Both snapshots pin native seed `0689d3407c17df34915aeb2a92e309af3a04921c`, archive
`f7771acebf47c56f8436aaca8e44c5cabccb27d378e0c5535338c8db6e5b4c5c`, and Zig
`0.17.0-dev.1683+5ceec001b`. The seed recipe is native ReleaseFast
`affected-compiler`. Its local qualification binds pin, Zig executable/library
content, target, source identity and executable digest. The current coordinator
checks receipt recipe and compiler bytes before use, verifies the immutable archive
on provisioning, and rejects corruption. A recorded pin alone is not an actual
qualified seed executable.

Producer receipt identity format2 binds component source bytes (including embeds),
protocol/schema, complete seed qualification, coordinator executable digest,
native target/CPU identity, flags and build-cache root. The native builder is
LLVM ReleaseSafe; seed/compiler mode and guest mode are distinct. C0 test-index
and cache-plan guest builds use debug/default guest policy; the external body
producer alone adds guest `--release`. Changing only the host optimization mode
does not select guest release. Reproducible builds isolate guest/compiler/Zig
caches. Parser source file symlinks to lexer libraries need the external
content-snapshot rule; C0 rejects non-ordinary source entries.

Manifest format1 is a deployment selector with component, protocol/schema,
content-named artifact, digest and recipe key. Host launch authenticates selected
artifact bytes. A wire schema match alone cannot qualify a different checker.
S04's `qualified_identity(...)->dict|None` must consume proven producer source,
generated/embedded input, seed, ABI/runtime, recipe/flags/tool closure and snapshot
stability; components retain conservative whole-compiler fallback until adapters
are qualified. Build-cache-root identity means relocation is not assumed equivalent.
The memory lane A07 owns ABI/ownership; A08 owns cache/scaling; A10 owns rollout.
Their changed contracts invalidate this audit's deployment conclusions.

## Ownership and acceptance requests

No port source/manifests/harness ownership has transferred. S06 may independently
edit `test_runner_discover.zig`, `test_runner_batch.zig`, `test_runner_work.zig`
(no delta from C0). `test_runner_directory.zig` carries frontend selection,
authentication and discovery changes; send a narrowed patch through the coordinator.
Port `selfhost/test_components.py` is changed and remains external-owned.
`test_component_native.py` is unchanged, but S07 requests no component edits.
It intentionally retains fresh debug/release/fact/leak tests and release no-cache
builds. C0's 18 coordinator cases become 25 cases in the external snapshot;
those inventories are audits, not fresh passing verdicts.

Before any new frontend adoption, require an explicit file transfer, source
parity/failure/fact/leak matrix, authenticated installed artifacts and seed,
source-edit responsibility, source/seed/ABI/flags mutation rejection, revert and
second-worktree proof, Python-free install/commands, and no native fallback.
Use existing qualified port harnesses. A broad port merge affects ~1,893 files
under src/selfhost/build wiring and cannot be treated as a narrow tooling patch.

## Admission migration request

Owner: external port, applied through coordinator after transfer. Files:
`selfhost/tests/measure_performance_ratio.py`, its qualification tests, and
`docs/tooling/selfhost-performance-budget.md`. Preserve frozen baseline host
identity, all seven manifest authentications, qualified seed, before/after
mutation checks, explicit candidate modes, facts/leaks checks, output/exit
assertions, exact cache receipt counts and every required workload.

Current ratio guard requires CPUs `2,3,10,11` and inherited legacy gate FD30.
Current development timing launcher drains ordinary work and holds fd8
`admit.lock` plus fd9 `timing1.lock`, then exports canonical admission directory
and kind. Do not acquire old gate/build locks inside exclusive timing. Preserve
explicit same CPU placement by running taskset *inside* current timing admission.

`timing_bridge.py` is an experiment fixture for a concrete replacement guard:
verify direct inherited fd8/fd9 against live canonical files and their exclusive
FLOCK ownership in Linux fdinfo; validate explicit expected CPU affinity; include
the returned admission receipt in raw ratio JSON. It rejects marker-only forgery,
lost locks, replaced files, wrong kind and affinity. The Python context-manager
holder uses another process and does not satisfy this direct-launch contract.
The helper does not acquire locks and does not launch timing. A production
migration must also compare canonical directory with the current launcher's
configured slot directory, and record launcher/tool hashes. Do not claim the
fixture as an accepted port integration patch.

Once migrated, S10 runs the ratio harness through
`scripts/build-slot.sh timing taskset -c 2,3,10,11 ... --isolated` after preparing
binaries under build admission, using an available agreed CPU set if these are
not allowed. Both hosts must use the same declared set. Queue time is separate.
The strict gate needs every median *and* nearest-rank p95 ≤1.5× frozen Zig:
36 rows, six workloads × six workflows, default20 repetitions. Five operational
samples are insufficient for stable p95 acceptance. Historical B2/B3/B4 evidence
fails compiler/test rows and passes short guest-runtime rows; no new ratio,
whole-language or full bootstrap success is claimed here.
