# Scoped synchronous resource providers

`language.scoped_providers.Context` packages filesystem and TCP callbacks for
`vm.Options.resources`. It borrows a configured open directory and a list of
`Endpoint { name, address }` grants. Keep the stable context and grants alive
until the VM's stores close; then call `Context.deinit` and close the directory.
The adapter releases all remaining handles even if the guest traps.

Filesystem acquisition requests are byte strings `r:relative/path` (read),
`w:relative/path` (write existing), `c:relative/path` (exclusive create), or
`t:relative/path` (truncate existing). Paths have at most 4094 bytes, contain no
empty, dot, dot-dot, NUL or backslash components, and cannot be absolute.
Directory traversal opens each component with symlink following disabled;
final opens also reject symlinks. Exclusive creation never follows an existing
link. Truncation occurs only after an authorized regular file has been opened.
Read-only capabilities reject all three writing modes before opening anything.
The host's filesystem tree is trusted: directory handles retain authority when
renamed, and directory scoping does not distinguish hard links to shared inodes.

TCP acquisition matches the exact configured endpoint name before connecting
to its pre-parsed numeric IP address. There is no DNS, HTTP redirect, TLS, process
launching, or implicit endpoint discovery. Read and write operations preserve
partial progress, cap each transfer at 64 KiB, and report EOF distinctly. Empty
reads report zero bytes without claiming EOF. Completion closes the handle;
release closes without application-level commit semantics. These are blocking
synchronous providers; VM instruction budgets are not wall-clock I/O deadlines.

Provider errors map to the existing runtime categories (`Denied`, `Failed`,
`Unavailable`, allocation failure). Acquire failures retain no live handle.
The provider registry has a default 256-handle bound in addition to VM quotas.
EOF translation handles both zero-length reads and host EndOfStream errors.

`mylang-io --project APP --allow-dir=DATA` grants read-only directory access.
Add `--allow-write` to permit write, exclusive create and truncation. Repeated
`--allow-endpoint=127.0.0.1:9000` arguments grant up to 16 numeric TCP endpoints
(IPv6 uses `[::1]:9000`). No grant means the corresponding entry capability is
unavailable. Resource effects occur during execution; only raw stdout is buffered
for publication after a successful guest exit. Filesystem writes and network
traffic are not rolled back on a later guest failure.

Applications using mylang-io still import their explicit `io` host declaration
(length, byte and put), as in the existing byte-I/O runner contract.

The standard filesystem additions also use read-authorized `m:path` metadata and
`l:path` directory snapshots. Empty paths name the granted root for these two modes
only. Snapshots default to 256 entries/64 KiB; limits are configurable together in
`Context.snapshot_limits`, and per-transfer reads remain capped at 64 KiB. Metadata
stats the final symlink itself; listing refuses to follow a symlink directory.
See [the typed guest APIs and wire contract](../standard-io.md#metadata-and-directory-snapshots).
