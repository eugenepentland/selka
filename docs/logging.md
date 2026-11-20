# Logging

A program tells whoever started it what it is doing with `print(err, ...)`, and every program spells that its own way:
its own prefix, no level, no time. The `logging` module is the one spelling. It is a library written in Selka (no
builtin behind it), and it follows the language's rules: it holds the stream you give it and nothing else, so it reads no
environment, opens no file and finds no clock of its own.

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

A real program passes `err` to `logging.new`; the examples on this page pass `out` so that the page can show the lines
(`selka doctest` compares standard output). Each of them ends by printing `done`, the program's own output, which is
also how the page checker knows that an example writes.

## In short

- **A logger is made from a stream the program holds**: `logging.new(err)`. It has a level, a name, fields, a clock and
  a form, each set by a function that returns a changed logger: `with_level`, `named`, `with_field`, `with_clock`,
  `as_json`. Nothing is global, and nothing reads the environment.
- **Four levels in order**, `Level.debug`, `Level.info`, `Level.warn`, `Level.error`; a new logger writes info and above.
  `logging.debug(log, message)`, `logging.info`, `logging.warn` and `logging.error` write an event.
- **Fields are typed** and go last: `logging.text(key, value)`, `logging.number(key, value)` (an `int`),
  `logging.real(key, value)` (a `float`) and `logging.flag(key, value)`.
- **One event is one line**, whatever its message and fields contain. A newline in a message cannot start a second line.
- **A line is written whole and flushed**, so it is never split and it survives a trap that follows it.
- **A task cannot log**: it holds no capability. It builds an `Event` with `logging.event(...)`, returns it, and the
  caller writes it after the group with `logging.write(log, event)`.
- **A test reads the lines back**: `logging.new(streams.memory())` and `streams.text(...)`.

The public names are `new`, `with_level`, `with_clock`, `named`, `with_field`, `as_json`, `enabled`, `debug`, `info`,
`warn`, `error`, `text`, `number`, `real`, `flag`, `parse_level`, `event` and `write`, and the types `Level`, `Field`,
`Logger` and `Event`.

## A logger

