# Persistent schematic development host

The installed `schematic-svg` host now supports request-boundary generation
replacement. The watcher invokes one host process and never invokes Zig or Guardian:

```sh
python3 scripts/dev.py --runner zig-out/bin/schematic-svg \
  --project src/schematic/guest --output /tmp/schematic.svg \
  experiments/schematic/fixtures/straps-synth-lmx2595.sexp \
  experiments/schematic/fixtures/lmx2595rhar.sexp \
  experiments/schematic/fixtures/spi.sexp
```

Watch `/tmp/schematic.svg.status.json` as well as the SVG. `fresh` means the
preview represents the recorded captured source/input generation. `stale` means
an edit is pending or failed; the prior preview remains available. `stopped` means
the watcher is no longer maintaining freshness. Status includes the source digest,
last active digest, host PID and failure identity. Located compiler and schematic
diagnostics go to stderr. A viewer must use the status file to display a stale
label; the SVG alone cannot signal freshness. Output and status are individually
atomically replaced; status becomes stale before a build, and fresh only after
successful output publication. `--once` performs one stable attempt and exits.

The coordinator captures all `.selka` files, directory membership and three request
inputs, debounces, checks that capture is still current, and writes private temporary
snapshot files. It includes new imports and deletions without depending on the old
module graph. Source snapshots enforce the project byte/file limits; request inputs
are limited to one MiB each. Traversal is capped at 8192 entries and rejects
symlinks and nonregular inputs (including FIFOs) without blocking. Compilation reads only the captured directory. Before
committing a prepared generation, the coordinator captures the live inputs again.
An intervening edit discards that generation and retries. These checks are intended
for local development, not a transactional filesystem or a proof against malicious
concurrent writers or an edit that changes and restores bytes between observations.
The source root is trusted, and source symlinks are unsupported.

The host's private `--dev-session` protocol accepts one JSON object per line:

- `prepare`, with `project` directory and three `documents` paths, compiles and
  executes a candidate with fresh guest state. The response contains `prepared`
  and the complete output, or `error` and its error identity.
- `commit` releases the old active generation and activates the prepared one.
- `discard` releases the candidate without changing the active generation.
- `quit` or EOF releases both generations and exits.

The coordinator does not send another request while one executes. Thus swaps
occur with no active VM frames. The host retains at most one active and one
candidate compilation; per-request document, host registry, VM and output storage
is released after each request. Typed host registration and execution must succeed
before a candidate can be activated. Failed or superseded candidates never replace
the preview. A prepared program owns its copied source and diagnostic mappings, so
snapshot files can be removed after preparation. The public coordinator owns the
snapshot contract; callers of the private protocol must also provide immutable
input paths.

This implementation recompiles on fixture changes as well as source changes. It
provides persistent host generations, not incremental semantic compilation. It
does not preserve guest heap state, patch instructions or execute concurrent
requests. Native host state is currently request-local. Compiler/VM/native-wrapper
changes require a binary rebuild and restart. Future concurrent request handling
needs reference-counted generation lifetimes; future persistent guest state needs
explicit serialization and migration.

> The Python development-host/watch driver was dropped in the Zig-native tooling
> fold. This page is retained as a historical design record.

Validation: `tests/dev_reload.py --runner PATH` covers source and fixture changes,
compile and host-contract errors, repair, import membership, immutable snapshots,
repeated replacements with a bounded RSS-growth check on Linux, stable host PID,
unchanged binary identity, no build tools on watcher PATH, discard/commit ordering,
a deliberately superseded request and clean shutdown. The existing schematic
acceptance driver independently validates the real circuit output. The RSS check
is a coarse regression bound, not a leak proof or a cross-platform memory budget.

The watcher bounds host replies to 32 MiB and 180 seconds, including incomplete
reply lines. SIGINT and SIGTERM close the host, escalating termination if a running
request does not finish promptly. Polling/debounce durations must be finite.
