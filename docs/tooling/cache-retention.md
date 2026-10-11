# Shared local evidence and retention

The developer verification, fuzz and Juice coordinators accept
`--shared-cache-dir DIR`. Point participating worktrees at one dedicated local
directory outside their checkouts, for example
`$HOME/.cache/mylang/toolchain-evidence-v1`. The option shares immutable blobs
and exact action receipts. Each command keeps its ordinary private worktree cache
for mutable planning data and working files.

```bash
python3 scripts/verify_cache.py --zig /path/to/pinned/zig \
  --shared-cache-dir "$HOME/.cache/mylang/toolchain-evidence-v1"
python3 scripts/fuzz_campaign.py differential --zig /path/to/pinned/zig \
  --shared-cache-dir "$HOME/.cache/mylang/toolchain-evidence-v1"
python3 scripts/juice_cache.py capture suite.json --compiler /path/to/mylang \
  --shared-cache-dir "$HOME/.cache/mylang/toolchain-evidence-v1"
```

These are developer commands. Building, installing and using the native compiler
continues to require no Python.

## What can be shared

Storage location is independent of action identity. Identical bytes deduplicate
even when their producers have different action keys. A receipt authorizes reuse
only for its exact existing dependency and execution contract. Workspace paths,
debug paths, environment, host context and physical executable layout still
invalidate actions that observe them. This does not normalize paths inside
results or promise that two different checkout paths have interchangeable tests.
An unchanged retained revision can recover its original receipts after an edit
and revert.

Verification inventory and preparation records stay private. Fuzz corpus
catalogs and their retained raw inputs stay private too: they can survive shared
success eviction and be replayed against a changed target. Juice materializes
verified raw records and executable copies into the requesting worktree.

Native unit/runtime objects already use their own shared content-addressed
store. Native frontend packs, linked-program caches and revision indexes remain
private. `--shared-cache-dir` does not merge these formats or share Zig's local
cache. Each worktree still requires its own `ZIG_LOCAL_CACHE_DIR`.

The native `mylang test --shared-cache-dir DIR` command also accepts a shared
root, using the independent `native-tests-v1` namespace for portable ordinary
test successes. It does not use this developer store's blob/receipt or retention
format. The Python collector below does not collect native test receipts. Remove
that disposable namespace only while its users are stopped; never unlink its
permanent `.lock` while a command may use it. See
[guest tests](guest-tests.md#reusing-unaffected-results) for the supported subset
and environment setup. Native tests, including shared lookup, require no Python.

## Publication and compatibility

The store declares its format explicitly. An unknown, damaged or unversioned
nonempty configured store is an error with an actionable diagnostic. Select a
new empty root for a new layout; do not copy old flat receipts into it. The
coordinators use new private evidence subdirectories for the versioned layout.
Old disposable caches can be removed when no old worker is using them.

Every blob is length-bounded and checked against its content digest. Receipts
have checksummed envelopes and exact schema checks. Missing, truncated or damaged
payloads cause work again. Atomic publication exposes either a complete record
or a miss, including after an interrupted writer. A digest proves payload bytes;
local producer trust and the caller's dependency checks establish their meaning.
This store is for trusted local processes, not unauthenticated remote producers.

Two completed deterministic results for one action must agree. A mismatch raises
a determinism error and poisons that action until explicitly investigated and
cleared. Ordinary force/discard does not clear this evidence. Physical Juice
measurements retain their separate first-valid-observation policy: a later
sample need not have identical counts or timestamps.

A forced deterministic refresh makes the old success unavailable for lookup
while retaining its comparison reference. A failed refresh stays a miss; a
different completed result is a conflict. Shared fuzz publication restores
referenced raw bytes from the private corpus copy before saving a new receipt.

## Leases and collection

Store operations take a local shared process lease. Coordinators keep it through
lookup, execution, publication and materialization. This lock is independent of
server admission and allows concurrent readers and writers. Collection requests
an exclusive nonblocking lease; an active store is reported as skipped. Process
death releases its lease. The global retention lock is permanent. Collection can
remove unused per-key locks only while it holds the exclusive lease: every holder
and waiter owns a shared lease before opening a per-key lock. No active process
can silently acquire a different lock inode for the same key.

Collection is explicit. Byte and age policies evict unpinned receipts and then
unreferenced blobs; age means time since publication, not last access. Pins retain
explicit receipt/corpus references and a frozen list of their payloads. Protected
data can exceed a requested budget, which is reported rather than deleted. An
unreadable protected record stops collection. The inventory itself has an entry
bound; byte counts exclude filesystem overhead and the fixed format/global lease
files. Periodic collection is needed to enforce the selected disk policy.

```bash
# Inspect the proposed collection; omit --max-age-seconds for a byte-only policy.
python3 scripts/cache_retention.py --cache-dir /path/to/shared-store gc \
  --max-bytes 10737418240 --max-age-seconds 1209600
# Apply that policy only while the store is idle.
python3 scripts/cache_retention.py --cache-dir /path/to/shared-store gc \
  --max-bytes 10737418240 --max-age-seconds 1209600 --apply
```

The JSON report includes scanned and retained entries, bytes, active-lease skips
and an unmet-budget flag. `pin PIN_ID --success ACTION_KEY` retains a success and
its referenced payloads; `--corpus FAMILY_KEY` and `--blob DIGEST` can be repeated
as well. IDs and keys are lowercase SHA-256 strings. `unpin PIN_ID` releases that
root. `clear-conflict ACTION_KEY` explicitly discards the poisoned receipt after
investigation; it does not certify which old output was correct.

The legacy `prune-caches.sh` no longer deletes an entire `.mylang-cache` and skips
scratch directories containing evidence retention locks. Use the dedicated
collector for these stores. Do not manually remove a store that workers are using.

Pins are cache-retention roots. They do not establish durable application
checkpoints, power-loss persistence, effect replay or restart guarantees. Those
require the separate application-journal qualification planned for Wave 7.

## Warm validation

Within one invocation, overlapping snapshots can share content digests only
while the original watches remain active and clean. Receiving snapshots install
their own watches first. Watch closure, event loss, process change, mutations or
metadata differences prevent reuse; restarting a command reads input contents
again. This bounded session never persists a metadata-only digest claim.

Reports expose hashing work separately from reused actions. Juice also uses an
optimized native streaming SHA-256 implementation when the compiler is built in
Debug mode. It still reads every byte, including the running compiler executable;
the optimization changes computation cost, not cache identity.

Zero test or workload executions does not mean zero validation work. Discovery,
provider resolution, hashing, locks and materialization remain part of the warm
command. A persistent workspace service remains a possible later optimization;
it is not required for correctness or for this storage interface.
