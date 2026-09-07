# Persistent CLI checking sessions

`mylang check-session path/to/main.my` keeps bounded syntax and successful-verdict
caches while checking fresh project snapshots on request. It accepts repeated
`--inputs` manifest options. A verdict hit requires exact equality of all loaded
module names, paths and source bytes. It replays owned warning text and skips
interface and semantic checking. Symbol indexes and typed programs are not retained.

```sh
printf 'check\ncheck\nclear\ncheck\nquit\n' | zig-out/bin/mylang check-session examples/corpus/invoice/main.my
```

For automatic checks after saving, use the [watch driver](watch.md). Editors can
also start the process once and send `check` after source changes. The synchronous line protocol has three commands:

- `check`: reread project files and input manifests and validate loading before
  looking for an exact successful verdict. A miss reuses available syntax and
  runs fresh interface and semantic checks. The guest program is never executed.
- `clear`: release both caches; cumulative observations remain available.
- `quit`: acknowledge the command and exit successfully. EOF also exits; a final
  command without a newline is processed.

Each command produces one compact JSON line on stdout with version
`check-session-v1`, `action`, `status`, nullable host/protocol `failure`, per-request
`reuse` syntax hit/miss counts, cumulative syntax `cache` observations, and
cumulative `semantic` verdict observations. Status 0 means the
check succeeded; 1 means rejected source; 2 means input/host/protocol failure.
Source diagnostics and warnings use stderr, following ordinary CLI checking.
Requests are serial; this is not an LSP or multiplexed diagnostics protocol.
A failed check does not terminate the session. EOF/quit exit 0 even if earlier
requests reported errors, so callers inspect each reply's status.

Commands are trimmed for ASCII space/tab/carriage return. Unknown commands get an
error reply and the session continues. Lines longer than 128 bytes produce
`RequestTooLong` and terminate with exit 2; buffering is fixed at 256 bytes. VM
execution flags are rejected because a checking session does not run programs.
Unrecoverable stream/output failures may terminate the process with host failure.

Each check has a fresh request arena and Project. A verdict miss copies unchanged
parses into the fresh project. Syntax retention allows 256 entries and 16 MiB of
entry arena capacity, with oldest-insertion eviction. The verdict cache retains
one successful source snapshot plus rendered warnings, under a separate 16 MiB
arena-capacity limit. Oversized entries bypass retention. Allocation failures
remain explicit host failures and preserve the previous successful entry.

These are retained-cache limits, not whole-process limits; both caches can retain
up to 32 MiB combined, excluding index storage. Fresh project/module and manifest
budgets still apply. Failed source checks are not cached. A verdict hit increments
`semantic.hits` while `reuse` remains zero because no syntax lookup occurs.
`semantic.misses` counts attempts that reach verdict lookup and require checking;
input/loading failures can return before lookup. `stored`, `bypassed` and
`retained_bytes` report retention outcomes. These are actual work-reuse counts,
not timing measurements or evidence of a particular speedup.

`tests/check_session.py` edits source while the same process runs, verifies cold/warm
and one-module edit counts, checks type/privacy/deleted-file errors and recovery,
clears retention, repeats warm checks, checks invalid commands/EOF/oversized input,
and changes a manifest between requests. It verifies identical warning replay and
that source/privacy/removal errors cannot reuse a successful verdict. Cache unit
tests cover independent ownership, exact path/byte comparison, invalid verdicts,
retention limits and allocation-failure recovery. Actual Zig CLI tests verify cache clearing
and host-error recovery through redirected request/reply files. The standard build
runs these tests in Debug and ReleaseFast.

This reuses whole-project successful verdicts within one compiler process.
Persistent disk storage, finer declaration/function semantic queries, structured
diagnostic frames, and incremental native linking remain open work; this is not completion
of the incremental-compilation roadmap.
