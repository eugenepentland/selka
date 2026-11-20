# Shared local evidence and retention

The developer verification, fuzz and Juice coordinators accept
`--shared-cache-dir DIR`. Point participating worktrees at one dedicated local
directory outside their checkouts, for example
`$HOME/.cache/selka/toolchain-evidence-v1`. The option shares immutable blobs
and exact action receipts. Each command keeps its ordinary private worktree cache
for mutable planning data and working files.

```bash
python3 scripts/verify_cache.py --zig /path/to/pinned/zig \
  --shared-cache-dir "$HOME/.cache/selka/toolchain-evidence-v1"
python3 scripts/fuzz_campaign.py differential --zig /path/to/pinned/zig \
  --shared-cache-dir "$HOME/.cache/selka/toolchain-evidence-v1"
python3 scripts/juice_cache.py capture suite.json --compiler /path/to/selka \
  --shared-cache-dir "$HOME/.cache/selka/toolchain-evidence-v1"
```

These are developer commands. Building, installing and using the native compiler
continues to require no Python.

### The verification coordinator's default store

`verify_cache.py` resolves its shared store in this order: `--shared-cache-dir DIR`,
then `SELKA_VERIFICATION_SHARED_CACHE=DIR` (a placement variable: its value never
enters a key), then the per-user default `$XDG_CACHE_HOME/selka/verification-shared`,
else `~/.cache/selka/verification-shared`. The default applies only while the
module constant `DEFAULT_SHARING` in `scripts/verify_cache.py` is true, as enabled
after three R4 complete-verification passes at the default store locations.
The trust boundary is the same Unix user on the same machine. An explicitly
empty flag or variable disables sharing. An unusable default store prints one
warning and verification proceeds without sharing; an unusable store named by
the flag or the variable is an error. `last-run.json` reports the choice as
`evidence_store.source` (`flag`, `environment`, `default` or `none`).

## What can be shared

