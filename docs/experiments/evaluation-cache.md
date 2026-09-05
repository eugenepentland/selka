# Persistent restricted-evaluation cache

The local evaluation driver now reuses successful results by checked request identity:

```sh
zig build
python3 scripts/evaluate.py examples/modules/main.my --cache-dir .mylang-cache
python3 scripts/evaluate.py examples/modules/main.my --cache-dir .mylang-cache
```

The first run reports a cache miss and VM execution; the second reports a hit and a
skipped VM, both with the typed decimal result 12. The cache directory is explicit.
`--compiler`, `--max-steps`, `--max-frames`, and `--max-eval-bytes` select the compiler
and evaluation budgets. `--timeout` bounds each compiler subprocess (default 90 seconds).

## Lookup and execution

Every invocation first runs eval-project --evaluation-request. Thus source loading,
parsing, type checking, lowering, bytecode validation, authority checks, and compiler
identity hashing still run even on a hit. The driver does not infer source validity
from a previous result or filesystem timestamps.

The request digest names a JSON entry in the chosen directory. A usable entry must
have the supported envelope/report versions, matching request digest and full request,
a valid report checksum, and a canonical in-range i64 decimal result. Duplicate JSON
keys, malformed/oversized documents, unsupported formats, bad checksums, wrong requests,
and invalid result encodings cause a miss with reason invalid-cache. Missing entries
report not-found. Cache documents are limited to 16 MiB. Filesystem access failures
remain host failures instead of silently claiming a successful hit.

On a miss, the driver runs eval-project --evaluation-report. It compares that report's
request and digest with the lookup request before storing a result. A source/compiler
change between those two snapshots fails with a retry message and writes no entry.
A hit corresponds to the source snapshot captured by its fresh request, as ordinary
compilation also uses loaded source bytes; it does not freeze files against later edits.

Only successful evaluated results are cached. Invalid source, forbidden authority,
traps, timeouts, and exhausted budgets do not create a result entry. Existing entries
remain available if sources later return to their previous identities. Compiler and
budget changes are part of the key, as are all declared source/import bytes.

## Storage and reporting

Writes use a same-directory temporary file, flush/fsync, then atomic replacement.
Temporary files are removed on failed replacement and existing entries are preserved.
Concurrent successful writers for the same deterministic request can replace the same
entry; there is no lock or duplicate-execution suppression. Cache entries are local
trusted build state. Their checksums detect accidental corruption, not malicious edits
with recomputed checksums. The driver does not upload data or write into source files.

Successful stdout is eval-cache-run-v1 JSON with cache hit/miss, reason, frontend
checked, VM executed/skipped, request digest, and typed result. Compiler diagnostics
remain on stderr, semantic/runtime failures retain status 1, and driver/host failures
use status 2. This reports actual invocation behavior, not inferred test coverage or
estimated time savings.

## Acceptance and remaining work

The build runs tests/evaluation_cache.py against its actual compiler. Instrumented
compiler invocations establish request+evaluation on a cold miss and request-only on
a hit. Tests cover source/budget changes, corrupted entry repair, invalid documents
and i64 encodings, wrong requests, injected atomic-write failure with cleanup, rejected
source/runtime failures without cache writes, and a source change deliberately inserted
between lookup and execution. Both Debug and ReleaseFast run these cases.

This implements persistent reuse of completed restricted VM evaluations. It does not
cache parsed/typed modules or native builds, perform dependency-granular recompilation,
explain which fields changed between historical requests, collect measured rebuild
savings, evict old entries, or suppress concurrent duplicate work. Those incremental
extensions, external input manifests, schema generation, and other unfinished roadmap
requirements remain pending.
