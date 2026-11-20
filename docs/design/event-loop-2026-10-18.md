# An event loop for Selka: one process, many connections, no threads

Status: implemented on `projects/event-loop` (project-ladder lane "event loop").
The user chose an event loop over threads for network concurrency on 18 October
2026. This page is the design; the API is documented in
[the standard library's `network` section](../standard-library.md#network) and
the decisions and measurements are in
`experiments/project-ladder-20261018/event-loop.md`.

## The problem

The Selka HTTP server (`selka-projects/http-server`) is single-threaded and
blocking: one accept loop, one connection at a time, `accept_resource` and
`read_resource` block. The gap ledger records what that costs:

| id | gap |
| --- | --- |
| FR-214 | one idle keep-alive client starves the server; nothing bounds a blocking read |
| FR-203 | a resource passed to a function is transferred even through `mut`, so connections cannot be held in helpers or collections |
| FR-204 | no way to learn a listener's bound port, so tests cannot listen on port 0 |
| FR-216 | an accepted connection has no peer address |
| FR-212 | a listener cannot be returned from the function that narrowed the `Network` |

The concurrency decisions already accepted keep CPU tasks fork/join only, with
handles confined to their task. This lane adds **no threads**: one thread waits
on many sockets at once.

## Constraints that shaped the design

1. **No change to the language shape or the ownership rules.** A resource cannot
   live in a list or a dictionary and cannot be borrowed by a helper (FR-203).
   Many connections therefore cannot be many `Connection` resources.
2. **No new authority.** Listening still needs `--allow-listen=IP:PORT`, matched
   verbatim against a `net.host("IP:PORT")` narrowing. Nothing here reads the
   clock, the environment or the file system.
3. **Few hand-synchronized compiler sites.** A new keyword builtin touches
   seventeen files (FR-201). The existing `acquire_resource`, `read_resource`,
   `write_resource` and `complete_resource` builtins already carry arbitrary
   bytes in and out of a provider-owned object.
4. **Slices copy (FR-108).** A response written over several wake-ups must be
   addressed by offset and count, not by `data[sent:]`.

## The design

### One `Poller` resource owns every socket

```
resource Poller: network            # new, in the network module
```

`network.open_poller(net)` binds the listening endpoint that the narrowed
`Network` names (the same `--allow-listen` check as `network.listen`), puts the
listener in an `epoll` set and returns one `Poller`. The runtime keeps the
accepted connections in a table inside the poller's state. The guest refers to a
connection by a small integer id, a plain value that can be a `dict[int,
ConnState]` key. The `Poller` is the only resource, so the loop function holds
exactly one local, which is the shape the ownership checker accepts.

Closing the poller (completing it, or dropping it at the end of its scope, or
the process ending) closes the listener and every connection it still holds.

### Operations are commands over the existing resource builtins

A `Poller` is read and written with `write_resource` (a command) and
`read_resource` (the response to the last command), the builtins every network
resource already has. The command is a 16-byte little-endian header
(`op, what, pad, pad, id, a, b`) optionally followed by a payload (the bytes of
a send). The response is a 12-byte header (`status, value, extra`) optionally
followed by a payload (received bytes, or event records). The stdlib `network`
module hides the encoding: a guest calls `network.wait`, `accept`, `recv`,
`send`, `shutdown_send`, `close_connection`, `port`, `peer`, `set_interest`,
`set_idle_timeout` and `connection_limit`.

This costs **zero new compiler sites**. `acquire_resource` gets one new mode tag
(2, beside 0 connect and 1 listen), preserved through `net.host` narrowing the
way tag 1 already is. The checker, the ownership passes and the Core lowering
treat a `Poller` exactly like a `Connection`, because to them it is one.

The wire format is an implementation detail of one stdlib module and one C file.
If the transport later becomes typed builtins (see "Alternatives"), only
`network.selka` changes; guest programs written against the wrappers do not.

### The wrappers hand the poller back (FR-203)

A resource passed to a function is transferred, so every wrapper takes the
`Poller` by value and returns it, and a loop reassigns one local:

```selka
# doc: not-selka
mut live = poller
live = network.wait(live, 100, mut ready)
```

Returning the bare resource matters. The recipe the network documentation taught
before, a record whose only field is the resource (`live = pump(live.connection,
...)`), checks but cannot be lowered inside a loop: the ownership pass reports
`Unsupported` with no message (see the lane notes). A function that takes a
resource and returns it reassigns cleanly in a loop, on the existing compiler.

Results that are not the poller come back through `mut` arguments (a `Ready` for
events, an `Outcome` for one operation, a byte builder for received bytes),
because projecting a scalar out of a record that holds a resource consumes the
record (FR-107). The pure decisions of a server live in functions that take ids
and bytes; only the thin I/O shell touches the poller.

### Readiness

`network.wait(poller, timeout_ms, mut ready)` blocks for at most `timeout_ms`
(0 polls, -1 waits for ever) and fills `ready` with up to 255 events, each an id
and a flag set:

| flag | value | meaning |
| --- | --- | --- |
| readable | 1 | bytes, a new connection (listener id 0) or end of stream can be read |
| writable | 2 | the socket send buffer has room (only when interest includes writable) |
| hangup | 4 | the peer closed or reset the connection |
| error | 8 | the socket has a pending error; the next `recv` or `send` reports it |
| idle | 16 | no transfer on this connection for the poller's idle timeout |

Readiness is level-triggered: an event repeats on the next wait until the guest
drains the socket, so a guest that stops early loses nothing. The listener is id
0. A connection id is `generation * 1024 + slot` with generation at least 1 for the first 1,024 slots, so
ids are at least 1024, are never 0, and a stale id for a closed connection never
names a newer connection that reused its slot (until 2^21 reuses of one slot). A
slot from 1,024 on, which only a poller of more than 1,024 connections has, is named
by `2^31 + generation * 2^bits + (slot - 1024)`, where `bits` is what the poller's
limit needs (at most 20, so a generation of at least 11 bits).

Interest defaults to readable. `network.set_interest(poller, id, mask)` adds or
removes writable (to be told when a partial send can continue) and can remove
readable (to apply back-pressure to a client whose earlier response is still
queued) without closing. Removing readable also stops the report that the peer
shut down its sending side, which would otherwise repeat on every wait; a full
hangup (both directions) or a socket error cannot be masked, so close a muted
connection once it reports one.

### Non-blocking accept, receive and send

Every data operation returns at once with an `Outcome.code`:

| code | name | meaning |
| --- | --- | --- |
| 0 | ok | `value` is the new id (accept), the bytes received or the bytes taken |
| 1 | would block | nothing available now (accept, recv) or no room now (send) |
| 2 | closed | the peer finished sending (recv saw end of stream) |
| 3 | failed | the socket reported an error; `value` is its errno |
| 4 | unknown | the id names no open connection (never opened, or closed) |
| 5 | full | the connection table is full (accept) |
| 6 | bad | a malformed command, or an argument the operation does not take (closing the listener, a peer address for the listener, an interest mask with unknown bits) |

`recv(poller, id, mut raw, mut outcome)` appends what is available, at most
16,384 bytes, to a byte builder. `send(poller, id, data, offset, mut
outcome)` offers `data[offset:offset + 64 KiB]` and reports in `outcome.value`
how many bytes the kernel took, so a large response is written over several
wake-ups and the guest advances `offset` itself; no remainder is sliced. The
runtime sets `TCP_NODELAY`, uses `MSG_NOSIGNAL` (a closed peer is `failed`, never
a signal) and non-blocking sockets throughout.

`accept` refuses to accept while the table is full and takes the listener out of
the epoll set until a slot is free, so a full server does not spin on a
listener it cannot serve; clients wait in the kernel's backlog.

### Timeouts (FR-214)

`wait`'s timeout bounds the blocking. For idle keep-alive connections the
poller keeps one `CLOCK_MONOTONIC` stamp per connection, set at accept and
refreshed by every `recv` or `send` that moves bytes.
`network.set_idle_timeout(poller, ms)` arms it for all connections (0 disarms).
A `wait` that finds a connection quiet for `ms` reports it with the idle flag
and restarts its stamp, so an ignored idle event repeats after another `ms`
instead of on every wait. The wait shortens its own timeout so the idle event
arrives on time. The runtime reads the clock for this and never tells the guest
the time: the `Clock` capability stays the only way to learn it.

A guest that prefers its own bookkeeping can ignore the idle flag, use `Clock`
and compute deadlines; the primitives allow both.

### FR-204 and FR-216 come with it

`--allow-listen=IP:0` is now a valid grant. It permits `net.host("IP:0")` and
binds the kernel-assigned port, matched verbatim like every other grant: a
`:0` grant does not permit `IP:8080` and `IP:8080` does not permit `IP:0`.
`--allow-endpoint=IP:0` stays a usage error (dialing port 0 is meaningless).
`--allow-all` and `--allow-listen=*` permit both. Only a `Poller` can report its
bound port, so `network.listen` (the blocking `Listener`, which has no query)
refuses a port-0 narrowing with `err(2)` rather than bind a port nobody can
learn. `network.port(poller, id, mut outcome)` returns the local port of the
listener (id 0) or of a connection; `network.peer(poller, id, mut outcome)`
returns the peer's IPv4 address and port for an accepted connection;
`network.format_address(address, port)` spells them.

### Limits

| limit | value | where it comes from |
| --- | --- | --- |
| connections per poller | the descriptor limit less 64, at most 1,048,576 (`1 << CORE_POLL_MAX_SLOT_BITS`) | `core_poll_create` raises the soft `RLIMIT_NOFILE` to the hard limit, or to 1,048,640 when that is lower, and 64 descriptors stay for the rest of the process (a started program gets the first soft limit back, `core_process_spawn`); the table starts at 1,024 slots (`CORE_POLL_INITIAL_SLOTS`) and doubles up to the limit |
| events per `wait` | 255 | one 2,060-byte response |
| bytes per `recv` or `send` call | 65,536 | the existing transfer limit of the scoped provider |
| pollers | share the 1024 resource limit and the 256 scoped handle slots with every file and connection | existing |
| memory | about 114 KiB for an idle poller (1,024 slots of 50 bytes and the 64 KiB response buffer), 50 bytes for each slot after that | malloc'd; `RLIMIT_AS` covers it |

A full table is the `full` outcome of `accept`. The explicit limit is
`network.connection_limit(poller, mut outcome)`.

## Alternatives considered

- **Typed builtins** (`poll_resource`, `recv_resource`, ...). Better static types
  and one call per primitive instead of two, and `recv` could return `bytes`
  directly (avoiding FR-205's per-octet copy). Rejected for this lane: every
  builtin is seventeen hand-synchronized sites plus a new reserved word, and a
  missed site fails late (FR-200, FR-202). The wrappers make the transport
  replaceable later without touching guests.
- **Connections as resources in a collection.** Would remove the poller's table
  but is an ownership-model change (a hard stop for this lane).
- **A runtime that buffers.** Reading and writing into runtime-owned buffers per
  connection (as Node or Go's netpoller do) hides would-block, but moves memory
  policy and back-pressure out of the guest's sight and out of the budgets.
  Rejected; the brief asks for a read that returns what is available and a write
  that returns how much was taken.
- **Edge-triggered epoll.** Faster for huge fan-out, but a guest that fails to
  drain a socket then hangs for ever. Level-triggered is the safe default.
- **`poll`/`select`.** `select` caps descriptors at 1024 and both are O(n) per
  call. `epoll` is available on every Linux this runtime targets.
- **Auto-accept inside `wait`.** Fewer calls, but the guest could not refuse or
  count connections before the runtime had taken them.
- **A monotonic time in each `Ready`.** Would give programs a clock without
  the `Clock` capability; the idle timeout does the same job without leaking it.

## What the HTTP server migration needs to know

- The loop is one function that owns the `Poller` and a `dict[int, Conn]`;
  everything else is a pure function of ids and bytes. `examples/event-loop-echo`
  and `test/fixtures/event_loop_server.selka` are two worked shapes.
- `network.wait`, `accept` and the rest each take the poller and return it:
  `live = network.recv(live, id, mut raw, mut outcome)`. Return the bare resource;
  a record that wraps it cannot be carried round a loop (see the lane notes).
- Wake on `LISTENER`: call `accept` until the outcome is not `OUTCOME_OK`
  (would block, or full). A new connection id is readable-only.
- Wake on a connection: `recv` until `OUTCOME_WOULD_BLOCK`, parse what the
  connection's buffer holds, and keep the parse state in `Conn`. `OUTCOME_CLOSED`
  is the client's end of stream (finish the response, then `close_connection`).
- A response is `send(live, id, data, conn.sent, mut outcome)` in a loop that adds
  `outcome.value` to `conn.sent`; when the outcome is would-block (or fewer bytes
  were taken), `set_interest(... EVENT_WRITABLE)` and continue on the writable
  event. While a response is queued, drop `EVENT_READABLE` so a pipelining client
  cannot grow the buffer.
- Keep-alive timeouts are `set_idle_timeout(live, ms, ...)` plus closing every
  connection that arrives with `EVENT_IDLE`; no `Clock` is needed.
- `peer(live, id, ...)` and `format_address` give the access log its client column.
- Tests can listen on `net.host("127.0.0.1:0")` with `--allow-listen=127.0.0.1:0`
  and read the port with `port(live, network.LISTENER, ...)`; a port announced on
  stderr (stdout is buffered until exit) is how a Zig or Python driver finds it.
- Open the poller from `main` with a `net.host` narrowing and pass it by value
  to the loop function (a resource cannot be returned from the function that
  narrowed the `Network`, FR-212).
- Descriptor limit: the hard limit less 64 connections per poller (at most 1,048,576).
  Above it `accept` answers `OUTCOME_FULL` and clients wait in the kernel backlog.

## Open

- FR-205: `recv` still appends octet by octet because a `FixedArray[u8, N]`
  cannot become `bytes` in one step. A typed `recv` builtin that returns `bytes`
  would remove it, and halve the calls per operation; the wrappers make that
  swap invisible to guests.
- A client-side poller (non-blocking `connect`) is not provided; a poller has
  one listener, so a proxy cannot multiplex its upstream connections with it.
- The blocking `Connection` and `Listener` still have no peer address or port
  query; only a poller reports them.
- The idle timeout is one value for the whole poller; per-connection timeouts
  (a shorter one for a connection that has not sent a request yet) are a guest
  bookkeeping job with `Clock`, or one more command.