`logging.new(stream)` makes a `Logger` that writes to `stream`. The stream is a capability the program already holds,
usually `err` (standard error is where a program's own messages belong, and whoever starts it redirects that stream to a
file or a collector: the library opens no file and has no rotation). The logger also reads no environment: the level
comes from text the program gives it ([the level from an option](#the-level-from-an-option)).

A `Logger` is an ordinary record. It holds the stream, an optional `Clock`, the level, the name, the bound fields and
whether to write JSON. Like any value that holds a capability ([records that hold
capabilities](io.md#records-that-hold-capabilities)) it is passed to a function, returned and stored in another
record. A function that logs takes it as a parameter, as it takes a `Stream`, and a record that keeps one stores a
`copy(log)` (or `own log` when `log` is not used again), because a logger holds a list and a name (a managed value, [managed
memory](managed-memory.md)).

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

A setting does not change the logger it is given: `logging.with_level(log, level)` answers a logger like `log` with
another level, and `log` is as it was. The settings are:

| call | what it sets |
| --- | --- |
| `logging.with_level(log, level)` | the lowest level written |
| `logging.named(log, "store")` | the name written before the message; replaces a name set before |
| `logging.with_field(log, field)` | a field added to every event, such as a request id; the fields add up |
| `logging.with_clock(log, clock)` | the clock that gives each line its time |
| `logging.as_json(log)` | one JSON object per line instead of text |

## Levels

`Level` is an enum with the cases `debug`, `info`, `warn` and `error`, in that order. A logger writes the events at its
level and above, and drops the rest: a new logger shows info, `with_level(log, Level.debug)` shows everything, and
`with_level(log, Level.error)` only errors. `logging.enabled(log, level)` answers whether an event of that level would be
written.

A dropped call does no work: it tests the level and returns, and it formats nothing. The message you pass is another
matter. Selka has no lazy arguments, so `logging.debug(log, describe(table))` runs `describe(table)` before the call
whether or not debug is shown. When building the message costs something, ask first:

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

```selka
# doc: expect DEBUG shown now
# doc: expect ERROR only errors from here
# doc: expect done
import logging

func main(out: Stream) -> int:
    const everything = logging.with_level(logging.new(out), logging.Level.debug)
    logging.debug(everything, "shown now")
    const quiet = logging.with_level(everything, logging.Level.error)
    logging.warn(quiet, "dropped")
    logging.error(quiet, "only errors from here")
    print(out, "done")
    return 0
```

## Fields

Each of the four level functions takes the event's fields as an optional last argument, a list of `Field`. A field is
made by the function that names its type:

| call | the value |
| --- | --- |
| `logging.text(key, value)` | a `str` |
| `logging.number(key, value)` | an `int` |
| `logging.real(key, value)` | a `float` |
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

The list is the call's own: write it in the call, or give a list built earlier as `copy(fields)` (`own fields` when it is
not used again), the ordinary rule for a value stored in an option. A field that belongs on many events is bound to the
logger instead: a field bound with `with_field` is written on every event of that logger, before the event's own, so a
request id is set once:

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

A `float` that is `nan` or infinite is written `nan` or `inf` in text and as `null` in JSON, which has no such number.
A `str` holds valid UTF-8 and nothing else, so the logger never meets bytes that are not UTF-8: `strings.decode(data)`
fails on them, and the program logs what it can say about the data instead (`logging.number("size", len(data))` or
`logging.text("data", hex.encode(data))`).

## The line

Text is the default form. One event is one line:

    2026-11-17T09:35:14Z WARN store: slow request path=/tmp/x ms=31 note="two words"

The time comes first and only when the logger has a clock (`with_clock`): UTC, as `time.format_rfc3339` writes it. Then
the level (`DEBUG`, `INFO`, `WARN`, `ERROR`), the name and a colon when a name is set, the message, and the fields as
`key=value`, bound fields first.

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

The clock is read when the line is written. A clock that fails (`time.failing_clock` is one) never stops the program: the
line is written without its time.

**Quoting.** A value is written in double quotes when it is empty or holds a space, an `=`, a `"` or a control byte (a byte
below 0x20, or 0x7f); any other value is written as it is. A number or a flag never needs them.

**Escapes.** Inside quotes, and in the message, which is never quoted, a newline is written `\n`, a carriage return `\r`,
a tab `\t`, a `"` is `\"`, a `\` is `\\`, and any other control byte is `\x` and two lowercase hex digits (`\x1b`).
So a message that holds a newline, or a line that looks like another event, stays on its line:

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

**Keys and names.** A key and a logger name are written bare, so each space, `=`, `"`, `\` and control byte in one is
written `_` instead, and an empty key is `_`. (`logging.text("two words", "x")` is `two_words=x`.) The text form of an
event is therefore always one line of `key=value` words.

## JSON lines

`logging.as_json(log)` writes one JSON object per line, built with the `json` module: `time`, `level`, `logger` and
`message` first (each only when present: no clock, no time; no name, no logger), then the fields in order. A number is
a JSON number, a flag a JSON boolean, a text a string. The level is written in lowercase, as `parse_level` reads it.

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

A field named like one of the four, `time`, `level`, `logger` or `message`, would replace the event's own, so in JSON its key
gets a `_` after it (`message_`). In the text form such a field is written as it is: the level and the message
are not `key=value` words there, so nothing is confused. A key given twice is written twice in the text form; a JSON
object holds one, so the last value stays, at the place of the first.

## Written whole and flushed

Each event is built as one piece of text with its newline, written to the stream in one call and flushed. A line is
never split by another write, and a line written just before a trap, a `fail` that ends the program or a signal is out.

A write that fails behaves as `print` to that stream does, and the library adds nothing to it. Standard error ignores
the failure (a closed or full standard error is not an error: the program goes on and the line is lost), except that a
reader that has gone ends the program quietly with status 141. Standard output does not ignore it: a refused write
traps with `R_OUTPUT` and status 1, so a logger made from `out` ends the program at the first line a full disk refuses; a
pipe whose reader has gone (`prog | head -5`) ends it quietly with status 141, with no message, for `out` and `err`
alike ([stream](io.md#stream)). A memory stream (`streams.memory()`) never fails.

## Tasks

A `parallel` task holds no capability ([tasks take values](concurrency.md#tasks-take-values)), so it cannot log:
passing it a `Logger`, or any record that holds one, is `E_TASK_CAPABILITY`. An `Event` is a plain value: the level, the
message and the fields. A task builds one with `logging.event(level, message, fields)` and returns it, and the caller
writes the events after the group, in the order of the list, with `logging.write(log, event)`. The time on the line is the
time of the write, since a task has no clock.

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

`logging.write` obeys the logger's level, name, bound fields, clock and form, like the level functions. The refused shape
is the task that takes the logger:

```selka
# doc: expect-error E_TASK_CAPABILITY
import logging
import parallel

func check(path: str, log: logging.Logger) -> int:
    logging.info(log, "checked", [logging.text("path", path)])
    return len(path)


func main(out: Stream) -> int:
    const log = logging.new(out)
    const sizes = parallel.map(["/a", "/b"], check, log)
    print(out, sizes)
    return 0
```

## The level from an option

`logging.parse_level(text)` reads `debug`, `info`, `warn` or `error` (in any case) and answers a `Level?`; any other text,
`warning` included, is `None`. A `--log-level` option is two lines: the parse and the refusal.

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

There is no global logger (a program passes the one it made), no handler, no hierarchy of loggers, no file or rotation (a
program logs to standard error and whoever starts it redirects that), no colour and no sampling.
