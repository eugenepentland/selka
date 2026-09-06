# Persistent CLI checking sessions

`mylang check-session path/to/main.my` keeps one bounded syntax cache while checking
fresh project snapshots on request. It accepts the existing repeated `--inputs`
manifest options. No source file, generated input, symbol index, or semantic verdict
is retained between requests; only the owned parse cache survives.

```sh
printf 'check\ncheck\nclear\ncheck\nquit\n' | zig-out/bin/mylang check-session examples/corpus/invoice/main.my
```

For automatic checks after saving, use the [watch driver](watch.md). Editors can
also start the process once and send `check` after source changes. The synchronous line protocol has three commands:

- `check`: reread project files and input manifests, reuse exact syntax matches,
  and rerun interface and semantic checking without executing the guest program.
- `clear`: release retained syntax; cumulative observations remain available.
- `quit`: acknowledge the command and exit successfully. EOF also exits; a final
  command without a newline is processed.

Each command produces one compact JSON line on stdout with version
`check-session-v1`, `action`, `status`, nullable host/protocol `failure`, per-request
`reuse` hit/miss counts, and cumulative `cache` observations. Status 0 means the
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

Each check has a fresh request arena and Project. Manifest-generated source and
all checking allocations are released after the response; unchanged parses are
copied into the new project from the cache. Retention uses the existing defaults:
64 entries and 16 MiB of entry arena capacity, with oldest-insertion eviction.
Those are retained-cache limits, not whole-process limits. Project source/module
budgets and manifest budgets also continue to apply. Statistics count real syntax
reuse, not skipped semantic work or a claimed speedup.

`tests/check_session.py` edits source while the same process runs, verifies cold/warm
and one-module edit counts, checks type/privacy/deleted-file errors and recovery,
clears retention, repeats warm checks, checks invalid commands/EOF/oversized input,
and changes a manifest between requests. Actual Zig CLI tests verify cache clearing
and host-error recovery through redirected request/reply files. The standard build
runs these tests in Debug and ReleaseFast.

This exposes incremental syntax reuse through a long-lived CLI. Persistent disk
storage, semantic query reuse, structured diagnostic
frames, and incremental native linking remain open work; this is not completion
of the incremental-compilation roadmap.
