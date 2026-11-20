# Event-loop echo server

An echo server that serves many clients at once on one thread. A single `Poller`
resource waits on the listening socket and on every accepted connection; the
program names each connection by the integer id `network.accept` returns and keeps
its per-client state in a `dict[int, Client]`. No client can block another: a
connection that is silent or slow to read costs the loop nothing, and one that is
silent for ten seconds is disconnected with `network.set_idle_timeout`.

```sh
selka run examples/event-loop-echo/main.selka --restrict --allow-listen=127.0.0.1:0
```

`--allow-listen=127.0.0.1:0` lets the kernel choose the port, which the server
reports on stderr (stdout is buffered until exit, so a server announces itself on
stderr). Connect with `nc 127.0.0.1 PORT` from as many terminals as you like.

The poller is a resource, so every `network` call takes it and returns it:
`live = network.wait(live, -1, mut ready)`. The decisions live in plain functions
of ids and bytes; the two functions that touch the poller are `accept_all` and
`serve_client`. See [the event loop section of the standard library
page](../../docs/standard-library.md#event-loop) and
[the design note](../../docs/design/event-loop-2026-10-18.md).
