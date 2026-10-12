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
store. Optional native compiler-artifact sharing has its own namespace and
environment variable, described below; revision indexes stay private.
`--shared-cache-dir` does not merge these formats or share Zig's local cache.
Each worktree still requires its own `ZIG_LOCAL_CACHE_DIR`.

The native `mylang test --shared-cache-dir DIR` command accepts a shared root,
using the independent `native-tests-v3` namespace for shareable test
successes. It uses the native retention policy below, separately from the
Python developer evidence store. See [guest tests](guest-tests.md#reusing-unaffected-results)
for eligibility. Native tests, shared lookup and collection require no Python.

## Native compiler artifacts

`MYLANG_COMPILER_SHARED_CACHE=DIR` selects
`DIR/compiler-artifacts-v2/{syntax,typed,program}` for supported syntax, typed
bodies and linked executables. Private mutable indexes and materialized
executables remain in each worktree. See [compiler caches](caches.md#shared-compiler-artifacts)
for eligibility and [native builds](native-build.md#shared-compiler-artifacts)
for usage. The same root may hold `native-tests-v3`; budgets are per namespace.

Native compiler artifacts are bounded to 128 MiB per payload and protected by
checksummed records and atomic rename. Staging/hashing precedes a per-key
publication lock, which covers comparison and replacement. A conflicting valid
same-key result raises `DeterminismMismatch` and preserves the existing record.
Retention does not implement the developer evidence store's conflict poisoning
or pins. These are disposable caches for trusted local producers, with no
application-journal or power-loss durability guarantee.

## Native cache retention

The native stores automatically attempt least-recently-used collection when
opened, at most once per hour by default. The policy is stored in each namespace
and therefore applies to every participating worktree:

| Policy | Compiler artifacts | Native test receipts |
| --- | --- | --- |
| Maximum record bytes | 10 GiB | 256 MiB |
| Maximum retained entries | 100,000 | 100,000 |
| Age expiry | Disabled | Disabled |
| Automatic collection interval | 3,600 seconds | 3,600 seconds |

Budgets are soft between collections. No background daemon runs while the cache
is unused. A busy store is skipped and a later open can retry. Verified reads
refresh modification time for eviction ordering; timestamps never establish
content validity. Optional age expiry means time since publication or the last
verified hit. Zero age disables expiry; zero byte or entry limits select all
records for eviction. Format, policy and permanent-lock overhead is outside the
record budget. Abandoned staging files and unused per-key lock files can be
reclaimed while the collector has exclusive access.

Every storage operation owns a shared process lease before it reads or stages
records, including while waiting for a publication lock. Collection acquires an
exclusive nonblocking lease and skips active users. Compilation and test
execution hold no exclusive retention lock. The collector requires no server
build/gate slot. Process termination releases its lease automatically. Permanent
`.lock` and `.retention.lock` files are never removed by collection.

Inspect the installed native command without requiring Python:

```bash
mylang cache --help
```

A first build or test initializes its namespace. Afterwards, preview its current
policy, or preview a one-time budget override:

```bash
mylang cache gc --shared-cache-dir "$HOME/.cache/mylang/compiler-artifacts" --kind compiler
mylang cache gc --shared-cache-dir "$HOME/.cache/mylang/compiler-artifacts" --kind compiler --max-bytes 10737418240
```

Add `--apply` to delete the proposed entries. Overrides on `gc` apply only to
that collection. `configure` explicitly persists policy; omitted settings keep
their current values:

```bash
mylang cache configure --shared-cache-dir "$HOME/.cache/mylang/compiler-artifacts" --kind compiler --max-bytes 21474836480 --max-entries 200000 --interval-seconds 3600
mylang cache gc --shared-cache-dir "$HOME/.cache/mylang/compiler-artifacts" --kind compiler --apply
```

Use `--kind tests` for native test receipts. Add `--max-age-seconds 1209600` for
an optional 14-day last-use limit, or `--max-age-seconds 0` to disable it again.
Reports expose scanned, removed/proposed and retained record bytes and entries,
active-store skips, incomplete inventories and unmet budgets. A bounded inventory
and conservative filename handling preserve foreign files; unknown contents
are not silently deleted to claim a satisfied budget. Automatic cleanup is
best effort; explicit collection reports failures for inspection.

The v2 namespaces isolate this lease protocol from older compiler binaries,
which continue to use `compiler-artifacts-v1` and `native-tests-v1`. There is no
automatic migration or deletion of v1 storage. Remove an old namespace only
when every old user has stopped. Never manually unlink live coordination locks.
The Python collector below does not collect either native namespace. Evicted
records safely miss and refill; already materialized private executables remain
usable. Reuse after an edit/revert requires that the old entry is still retained.

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
scratch directories containing evidence or native retention locks. Use the dedicated
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

Wave 11 adds an optional persistent developer process:

```sh
python3 scripts/cache_session.py
```

Send one JSON object per line on stdin. For example, keep that process open and
submit the same request again after the first completion:

```json
{"id":"gate-1","command":"verify","args":["--zig","/path/to/pinned/zig"]}
{"id":"gate-2","command":"verify","args":["--zig","/path/to/pinned/zig"]}
{"id":"reset-1","command":"reset"}
{"id":"stop-1","command":"stop"}
```

Commands `fuzz` and `perf` take the ordinary arguments of `fuzz_campaign.py` and
`juice_cache.py`. Each stdout line reports the request ID, exit status, whether
restart is required, and actual snapshot work. Tool output, including child
process output, goes to stderr. Requests run sequentially with the repository
root and environment captured at startup; a supervisor can queue agent requests
through this one stream. There is no background daemon, socket or automatic
attachment from independent one-shot commands.

The session retains live watches, inventories and hashes, bounded by
`--max-snapshots` (default 16) and `--max-entries` (default 262144 metadata,
inventory and watch entries). Oversized or busy scopes remain transient. Warm
unchanged scopes skip hashing and enumeration but still revalidate path
identities. Dirty scopes are reconstructed. Active requests never move to a
new revision midway through work. Reset, EOF, cancellation or process exit
releases retained state; restarting validates bytes again. Editing loaded
coordinator or Python runtime code requires restarting the session. Its startup
runtime watch is independent of the evictable snapshot pool. It assumes a
trusted Python installation at launch, rejects preloaded coordinator helpers,
and guards later changes; it does not reconstruct how Python itself bootstrapped.

Native compiles, links and eligible shared tests also coordinate simultaneous
requests by exact keys. Claims are process locks, not saved success evidence:
followers recheck artifacts or receipts after acquiring them, and failure or
process death releases ownership. Sorted batches avoid lock-order cycles.
Different keys remain independent, and test/source checks still apply after a
wait. Existing private test receipt hits keep their ordinary reuse semantics.

Collection skips active owners and waiters. Shared v2 namespaces reclaim idle
work locks only under exclusive retention ownership. The legacy pruner also
reclaims recognized idle work locks under nonblocking exclusive leases and
preserves permanent lease locks, while native builds retain shared leases
through linking and output publication. No server admission is needed for
retained validation, cache lookup, publication or collection.

Reports expose hashing work separately from reused actions. Juice also uses an
optimized native streaming SHA-256 implementation when the compiler is built in
Debug mode. It still reads every byte, including the running compiler executable;
the optimization changes computation cost, not cache identity.

Zero test or workload executions does not mean zero validation work. Discovery,
provider resolution, hashing, locks and materialization remain part of the warm
command. Retained developer sessions do not retain compiler ASTs across ordinary
native command invocations, and do not change fuzz freshness or measurement
validity policies. A fresh performance measurement still requires execution.
