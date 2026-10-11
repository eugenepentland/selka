# Wave 7b/7c independent application qualification

Proposed qualification from `2d00dc3da`; this file records requirements, not
completed results. Product APIs and fixture ownership are being coordinated.
The installed compiler and applications must remain Python-free. Python is only
the developer supervisor, independent CSV oracle and fault injector.

Use one copied native Selka fixture at a stable source path. Its pure callback
maps captured CSV rows in chunks of two. Retain each completed chunk's canonical
rows, a serializable running-total state and an identity-bound journal prefix.
Publish `id,input,mapped,running_total` CSV only from verified completed chunks.
Twelve input rows provide six chunks, enough to inspect partial progress.
Compute expected CSV independently in Python and also execute a forced,
uninterrupted native run against a separate empty store. Compare exact bytes.

## Required observable application outcomes

- Selected implementation/dependency identity, argument/input digest, result
  schema identity and relevant compiler/runtime/target context.
- Completed, failed or uncertain publication status; no success on storage
  failure, malformed state or incomplete execution.
- Fresh/reused chunk ordinals, committed prefix and final artifact digest.
  Distinguish journal reuse from a newly computed chunk hitting a persistent
  value cache. Report actual selected chunk IDs, not just aggregate counts.
- Artifact, journal and final-output paths for targeted corruption; declared
  bounds and retained-state GC counts. Ordinary failure categories are values;
  traps and unfinished work are not completed success.

## Persistent identity matrix

Cold then a separate-process warm run must agree with forced execution and
reuse all eligible results. At the same source and input paths, independently
change the selected callback body, its private helper, a shared reachable helper,
the selected callback, result schema and captured input bytes. Preserve line
counts for body edits. Each change must reject incompatible prior results and
produce the corresponding fresh oracle output. Revert each change and verify
parity, allowing prior baseline results only when their complete identity still
matches. An unrelated helper edit is an incremental-reuse probe, not an assumed
guarantee before the conservative indirect-call identity contract is known.

Input mutations include same-size bytes with restored mtime, deleted input and
an input edit after capture. The latter must follow the declared captured-input
contract: finish from immutable captured bytes or explicitly abort; the next run
must observe the new bytes. Exercise empty/text/byte arguments, embedded NUL,
structural canonical encodings and schema mismatch. Resource/Host/unknown
callables must fail admission or bypass persistence rather than mint a reusable
identity. Truncated/corrupt/missing cache metadata and payloads must never hit.

## Durable recovery matrix

Inject an owned-process SIGKILL before and after artifact publication, journal
commit and final publication. A developer-only C syscall interposer can notify
the supervisor and stop around real write/fsync/rename calls. Do not substitute
Python-created journals or timing sleeps for native library publication. Exact
operation/path classification will follow the storage API. Retain the original
and recovered stores, fault marker and logs as raw evidence.

For every crash, recovery must match the forced uninterrupted CSV. Already
committed chunks with intact validated artifacts must not be computed again;
uncommitted artifacts may be discarded or safely reused only through their
independent complete cache proof. Kill after the first committed journal as an
additional partial-progress test. Recover twice, and exercise competing recovery
under a held directory lock and release after SIGKILL.

Inject directory-sync failure after a successful final rename to exercise an
uncertain publication. A fresh recovery must verify existing output bytes and
reconcile its journal safely, without claiming the failed operation committed.
Also corrupt/truncate/remove the journal and a referenced chunk; plant orphan
partial files; exercise retained-state GC under ownership; and inject write,
rename and sync failures. No failed attempt may publish reusable success.
Storage bounds must distinguish live journal references from evictable cache
entries and arbitrary payload bytes.

## Execution and evidence

Build only through normal `scripts/build-slot.sh build` admission, using pinned
Zig, the existing worktree `.zig-cache`, default shared global cache and
`.mylang-cache/cache-wave7bc/tmp`. Product source stays frozen during combined
qualification; source variants and all stores/binaries live in ignored cache.
Retain commands, compiler/fixture/interposer hashes, case outcomes, admissions,
fault markers and final CSV hashes under this experiment directory. Do not copy
binaries or caches into git. Later register every committed script/fixture in
the appropriate input recipes. No performance comparison is implied.

SIGKILL testing establishes process-crash recovery. File and directory fsync
ordering can be reviewed and fault-injected, but it does not experimentally
establish power-loss durability; that claim needs separate filesystem/device
qualification.
