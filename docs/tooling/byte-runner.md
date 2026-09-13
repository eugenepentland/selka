# The byte runner host

`mylang-io --project DIRECTORY` is the smallest useful host for a guest program:
it reads standard input as raw bytes, checks and runs the project's `main`, and
publishes the buffered output only when the guest exits successfully. Everything
the guest is allowed to touch beyond those bytes is named on the command line.
The design records are [bounded byte block I/O](../byte-io-bulk.md) and
[scoped synchronous resource providers](../experiments/scoped-providers.md).

## Scoped directory and endpoint providers

The runner provisions a filesystem or network capability only from an explicit
grant. `--allow-dir=PATH` opens one directory read-only; `--allow-write` widens
that same grant to writing, exclusive creation and truncation and is a usage
error without it. `--allow-endpoint=IP:PORT` may be repeated for up to sixteen
numeric TCP endpoints (IPv6 written `[::1]:9000`). Without the matching grant the
entry capability is simply unavailable, and the program stops rather than falling
back to ambient authority. Filesystem acquisition requests are byte strings with
a mode prefix — `r:`, `w:`, `c:`, `t:`, `k:`, `x:` — over a relative path of at
most 4094 bytes with no empty, dot, dot-dot, NUL or backslash component;
traversal opens every component with symlink following disabled and final opens
reject symlinks too. A TCP request must match a configured endpoint name exactly
before the pre-parsed numeric address is dialled: there is no DNS, TLS, redirect
or process launching, and each transfer is capped at 64 KiB with partial progress
reported. These are blocking synchronous providers, VM instruction budgets are
not wall-clock deadlines, and effects that already happened are not rolled back
when the guest fails afterwards.

```console
$ mylang-io --project reader < /dev/null
mylang-io: CapabilityUnavailable
$ mylang-io --project reader --allow-dir=data < /dev/null
scoped read
```

## Filesystem metadata and listings

Two further read-authorized modes answer questions about the granted tree without
opening a file for content. `m:path` publishes ten immutable bytes — version `1`,
a kind byte (0 other, 1 file, 2 directory, 3 symlink) and eight little-endian
size bytes — describing a final symlink itself rather than what it points at.
`l:path` publishes a version byte followed by one record per entry: a kind byte,
a little-endian `u16` name length, and that many opaque name bytes. An empty path
denotes the granted root, and only for these two modes. Snapshots default to 256
entries and 64 KiB of encoded bytes; exceeding either bound denies the whole
acquisition rather than publishing a truncated answer, listing refuses to follow
a symlinked directory, and writes through a metadata or listing handle are
denied. Directory order is unspecified, listings are not recursive, entry names
are bytes rather than text, and a snapshot describes the directory at the moment
it was taken, not what a later open will find. Below, the guest asks for the kind
of `notes.txt` and then lists the granted root.

```console
$ mylang-io --project describe --allow-dir=data < /dev/null
1
notes.txt
```

## Budgets

Budget flags follow `--project DIRECTORY` and use `=` syntax with unique decimal
values: `--max-input`, `--max-output`, `--max-steps`, `--max-calls` and
`--max-work`. Input and output capacity may be zero; the three execution budgets
must be positive. Unknown flags, repeated limits, non-decimal values and overflow
are rejected before the guest is invoked, so a mistyped budget never runs with a
default silently substituted. Defaults are 2 MiB of input, 128 MiB of
unpublished output, 2,000,000,000 VM steps and 300,000,000 host calls and work
units. Input is bounded by its configured limit plus one detection byte, and
output is bounded by its configured capacity; source parsing and VM metadata keep
their own separate budgets. Exhausting a host budget traps the guest, and because
output is published only after a successful zero exit, a trapped run publishes
nothing at all.

```console
$ printf 'hello bytes' | mylang-io --project examples/contract-echo
hello bytes
$ printf 'hello bytes' | mylang-io --project examples/contract-echo --max-input=64 --max-output=5
main.my:6:13: error[R_HOST_LIMIT]: HostWorkLimit
          _ = io::put(io::byte(index));
              ^
  in main::main at main.my:6:13
mylang-io: GuestTrap
$ echo $?
1
```