Storage location is independent of action identity. Identical bytes deduplicate
even when their producers have different action keys. A receipt authorizes reuse
only for its exact existing dependency and execution contract. Verification action
keys hold no checkout path and only the keyed and host environment classes, and
identify native executables by their producer recipes where `artifacts.json`
declares them ([receipt identities](development-loop.md#receipt-identities-schema-3));
host context and any provider still identified by its bytes still invalidate
actions that observe them. This does not normalize paths inside
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

The native `selka test --shared-cache-dir DIR` command accepts a shared root,
using the independent `native-tests-v3` namespace for shareable test
successes. It uses the native retention policy below, separately from the
Python developer evidence store. See [guest tests](guest-tests.md#reusing-unaffected-results)
for eligibility. Native tests, shared lookup and collection require no Python.

## Native compiler artifacts

`SELKA_COMPILER_SHARED_CACHE=DIR` selects
`DIR/compiler-artifacts-v2/{syntax,typed,program,engine_record,engine_object,frontend}` for supported syntax, typed
bodies, linked executables, the incremental engine's records and the objects their payloads point to
([the shared tier](engine.md#the-shared-tier)), and the front end's own: a project's check-summary table (the stand-in
facts of its last successful check, replaced by each worktree's check, so a worktree started from the same project is
served it) and a module's header facts. The table's key names the compiler identity, the entry and the set of the
project's module paths, never a root; every stand-in it offers is still validated against the fresh function. Private mutable indexes and materialized
executables remain in each worktree. See [compiler caches](caches.md#shared-compiler-artifacts)
for eligibility and [native builds](native-build.md#shared-compiler-artifacts)
for usage. The same root may hold `native-tests-v3`; budgets are per namespace.

A linked program's record (`program/<key>.blob`) is the executable itself, with its size
and digest in `program/<key>.blob.sum`, published after it. Retention counts the pair as
one record: it evicts the sidecar with its executable, and an orphan sidecar is reclaimed
as staging. A restore hands out a hardlink to the executable after checking its bytes
against the sidecar, or a verified copy when the link fails; a record that fails the check
is a miss.

Native compiler artifacts are bounded to 128 MiB per payload and protected by
checksummed records and atomic rename. A per-key publication lock covers
comparison, staging and replacement. An existing verified record is compared by
hashing the new bytes in place, so republishing identical bytes writes no
staging copy and renames nothing. A conflicting valid same-key result is a miss:
the existing record is preserved, nothing is published, and one line
`mismatch <kind> <key> existing=<digest> attempted=<digest>` is appended to the
namespace's `mismatches.log`. Builds count program mismatches as
`shared_mismatches` in their cache report. The native test store follows the same
rule with kind `engine` (its records are the engine's; the earlier `receipt` kind is no longer written). The integration gate (`verify_cache.py --integration`)
fails with status 5 while any log of a store it used is non-empty
([integration gate](development-loop.md#integration-gate)). The ordinary verification request does the same with stores of its own
(`.selka-cache/verification-v3/gate-stores`, removed when it ends): its workers never open the per-user stores, a mismatch
in its own is status 5 and a build of the request that holds a lease on a per-user store is status 6
([the gate's own stores](development-loop.md#the-gates-own-compiler-and-test-stores)).
Retention does not implement the developer evidence store's conflict poisoning
or pins. These are disposable caches for trusted local producers, with no
application-journal or power-loss durability guarantee.

## The shared stage store

`stage-artifacts-v1` (packs of records; [native builds](native-build.md#the-shared-stage-store)) is on by default, under
`$XDG_CACHE_HOME/selka/stage-artifacts` or `~/.cache/selka/stage-artifacts`, and is bounded by its own collector (`stage_collector.zig`)
rather than by the file-per-record policy above. Every process that opens it holds a shared lease file, and a build writes the
8-byte key prefixes it used as its worktree's live root. A collection runs in the build that finds ten minutes passed since the last
(`collector.lock` is taken without waiting; a busy collector is skipped), keeps the records a live root names (roots older than 14 days,
or whose work directory is gone, are dropped) and every pack written or read since the oldest live lease began or younger than 14 days,
compacts the other packs into fresh ones, and, over the cap, evicts packs older than the oldest lease that hold no live record, oldest first.
A reader that holds a pack open keeps reading it; a record that was evicted is a miss and is computed again. The sequence lock a save
takes is held only to append the build's own records; the compaction's reads and writes happen outside it, and a build refreshes its catalog
before taking it.

The cap is 4 GiB (about fourteen 400k-function states or sixty 99k ones), persisted in the namespace's `policy` file:

```bash
selka cache configure --shared-cache-dir "$HOME/.cache/selka/stage-artifacts" --kind stages --max-bytes 8589934592
selka cache gc --shared-cache-dir "$HOME/.cache/selka/stage-artifacts" --kind stages          # preview
selka cache gc --shared-cache-dir "$HOME/.cache/selka/stage-artifacts" --kind stages --apply  # collect now
```

`--kind stages` takes `--max-bytes` and `--apply` only, and both commands need the namespace a first build creates. The report names the
bytes before and after, the packs evicted, the live leases and whether the budget is unmet (the live and recent packs alone exceed the cap).

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
reclaimed while the collector has exclusive access. A test receipt's work sidecar
(`KEY.pass.work`, the trial's steps and peak bytes) belongs to its receipt: it is
not a record, so it counts against no budget and goes with its receipt when that
is evicted, and a sidecar whose receipt is gone, like an interrupted write of one
(`KEY.pass.work.partial`), is reclaimed as abandoned staging. Only an exact name of
that form is touched; another suffix, a key that is not lower-case hex and a
symbolic link remain foreign.

Every write owns a shared process lease before it stages records, including
while waiting for a publication lock, and every work claim holds one through its
work. Writers and claims take the lease without waiting: while a collection
holds the namespace, a publication is skipped and a claim is not taken, so the
build or test runs unclaimed and publishes nothing. Opening a namespace whose
format marker exists takes no lock; the exclusive `.lock` is taken only while the
marker is first created. Several processes may open and publish into one fresh
store at once: each tolerates directories and a marker a peer created, and an
open that fails retries namespace creation up to four times, re-reading what a
peer published, before it reports the store unusable (SHARED-STORE-6). Lookups and restores hold no lease: records are
immutable files replaced only by rename, so a record a collection evicts is
either read whole through its open handle or missed. No open, lookup or restore
waits on a collection. Collection acquires an exclusive nonblocking lease and
skips active users. Compilation and test execution hold no exclusive retention
lock. The collector requires no server build/gate slot. Process termination
releases its lease automatically. Permanent `.lock` and `.retention.lock` files
and `mismatches.log` are never removed by collection.

The automatic collection runs in the opening process, at most once per interval (30
minutes unless the namespace's policy says otherwise). It first tries for the exclusive lease. Builders
hold a shared lease for as long as they build (a program's work claim lasts the whole
build), so with a few of them at work there is no moment without one, and a sweep that
waited for the exclusive lease never ran: on 1 November 2026 the compiler store held
578,849 entries against its policy of 100,000 (F31). When the exclusive lease is not
free, the sweep runs beside the builders instead, alone (the `.sweep.lock` mutex) and
under a shared lease, and removes only what needs no exclusive lease: the immutable,
checked-on-read blobs of `syntax`, `typed`, `engine_record`, `engine_object` and `frontend`
(and, in the test namespace, `engine`), each under its own key lock, and only if it was
not touched since the inventory, plus lock files nobody holds and staging files idle for
ten minutes. Linked programs and their sidecars, test receipts and their work sidecars
wait for an exclusive sweep, and the report says `leased` and keeps the budget unmet if
they alone hold it over its quota. Lock and staging files are always removed and do not
count against the batch. It builds its inventory
(a path for every record it inspects, up to one million directory entries) in an
arena of its own that it frees before it returns, whatever allocator the opener
bound, so a process that opens a store many times, as a directory test run does
once per docstring example, keeps nothing of its sweeps. An automatic sweep also
removes at most 250,000 records, so one that finds a store far past its policy takes
a few seconds, not minutes; a forced
`selka cache gc --apply` is not held to that batch. `scripts/prune-caches.sh`
also runs `selka cache gc` for the shared namespaces it finds (the configured
`SELKA_COMPILER_SHARED_CACHE` and `SELKA_TEST_SHARED_CACHE` roots, else the
default roots below), so busy stores are still collected.

A namespace with more than one million directory entries is trimmed a window at a
time. The sweep inspects the first million entries in directory order, counts the
rest without inspecting them, and applies the policy to the records it inspected,
evicting the oldest until that window fits. This cannot evict a record that the
policy would keep for the whole namespace: the policy keeps the newest records
within budget, and records that fit among all of a namespace's fit among any part
of them. Each sweep therefore shrinks an oversized namespace by the records of its
window beyond the policy (an automatic sweep, by at most one batch of them), the
window moves as entries leave, and the sweeps end with a complete inventory and
the records that one sweep of the whole namespace would have kept. A million
entries is also the memory bound: a sweep holds a path for each inspected record
and no more, however large the namespace.

The rules of a whole-namespace sweep hold inside a window. A namespace with a
process lease is skipped. Entries that are not recognized records, and symbolic
links, are counted and never deleted. A preview deletes nothing and proposes
exactly what the sweep would remove. A policy whose limits exceed the window (more
than a million entries) cannot be enforced on a larger namespace, because no
window is ever over it; the report then says `unmet_budget`.

`selka cache gc` reports `visited` (directory entries inspected), `unvisited`
(entries past the bound, counted but not inspected), `scanned` (records inspected),
`removed` (records evicted, or proposed by a preview) and `retained`. When
`inventory_complete` is false, `scanned`, `removed` and `retained` describe the
window only and the namespace holds up to `unvisited` more entries; run
`gc --apply` again until it reports a complete inventory.

The default roots are `$XDG_CACHE_HOME/selka/compiler-artifacts` and
`$XDG_CACHE_HOME/selka/native-tests` when `XDG_CACHE_HOME` is absolute, else
the same names under `~/.cache/selka`. They are used for an unset variable only
when the `default_sharing` switch in `src/shared_cache_policy.zig` is on, as enabled
in R4. Sharing is for the same user on the same machine.

Inspect the installed native command without requiring Python:

```bash
selka cache --help
```

A first build or test initializes its namespace. A compiler-artifact namespace that lost
its `format` marker, and holds this cache's own directories (`syntax`, `typed`, `program`,
`engine_record`, `engine_object`, `frontend` and `work`) and nothing else, is adopted by the next build or test, which writes the
marker back: the directory name pins the format, and every record is checked against its
own key and digest when it is read. A namespace with a different marker, or with files
that are not this cache's, is never adopted; a default one prints one `warning:` line
that names the repair and the command goes on without sharing, and `gc` and `configure`
refuse it with the same advice. A test-receipt namespace that lost its marker is not
adopted by a build or test either (a lost marker must not adopt old receipts). `gc` and
`configure` never write a marker; `init` does, under the creation lock, for either kind,
and it changes nothing else, replaces no marker that is present and refuses a directory
that holds files that are not this cache's:

```bash
selka cache init --shared-cache-dir "$HOME/.cache/selka/compiler-artifacts" --kind compiler
```

Afterwards, preview its current policy, or preview a one-time budget override:

```bash
selka cache gc --shared-cache-dir "$HOME/.cache/selka/compiler-artifacts" --kind compiler
selka cache gc --shared-cache-dir "$HOME/.cache/selka/compiler-artifacts" --kind compiler --max-bytes 10737418240
```

Add `--apply` to delete the proposed entries. Overrides on `gc` apply only to
that collection. `configure` explicitly persists policy; omitted settings keep
their current values:

```bash
selka cache configure --shared-cache-dir "$HOME/.cache/selka/compiler-artifacts" --kind compiler --max-bytes 21474836480 --max-entries 200000 --interval-seconds 3600
selka cache gc --shared-cache-dir "$HOME/.cache/selka/compiler-artifacts" --kind compiler --apply
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

## Work directory retention

A work directory (`--cache-dir`, default `.selka-cache/core`) keeps its regenerable
tiers under the compiler's own bound: `programs-v2/`, `programs-v1/`, `foreign-v1/`,
`replay-v1/`, `stages-packed-v1/`, `lowering-assembly-v1/`, `semantic/`, `frontend/` and `engine-v1/`. The bound is `SELKA_CACHE_TIERS_CAP_GB` GiB across all of them (default 10;
`0` off), the variable build-slot admission reads for its developer caches.

**Ownership proofs.** The ownership proofs are `ownership-proof` records of the engine's store (`engine-v1/`, see
[the engine](engine.md)), kept by the engine's retention like every other kind: the kind's current code identity and the two most
recently used others. The pack store older compilers kept them in, `ownership/<compiler identity>/stages-packed-v1/`, is removed
by the first build, check or `selka test` run that finds it and gets the work directory's exclusive lease
(`work_retention.zig`, `removeLegacyOwnership`); a directory a running command holds is left until the next run.

- **When.** Each build and each check holds the directory's shared lease
  (`.retention.lock`) while its stores are open. When the command finishes it runs the
  collector at most once every ten minutes, and only if it gets the lease exclusively:
  a directory another build or check holds is skipped, not waited for. The next command
  retries.
- **What.** Whole files, oldest first, abandoned partials first, until the tiers total at
  most the bound. Lock files, the `sequence` counter, claim directories (`work/`), dot
  files and symbolic links are left alone.
- **Stage packs.** An open store can list a pack, so no sweep runs while one is open:
  every command that opens a store holds the lease for as long as the store is open. A
  pack removed after its store closed is a miss for the next open store, never an error.
- **Programs.** Each optimization level keeps the four linked programs used last (sidecars
  included; a replay that serves a program counts as a use), enforced when a program is published. A removed program is linked again, and
  a replay record that names it is not replayed.
- **Misses, not errors.** A removed entry costs a miss: a stage record is recomputed, a
  `--link` object recompiled, a replay record skipped. A build after a collection writes
  the same output as `--no-cache`.

The collector is `src/core/work_retention.zig`; `scripts/worktree_cache_trim.py` lists the
same tiers for developer admission.

The bound is per work directory, and the test suites make many: one per core test and one
per unit-test program under `.selka-cache/unit-tests/core/build/`. Build-slot admission
bounds them together with `SELKA_TEST_CACHES_CAP_GB` (default 8 GiB, `0` off), removing
whole work directories least recently used first under their exclusive lease
(`docs/tooling/many-agents.md`).
One complete gate's test caches measured 4.6 GiB on 29 October 2026 (the language suite
is a single 1.4 GB work directory), so the default sits above that: a bound below one gate's
working set would make each gate remove what the next one reuses.

## Ownership verdicts

The `ownership-proof` gate action keeps the verdicts of the Zig validator and the Lean checker in the namespace
`ownership-verdicts-v1` of the verification coordinator's shared root (the root of "The verification coordinator's default
store" above), so every worktree of the user shares them. The coordinator's own store ignores the directory as a foreign
entry; the action makes the root a versioned store first, as the coordinator does, so the order of the two does not matter.

- **Records.** `kind/CHECKER24/AA/CERTIFICATE-DIGEST`: the verdict line and a checksum of its key and text, published by
  atomic rename. A damaged record is a miss. `kind` is `zig`, `lean` or `mutants`; `CHECKER24` is the first 24 digits of the
  digest of the checker (the validator's sources, or `proofs/ownership` with the Lean toolchain). A checker also has a marker
  `ESTABLISHED` once a run has completed with it; until then the size cap on the Lean side is off.
- **Leases.** Every reader and writer holds a shared flock on `.retention.lock`; the collector takes it exclusively without
  waiting and skips a store in use. Process death releases it.
- **Retention.** Opening the store collects at most once an hour: the least recently used records beyond 150,000 are
  removed (each record is a few dozen bytes but a filesystem block, so the bound is about 600 MB; a hit refreshes a record older
  than an hour). Markers, `format.json`, `mismatches.log` and the locks stay.
- **Conflicts.** A verdict that differs from a stored one for the same key is not published; one line
  `mismatch KIND CHECKER24 DIGEST existing=... attempted=...` goes to `mismatches.log`.

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

The legacy `prune-caches.sh` no longer deletes an entire `.selka-cache` and skips
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

### Store claims, timers and keep markers

- The per-user core store's collector (`scripts/core_store_gc.py`) reclaims idle
  `work/*.lock` claims itself, in bounded batches
  (`--claim-batch-size`, default 500,000), by probing each claim's flock: a claim a
  build holds is busy and stays, an unheld one is unlinked. `storage.lock` checks after
  it locks that its name still names the held file and otherwise opens it again, so a
  builder that was waiting on a removed claim never holds an orphan inode and two
  builders never hold one key. No exclusive lease is needed. The legacy
  per-file shell loop is gone; a 500,000-claim fixture clears in under a minute
  in the test suite.
- **A test never collects the user's own store.** `SELKA_STORE_GC_DENY` (paths joined by `:`) lists stores
  `core_store_gc.py` refuses to touch, with exit 2 and no ledger, and `prune-caches.sh` passes it on. The retention
  driver (`scripts/cache_retention_test.py`) builds every pruner environment through `hermetic()`, which points
  `SELKA_CORE_RUNTIME_CACHE` and `XDG_CACHE_HOME` at directories of its own, denies the real per-user store, and fails
  a test whose environment would still reach it. Until 2 November 2026 one of its tests ran
  `core_store_gc.py --apply` on the real 2-million-entry store in every gate, 20 to 25 minutes each time. A test in the same file
  fails when another Python gate driver names `prune-caches.sh` or `core_store_gc.py` without being reviewed.
- The same collector bounds the toolchain identity memos in `core-tools-v1/` beside the store
  (`tool-identity/`, `approval-v4/`, `approval-v3/`, `approval-v2/`; `--tools-store` names another place): no
  memo idle for `--max-age-days` (the later of its modification and access times; a staged
  `.pending` file expires after a day) and at most `--tools-max-bytes` (default 64 MiB), the least
  recently used going first down to 90% of the bound. The memos are caches (a missing one is derived
  again, a damaged one is a miss, a publication is a rename), so the pass takes no lease; it touches
  only files with the memo names, never a symlink, and keeps a file that changed since its inventory.
  Before this pass nothing collected them: they had grown to 14,000 files and 254 MB in three weeks.
- The edit check's coverage maps in `~/.cache/selka/edit-check/` (`scripts/edit_check_refresh.py`)
  are pruned after each published map: the newest five by commit time stay (`MAPS_KEPT`), the
  map just published always, and any map a running edit check holds (it keeps a shared lock on
  the file). `python3 scripts/edit_check_refresh.py --prune` prunes at once. An old branch whose
  commit has no kept map as an ancestor runs `scripts/affected_tests.py` instead, as for any
  branch without a usable map.
- `scripts/systemd/selka-core-store.timer` keeps `OnBootSec` and
  `OnUnitInactiveSec` and also carries `OnCalendar=*:0/15`. On 16 October 2026 a
  user-manager restart left only the relative triggers, which had no next run,
  and the store sat 2 GiB over its cap for four days. A test parses every timer
  in `scripts/systemd/` and refuses one whose triggers all depend on a prior run.
- A `prune-keep` marker (in the worktree's git dir or as `.prune-keep`) is never
  deleted and should carry `owner=`, `reason=` and `until=YYYY-MM-DD`.
  `scripts/prune-caches.sh --list-kept` lists each kept worktree with its marker,
  last activity and cache size, and reports missing fields, a malformed date or
  an expired date. Nothing is deleted by that report.

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
