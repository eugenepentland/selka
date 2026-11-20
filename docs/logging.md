# Logging

The `logging` module gives a program one spelling for telling whoever started it what it is doing: a level, a time,
fields, one line each. It is written in Selka and holds the stream you give it and nothing else: it reads no environment,
opens no file and finds no clock of its own.

```selka
# doc: expect INFO listening port=8080
# doc: expect WARN disk at 91%
# doc: expect done
import logging

func main(out: Stream) -> int:
    const log = logging.new(out)
    logging.info(log, "listening", [logging.number("port", 8080)])
    logging.debug(log, "this line is not written: a new logger shows info and above")
    logging.warn(log, "disk at 91%")
    print(out, "done")
    return 0
```

A real program calls `logging.new(err)`; the examples pass `out` so the page can show the lines.

## A logger

`logging.new(stream)` makes a `Logger` that writes to `stream`, usually `err`; whoever starts the program redirects it.

A `Logger` is an ordinary record. Like any value that holds a capability
([records that hold capabilities](io.md#records-that-hold-capabilities)) it is passed, returned and stored in a record. It
holds a list and a name, so a record that keeps one stores `copy(log)`, or `own log` when `log` is not used again
([managed memory](managed-memory.md)).

```selka
# doc: expect INFO server up
# doc: expect INFO served path=/index
# doc: expect done
import logging

record Server:
    name: str
    log: logging.Logger


func serve(server: Server, path: str):
    logging.info(server.log, "served", [logging.text("path", path)])


func main(out: Stream) -> int:
    const log = logging.new(out)
    const server = Server(name="main", log=own log)
    logging.info(server.log, "server up")
    serve(server, "/index")
    print(out, "done")
    return 0
```

A setting does not change the logger it is given: each call answers a new logger.

| Call | Sets |
| --- | --- |
| `logging.with_level(log, level)` | the lowest level written |
| `logging.named(log, "store")` | the name written before the message; replaces an earlier name |
| `logging.with_field(log, field)` | a field added to every event, such as a request id; fields add up |
| `logging.with_clock(log, clock)` | the clock that gives each line its time |
| `logging.as_json(log)` | one JSON object per line instead of text |

## Levels

`Level` has the cases `debug`, `info`, `warn` and `error`, in that order. A logger writes events at its level and above: a
new logger shows info, `with_level(log, Level.debug)` shows everything. `logging.enabled(log, level)` answers whether an
event of that level would be written.

A dropped call formats nothing, but its arguments are still evaluated. When building the message costs something, ask
first:

```selka
# doc: expect INFO done
# doc: expect done
import logging

func describe(items: int[]) -> str:
    return f"{len(items)} items, the first is {items[0]}"


func main(out: Stream) -> int:
    const log = logging.new(out)
    const items = [4, 5, 6]
    if logging.enabled(log, logging.Level.debug):
        logging.debug(log, describe(items))
    logging.info(log, "done")
    print(out, "done")
    return 0
```

## Fields

Each of `logging.debug`, `info`, `warn` and `error` takes the event's fields as an optional last argument, a list of
`Field`:

| Call | Value |
| --- | --- |
| `logging.text(key, value)` | a `str` |
| `logging.number(key, value)` | an `int` |
| `logging.real(key, value)` | a `float`; `nan` and infinity are written `nan` and `inf` in text, `null` in JSON |
| `logging.flag(key, value)` | a `bool`, written `true` or `false` |

```selka
# doc: expect INFO served path=/index ms=31 load=0.5 cached=true
# doc: expect done
import logging

func main(out: Stream) -> int:
    const log = logging.new(out)
    logging.info(log, "served", [
        logging.text("path", "/index"),
        logging.number("ms", 31),
        logging.real("load", 0.5),
        logging.flag("cached", True),
    ])
    print(out, "done")
    return 0
```

Write the list in the call, or pass `copy(fields)` (`own fields` when not used again). A field for many events is bound
with `with_field`; it is written on every event of that logger, before the event's own:

```selka
# doc: expect INFO start request=r-17
# doc: expect INFO done request=r-17 ms=4
# doc: expect done
import logging

func main(out: Stream) -> int:
    const log = logging.new(out)
    const request = logging.with_field(log, logging.text("request", "r-17"))
    logging.info(request, "start")
    logging.info(request, "done", [logging.number("ms", 4)])
    print(out, "done")
    return 0
```

A `str` is valid UTF-8, so bytes that are not text are logged by what you can say of them: `logging.number("size",
len(data))` or `logging.text("data", hex.encode(data))`.

## The line

One event is one line, in text form by default: the time (only when the logger has a clock; UTC, as
`time.format_rfc3339` writes it), the level (`DEBUG`, `INFO`, `WARN`, `ERROR`), the name and a colon when set, the message,
then the fields as `key=value`, bound fields first.

```selka
# doc: expect 2026-11-17T09:35:14Z WARN store: slow request path=/tmp/x ms=31 note="two words"
# doc: expect done
import logging
import time

func main(out: Stream) -> int:
    const clock = time.simulated_clock(time.from_unix_nanoseconds(1794908114000000000))
    const base = logging.with_clock(logging.new(out), clock)
    const log = logging.named(base, "store")
    logging.warn(log, "slow request", [
        logging.text("path", "/tmp/x"),
        logging.number("ms", 31),
        logging.text("note", "two words"),
    ])
    print(out, "done")
    return 0
```

A clock that fails (`time.failing_clock`) never stops the program: the line is written without its time.

| Part | Rule |
| --- | --- |
| Quoting | a value is in double quotes when empty or holding a space, `=`, `"` or a control byte (below 0x20, or 0x7f) |
| Escapes | in quotes and in the message (never quoted): `\n`, `\r`, `\t`, `\"`, `\\`, and any other control byte as `\x` and two lowercase hex digits |
| Keys and names | written bare: each space, `=`, `"`, `\` and control byte becomes `_`, an empty key is `_` (`two words` gives `two_words=x`) |

So a message holding a newline, or text that looks like another event, stays on its line:

```selka
# doc: expect INFO login failed\n2026-11-17T00:00:00Z ERROR forged
# doc: expect WARN rejected user="a\"b" note="x\ty"
# doc: expect done
import logging

func main(out: Stream) -> int:
    const log = logging.new(out)
    logging.info(log, "login failed\n2026-11-17T00:00:00Z ERROR forged")
    logging.warn(log, "rejected", [logging.text("user", "a\"b"), logging.text("note", "x\ty")])
    print(out, "done")
    return 0
```

## JSON lines

`logging.as_json(log)` writes one JSON object per line: `time`, `level` (lowercase, as `parse_level` reads it), `logger` and
`message` first (each only when present), then the fields in order, as JSON numbers, booleans and strings.

```selka
# doc: expect {"time":"2026-11-17T09:35:14Z","level":"warn","logger":"store","message":"slow request","path":"/tmp/x","ms":31,"ok":false}
# doc: expect done
import logging
import time

func main(out: Stream) -> int:
    const clock = time.simulated_clock(time.from_unix_nanoseconds(1794908114000000000))
    const log = logging.as_json(logging.named(logging.with_clock(logging.new(out), clock), "store"))
    logging.warn(log, "slow request", [
        logging.text("path", "/tmp/x"),
        logging.number("ms", 31),
        logging.flag("ok", False),
    ])
    print(out, "done")
    return 0
```

A field named `time`, `level`, `logger` or `message` gets a `_` after its key in JSON (`message_`); the text form writes it
as it is. A key given twice is written twice in text; JSON keeps the last value at the place of the first.

## Written whole and flushed

Each event is written in one call and flushed, so a line is never split by another write and one written just before a
trap, a `fail` that ends the program or a signal is out.

A failed write behaves as `print` to that stream does ([stream](io.md#stream)): standard error ignores it, a reader that
has gone ends the program quietly with status 141, and standard output traps `R_OUTPUT` with status 1. A
`streams.memory()` never fails.

## Tasks

A `parallel` task holds no capability ([tasks take values](concurrency.md#tasks-take-values)), so passing it a `Logger`, or
a record that holds one, is `E_TASK_CAPABILITY`. A task builds an `Event` (a plain value) with
`logging.event(level, message, fields)` and returns it; the caller writes the events after the group, in list order, with
`logging.write(log, event)`, which obeys the logger's level, name, fields, clock and form. The time is the time of the
write.

```selka
# doc: expect INFO checked path=/a
# doc: expect WARN long path path=/a/very/long/path
# doc: expect done
import logging
import parallel

func check(path: str) -> logging.Event:
    if len(path) > 8:
        return logging.event(logging.Level.warn, "long path", [logging.text("path", path)])
    return logging.event(logging.Level.info, "checked", [logging.text("path", path)])


func main(out: Stream) -> int:
    const log = logging.new(out)
    const events = parallel.map(["/a", "/a/very/long/path"], check)
    for event in events:
        logging.write(log, event)
    print(out, "done")
    return 0
```

## The level from an option

`logging.parse_level(text)` reads `debug`, `info`, `warn` or `error` in any case and answers a `Level?`; other text,
`warning` included, is `None`.

```selka
# doc: expect WARN shown
# doc: expect unknown log level "loud": use debug, info, warn or error
import logging

func main(out: Stream) -> int:
    for wanted in ["warn", "loud"]:
        const level = logging.parse_level(wanted) else:
            print(out, f"unknown log level \"{wanted}\": use debug, info, warn or error")
            return 2
        const log = logging.with_level(logging.new(out), level)
        logging.info(log, "hidden")
        logging.warn(log, "shown")
    return 0
```

## Testing a program's logging

A logger over `streams.memory()` writes nothing to the process, and `streams.text(stream)` reads back what it wrote. With
`time.simulated_clock(...)` the times are the ones the test chose.

```selka
# doc: expect True
import logging
import streams
import time

func main(out: Stream) -> int:
    const sink = streams.memory()
    const clock = time.simulated_clock(time.from_unix_nanoseconds(0))
    const log = logging.with_clock(logging.new(sink), clock)
    logging.warn(log, "disk full", [logging.text("path", "/")])
    print(out, streams.text(sink) == "1970-01-01T00:00:00Z WARN disk full path=/\n")
    return 0
```

## Not in it

There is no global logger, handler, hierarchy, file, rotation, colour or sampling: pass the logger you made, and redirect
standard error.
