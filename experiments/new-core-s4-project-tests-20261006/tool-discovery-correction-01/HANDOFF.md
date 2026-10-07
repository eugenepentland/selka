# Additive full-tool discovery correction

This package repairs the retained production-helper closure RED from F evidence
commit `8d7952f86`. It preserves all prior executable, complete adjacent/override
library, native CPU/target, six runtime files and preload inputs. It adds 296
source-derived discovery selection paths; the actual approved tool-copy inventory
therefore contains 21,203 inputs. It does not establish smaller action identities
or qualify a warm-build performance gate.

The official Clang 22.1.8 source-to-pinned-binary build relation remains
unestablished. Reuse requires the exact previously approved executable and
normalized full library closure plus the newly reviewed fixed discovery state.
Unknown distro contents, version membership, aliases or sibling layouts refuse
persistent reuse. In particular the approved state requires the complete sibling
`lib` root, `/opt/rh` and `/etc/env.d/gcc` to be absent. A present sibling root is
refused before adding any resource child.

## Owned source and interpretation

Only `src/core/tool_discovery.zig`, `src/core/tool_identity.zig`,
`src/config_core_tool_platform.zig` and the single root-test import changed.
Existing compiler behavior, IR, public helper APIs and native flags remain as
captured in the source snapshots. No M Git mutation is part of this handoff.

| Item | New interpretation/version |
| --- | --- |
| Input codec | v2: one validated role byte; illegal enum bytes refuse hints |
| Inventory magic | `core-tool-inventory-v4\0` |
| Approval magic/namespace | `core-tool-approval-v3\0`, `approval-v3` |
| Semantic content identity | `core-tool-content-v3` |
| Semantic generation identity | `core-tool-generations-v3` |
| Discovery descriptor/state domains | `core-native-discovery-v1`, `core-native-discovery-state-v1` |
| Native CPU/target domain | existing `core-native-cpu-v2` |
| Opaque content-memo codec | existing `core-tool-content-v1\0`; fixed 32-byte opaque digests retain their encoding |
| Reviewed discovery state | `614ce9f2e514299aea9aea24086e224bb2c8ed8467fcf4a98e453d2d86057ab1` |

Both inventory-hint and approval keys bind all discovery descriptors, role names
and reviewed state. A checksummed old v3 hint is a miss. Existing inputs retain
their full content/stat policy. Predicate roles omit directory membership times
only for proved directory existence/alias queries; inode/type/permissions and
canonical resolution remain bound. Version membership directories retain full
generations and sorted reviewed names. Consumed discovery files keep full
content/stat guards and re-resolve their canonical alias every validation.
`std.Io.File.Stat` exposes no device field in the pinned toolchain.

## Retained sequence and exact scopes

`source-native-18.json` identifies the first frozen correction. Focus16 passed
25/25 and Guardian17 passed all 88 checks. Probe18 and Debug Core19 built from
those bytes. Helper-only replay21 uses the actual approved Zig/full-library copy:

- An initially absent sibling root is eligible, then its creation invalidates
  the generation/content identity and old provisional replay. The new state is
  ineligible.
- A preexisting sibling root is ineligible before a child resource exists.
  Its child addition may leave the conservative parent predicate unchanged;
  persistent replay is already disabled. This is not a claim to inventory an
  unreviewed resource tree.

Those receipts do not qualify the subsequent compatibility repair. Pure owned
RED20 proves Linux `dirStatFile` returns `NotDir` for children under a regular
file. The frozen helper previously returned `ReadFailed`, preventing fallback.
The pinned standard-library lines are retained as `std-dir-stat-linux-20.txt`.

`source-notdir-23.json` identifies the minimal repair. Only new discovery roles
interpret unreachable children as absent; legacy content snapshots keep the old
error behavior. The regular-file parent remains present with full content/stat
guards. Symlink-loop and access failures remain conservative. Focus24 passed
27/27; probe25 and Debug Core26 built successfully. Final Guardian29 passed all
88 checks. Source-final29 equals source-notdir23, including the unchanged IR.
Replay21 remains historical.

`native_replay.py` records actual canonical E Debug-unit native compiles with
fresh local/global caches before and after each mutation. It also exercises the
actual new Core executable and native guest for unreviewed directory/file
layouts. Exact input/object/executable hashes, argv, output/status and traces
are preserved. Replay27 retained an invalid evidence fixture (`export def`)
rejected before the guest-tool invocation. Only that fixture changed; replay28
then passed all three scenarios on fresh work/cache/output paths after E's
uncontended full-Core window. Two actual fallback builds succeeded and both
native guests exited 7; their invocation-owned private native/tool directories
were cleaned. The regular-file parent was edited with equal size and restored
mtime and invalidated the captured generation/content. Actual traces record
opening and reading the newly added resource. All six objects are SHA-256
`d8dd5741be1e8c641748d89dec8810ff602a9203e1b8afeaf4006e4cfe7a0b37`.
Equal object bytes establish neither changed-output behavior nor an
action-specific closure certificate. No final package old/fuzz gates are run
here.

The Debug Core artifact is SHA-256
`70d461e9ee318af7115f37d82ec22732a71f9a159aba698a69ee4ec418f1a539`;
the ReleaseFast helper probe is
`c32907052c667c7dc93d347bcc8792c26fa39e109d7a9ffe6bf561cad5114a2d`.
Successful fresh receipts and exact source/hash equality are retained after all
commands. Full Wave A integration/package gates remain root-owned and held
pending qualified E/V source.
