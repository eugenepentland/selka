# Persistent CLI checking sessions

`mylang check-session path/to/main.my` keeps bounded syntax, successful-verdict and
checked-body caches while checking fresh project snapshots on request. It accepts
repeated `--inputs` manifest options. A verdict hit requires exact equality of all
loaded module names, paths and source bytes; it replays owned warning text and
skips interface and semantic checking. When the verdict misses, the session still
reuses per-function checked bodies through the same bounded semantic cache that
one-shot commands use. Symbol indexes and whole typed programs are not retained.

```sh
printf 'check\ncheck\nclear\ncheck\nquit\n' | zig-out/bin/mylang check-session examples/corpus/invoice/main.my
```

Automatic watching is not part of the folded toolchain: the Python watch driver
was dropped, so start the process once and send `check` after source changes. The
synchronous line protocol has three commands:

- `check`: reread project files and input manifests and validate loading before
  looking for an exact successful verdict. A miss reuses available syntax and any
  unchanged checked bodies, then runs fresh interface and global semantic checks.
  The guest program is never executed.
- `clear`: release syntax, verdict and checked-body caches together; cumulative
  observations remain available.
- `quit`: acknowledge the command and exit successfully. EOF also exits; a final
  command without a newline is processed.

Each command produces one compact JSON line on stdout with version
`check-session-v1`, `action`, `status`, nullable host/protocol `failure`,
per-request `reuse` syntax hit/miss counts, cumulative syntax `cache`
observations, cumulative `semantic` verdict observations, cumulative `functions`
body observations and a `work-report-v1` `work` object whose request deltas
reconcile with the session totals. Status 0 means the check succeeded; 1 means
rejected source; 2 means input/host/protocol failure.
Source diagnostics and warnings use stderr, following ordinary CLI checking.
Requests are serial; this is not an LSP or multiplexed diagnostics protocol.
A failed check does not terminate the session. EOF/quit exit 0 even if earlier
requests reported errors, so callers inspect each reply's status.

Commands are trimmed for ASCII space/tab/carriage return. Unknown commands get an
error reply and the session continues. Lines longer than 128 bytes produce
`RequestTooLong` and terminate with exit 2; buffering is fixed at 256 bytes.
Runtime execution flags such as `--max-steps` are rejected because a checking
session does not run programs.
Unrecoverable stream/output failures may terminate the process with host failure.

Each check has a fresh request arena and Project. A verdict miss copies unchanged
parses into the fresh project and reuses any unchanged checked bodies. Syntax
retention allows 256 entries and 16 MiB of entry arena capacity, with
oldest-insertion eviction. The verdict cache retains one successful source
snapshot plus rendered warnings under a separate 16 MiB arena-capacity limit.
Checked bodies live in a third cache governed by the shared `reuse.max_bytes`
budget (16 MiB here), which also accounts for symbolic templates and concrete
specializations. Oversized entries bypass retention. Allocation failures remain
explicit host failures and preserve the previous successful entries.

These are retained-cache limits, not whole-process limits; the three caches can
retain up to roughly 48 MiB combined, excluding index storage. Fresh
project/module and manifest budgets still apply. Failed source checks are not
cached. A verdict hit increments `semantic.hits` while `reuse` remains zero because
no syntax lookup occurs.
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

This process keeps whole-project verdict reuse and per-function checked-body reuse
in one compiler process. Persistent checked bodies, symbolic-template and
concrete-specialization replay live in the one-shot `semantic-cache-v2` store
documented in [compiler caches](../tooling/caches.md#persistent-checked-body-store);
structured diagnostic framing, per-function lazy lowering and incremental native
linking remain open work. This is not completion of the incremental-compilation
roadmap.
