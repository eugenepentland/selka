# Printing, files and command-line authority

`print(out, …)` and the file surface give application code the I/O a Python
programmer expects. The entry point declares `out: Stream`/`err: Stream`, and the
runtime always supplies them, so printing itself needs no host grant. Touching
the filesystem, the clock, entropy or the environment does, and the entry point
names each one it needs — but `selka run` grants them all by default, so an
ordinary program just runs. Pass `--restrict` when you want the command to
withhold authority instead.

## print

```selka
# doc: expect hello 42 True None
# doc: expect ['a', 'b'] {'k': 1} b'\x00\xff'
func main(out: Stream) -> int:
    print(out, "hello", 42, True, ())
    print(out, ["a", "b"], {"k": 1}, b"\x00\xff")
    return 0
```

Arguments are separated by single spaces and followed by one newline. `sep=` and
`end=` replace either, and both accept any `str` expression:

```selka
# doc: expect 1-2-3!
func main(out: Stream) -> int:
    print(out, 1, 2, 3, sep="-", end="!\n")
    return 0
```

Every ordinary value renders the way Python spells it. `str` prints raw at the
top level and `repr`-quoted inside a container; `bytes` prints as a `b'...'`
literal; `float` keeps a `.0` when it has no fractional digits; records print as
`Name(field=value)`, enum and union cases as `Name.case`, and checked results and
optionals as `Ok(...)`, `Err(...)`, `Some(...)` and `None`:

```selka
# doc: expect Point(x=1, y=2) Colour.green
# doc: expect Ok(3) Err('nope') Some(4) None
record Point:
    x: int
    y: int

enum Colour:
    red
    green


func pick(n: int) -> int fails str:
    if n < 0:
        fail "nope"
    return n

func main(out: Stream) -> int:
    print(out, Point(x=1, y=2), Colour.green)
    mut found: int? = Some(4)
    mut missing: int? = None
    print(out, pick(3), pick(-1), found, missing)
    return 0
```

`str(x)` and `repr(x)` of a list, a set, a dictionary, an option, a record, a result or a fixed array give the text `print`
writes for it, and so does a format string's hole: one renderer writes them all
([the text of a collection](text.md#the-text-of-a-collection)). A set and a dictionary print in insertion order.

Nesting deeper than 24 levels renders as `...`, so a cyclic managed graph still
terminates. Capabilities, open files and callback values have no rendering and
are rejected while checking, and so is a value that holds one, wherever it holds it: `print(out, [stream])`, a record with a
`Stream` field and an option of a function are each `E_IO_ARGUMENT` at the check, naming the part that has no text and
saying to write a name or a count instead. `str`, `repr` and a format string's hole follow the same rule
([the text of a collection](text.md#the-text-of-a-collection)). Before 14 November 2026 `print(out, [f])` of a list of
functions checked and wrote a memory address, which differs from run to run, and `print(out, [stream])` checked and then
failed to build.

```selka
# doc: expect-error E_IO_ARGUMENT
func twice(n: int) -> int:
    return n * 2

func main(out: Stream) -> int:
    print(out, [twice])
    return 0
```

`print(out, …)` requires an explicit `Stream` argument. The old `noio` clause
is retired:

```selka
# doc: expect-error E_EFFECTS_REMOVED
func main(out: Stream) -> int noio:
    print(out, "not allowed here")
    return 0
```

Pass a stream from `main` to any helper that prints.

The bare `print(...)` and `eprint(...)` spellings are gone. They report
`E_OUTPUT_CAPABILITY` with the fix "add `out: Stream` to this function and pass
one from main"; `debug(...)` remains the only way to write without a capability.

```selka
# doc: expect-error E_OUTPUT_CAPABILITY
func main() -> int:
    print("no stream")
    return 0
```

`print(err, …)` is the standard-error form. It accepts the same values and
`sep=`/`end=` keywords and writes only standard error. The two streams are buffered and flushed independently, so an
`print(out, …)` line never mixes with a `print(err, …)` line even when both are used
together. Byte-exact stream separation is covered by the native CLI tests.

For a program's own messages (a level, a time, fields, one line each) use the [`logging`](logging.md) module instead of
a prefix of your own: `logging.new(err)` makes a logger from the stream you hold, and `logging.warn(log, "disk full")`
writes the line (`selka docs logging`).

## Format strings

An `f"..."` argument is written piece by piece, not built into a `str` first:
`print(out, …)` and `write(out, …)` both send each literal
piece and each hole's rendering straight to the stream. Printing or writing an
f-string therefore allocates nothing when its holes hold an integer, a `float`, a
`bool`, a `str` or `bytes`, with or without a format specification, and the bytes
written are the bytes the interpolation has always written. Each piece is spelled
once: a literal is one write of its bytes, a plain integer, `float` or `bool`
hole is one helper call that spells it into a small stack frame and writes it,
and only a hole with a written specification pays for that specification's
renderer. A hole whose own rendering allocates — a record, a list, a union or an
option — keeps that one rendering, and the pieces are still never joined.

A printed or written f-string is not free, though: it is output, so it costs one
formatting pass per piece and the write behind it. What it saves is the
allocations and the join, not the spelling work.

Using an f-string as a `str` — a binding, a store, an argument or a return value —
makes exactly one allocation: the result's own buffer, sized from the literal
lengths, the text holes' lengths, each scalar rendering's widest spelling and each
specified hole's own measure, and filled in place. A plain hole is never rendered
twice to size the buffer. `f"{text}"` of a value that is already a `str` is that
value, with no allocation at all.

```selka
# doc: expect row 3: value=9 ratio 0.30 note b'ab'
# doc: expect chars 36
func row(out: Stream, n: int) -> str:
    const text = f"row {n}: value={n * 3} ratio {0.3:.2f} note {b'ab'}"
    print(out, text)
    return text


func main(out: Stream) -> int:
    mut line = row(out, 3)
    write(out, f"chars {len(line)}")
    return 0
```

## Stream

`write(out, data)` writes bytes directly, including NUL and non-UTF-8 octets,
and answers nothing: a caller that needs the count takes `len(data)`. It adds no
quotes or newline. This is useful for binary protocols and UTF-8 output built as
bytes; it avoids converting the output to `str` and encoding it again. A `str`
argument is written as its UTF-8 octets. A window of a `bytes` is written where it
lies: `write(out, data[a:b])`, and `f.write(data[a:b])` on an open file, pass a view of
`data`'s octets and make no copy of the slice (1,000 such writes allocate nothing, and
`copy(data[a:b])` is the copy); only a slice of a `byte_buffer` is a new buffer.

```selka
# doc: expect world! 5
func main(out: Stream) -> int:
    const line = b"hello world\n"
    write(out, line[6:11])
    print(out, "!", len(line[6:11]))
    return 0
```

**A write to a stream whose reader has gone ends the program quietly.** A write or flush to *standard output* or *standard
error* that fails with `EPIPE`, because nothing reads the other end any more (`prog | head -5`, a closed terminal, a
collector that exited), ends the program at once with exit status 141 and no message: 128 plus `SIGPIPE`, which is what a
shell reports for a program that signal ended and what a Unix tool does there. The runtime keeps `SIGPIPE` ignored, so no
signal is raised and the program is not killed by one; buffered output is not written further, and the program's own status
(what `main` returned) is not used. It holds for `print`, `write` and `flush`, and for a large write as for a short one. `selka run` hands the 141 on as its own status and says nothing of its
own; when its standard error is what has gone (`selka run prog 2>&1 | head`), it stops reading the program's standard
error, and the program ends the same way at its next write there. A `selka test` test never meets it: a test's `out` and
`err` are captured, not written to a descriptor.

**Every other refused write or flush behind a stream differs by stream.** *Standard output* traps: `R_OUTPUT`
(`error[R_OUTPUT]: native execution failed`, then `standard output refused a write`) and exit status 1.
That holds for a full device (`> /dev/full`) and a closed descriptor (`>&-`), whichever of `print`, `write` or
`flush` meets it, and it is never a signal. *Standard error* ignores
the failure: the line or the octets are lost, the program goes on and ends with its own status (0 when `main`
returns 0), so a program cannot learn from a `Stream` that its diagnostics reached nobody. A stream the program
builds itself (`streams.memory()`) never fails. A write to a pipe the program opened itself keeps its own rules and is
not this ending: a file opened on a FIFO whose reader has gone traps `R_FILE` with the reason (`write 'ff': the other
end of the pipe is closed`, status 1); the input of a program it started with `process.run` is dropped from the point
the program stops reading, and the run goes on and answers with that program's status and output; a write to a closed
socket is an error result, or the `R_FILE` trap of a method of an open file.

A mutable [`byte_buffer`](bytes.md#writing-octets-in-place) is a byte string for
this purpose too: `write(out, buffer)` writes the octets the buffer holds right
now, straight out of the buffer's own storage. Nothing is copied and no snapshot
is built, so a program assembled in a buffer can reach the stream without a final
`bytes(buffer)`; it contributes the same `output` effect. Appending to the buffer afterwards cannot change what was already written.

`Stream` is a capability like `Filesystem`: the entry point declares the
standard streams it wants, and a helper may take any `Stream` name and be handed
either one. `print(out, values..., sep=, end=)` renders Python's `print`
spelling and `write(out, text)` writes the text. Both contribute the `output`
effect and write to the destination carried by the stream value. Streams are granted unconditionally, so
`--restrict` cannot take standard output away.

```selka
# doc: check
func main(out: Stream, err: Stream) -> int:
    print(out, "result:", 42)
    print(err, "note", sep=": ")
    write(out, "raw")
    return 0
```

A `Stream` stored in a record field is printed or written as the field:
`print(ctx.err, "note")`, `write(sink.stream, data)`, `flush(self.log.stream)`. The
first argument is a name followed by field names; a field that holds no `Stream` is
the same `E_OUTPUT_CAPABILITY` a bare `print` gets. Binding the field to a name first
(`const held = sink.stream`) still works, and the method spellings
`sink.stream.print(...)` and `sink.stream.write(...)` are retired.

```selka
# doc: check
record Sink:
    stream: Stream
    label: str


func note(sink: Sink, text: str):
    print(sink.stream, sink.label, text)
    flush(sink.stream)


func main(out: Stream) -> int:
    note(Sink(stream=out, label="stored:"), "ok")
    return 0
```

### Passing the stream as the first argument

The output functions take the stream as their first argument, which is a name or a
field of a name that holds a `Stream`:
`print(out, values..., sep=, end=)`, `write(out, data)` and `flush(out)`. They
answer unit, so a call stands on its own line and no `_ =` is needed.

Output is buffered. `print` and `write` append to the stream's buffer, and it
reaches the descriptor when `flush(out)` runs, when the buffer fills, or when the
program ends; a trap flushes standard output before it reports. Standard error is
unbuffered, so an `err.print` line appears before a later `out` line reaches its
buffer's end.

The runtime also flushes standard output before it waits for something outside the
program, so a service whose log is standard output shows each line while it waits, and
a signal that ends it there loses none of them. The places are the poller's
`network.wait` (unless its timeout is 0), a blocking read of standard input, of a
connection or of a file handle, `accept_resource` and a blocking connect (`network.connect`,
`connect_within`), `process.run`, `process.wait` and `wait_within` when they may wait,
`time.sleep` on a real clock, and a blocking `durable` lease. Only when the bytes arrive
changes: what the program writes and its order on each stream are what they were. A
program that computes for a long time between prints still holds its output until it
waits, flushes, fills the buffer or ends, and a signal that ends it then loses the buffer
(the program cannot hear a signal): call `flush(out)` for a line that must not wait.

```selka
# doc: expect written 3
# doc: expect trailing
func main(out: Stream) -> int:
    write(out, "written ")
    print(out, 3)
    flush(out)
    write(out, "trailing")
    return 0
```

```selka
# doc: expect ok 2
record Sink:
    stream: Stream
    label: str


func main(out: Stream) -> int:
    mut sink = Sink(stream=out, label="ok")
    const held = sink.stream
    print(held, sink.label, 2)
    return 0
```

## debug

`debug(values...)` writes to standard error without a capability. It renders like
`print` and returns unit. A debug build, `selka run` (with `--release`
too), `build --run` and `selka test` write it. A `selka build --release`
executable writes nothing and formats nothing, but it still evaluates every
argument, in order, as every other build does: a call in the arguments runs, a
`mut` argument is written, and a bad index traps. A program therefore means the
same in every build mode, and `debug` only adds output. A generic function may
call it too, although `print` is not supported in a generic body: each instance
renders its own argument types, and one that cannot be rendered, such as a
capability, is refused where the instance is checked.

```selka
# doc: check
func trace() -> int:
    debug("pure function")
    return 0


func traced[T: copy](value: T) -> T:
    debug("traced", value, sep=": ")
    return copy(value)
```

## What `selka run` prints and returns

`selka run` streams program output to standard output as it happens and does
**not** print the entry point's `int` result. Pass `--print-result` when you want
the result line written after the program's own output:

```text
$ selka run hello.selka
hello
$ selka run hello.selka --print-result
hello
0
```

The entry's `int` result is the **process exit status**, the way a Python or Go
program returns an exit code, truncated to the low 8 bits (`status = value &
0xFF`). This holds whether or not `--print-result` is passed, so printing the
value and exiting with it are independent:

```text
$ selka run hello.selka; echo "exit $?"
hello
exit 0
```

A runtime trap outranks the return and exits 1, because the program never
reached its `return`. `run-project` and a native executable from `selka build`
follow the same rule. An entry point may also return `Result[int, E]`:
`Ok(code)` carries the same status rule, while `Err(message)` writes an
`error: message` line to standard error, followed by the error's
[return trace](results-and-options.md#error-return-traces), and exits 1 (an `int`
error is the status instead). Exit codes are truncated to the low eight bits, so
`Ok(300)` exits 44. `--print-result` still prints the carried integer status,
independent of the diagnostic on stderr.

## Runtime diagnostics

A native trap keeps its original code, primary location, call stack and omitted
frame count. Where the failing operation already evaluated the values, the trap
also carries a bounded versioned detail: bounds failures report the original
index (negative values preserved) and the receiver length; integer division and
checked overflow report the evaluated operands and width where available, in the
operation's own signedness: a `u64` overflow reads `left 18446744073709551614`,
not `left -2`, and its record carries `"unsigned":true`. A trap is sticky: the
first trap's detail is retained even if later operations would also fail.

`selka run` renders that detail in text and, with `--diagnostics json`, under
`trap_detail` in the structured diagnostic. Both come from the same captured
values, so text does not reparse its own output and no receiver, index or
expression is reevaluated for a diagnostic. Detail-free traps (step and memory
budgets, capability and host failures) omit the field. Guests are separate
native processes, so children emit exactly one newline-terminated record
`\x1eSELKA-TRAP ` followed by a bounded JSON object on standard error; a host
that sees no record behaves exactly as before, and ordinary standard output,
diagnostics and exit statuses are unchanged.

```text
example.selka:2:12: error[R_LIST_BOUNDS]: native execution failed (index 14, length 1)
```

## Arguments

A `main(args: list[str], ...)` entry point receives guest arguments as input
data, never authority. `selka run` and `build --run` reserve their own compiler
and runtime options before `--` and pass every value after it in order:

```console
$ selka run report.selka -- --format=json "two words" ""
```

The list never contains a synthetic program name. An installed executable
hands `main` every OS argument after `argv[0]` unchanged — `--` and
flag-looking values such as `--restrict` included — because it reads its own
runtime options from the `SELKA_OPTIONS` environment variable instead (see
[the native backend](#the-native-backend)). Every argument is validated as
Unicode before guest execution, and invalid platform bytes fail with a stable
host-boundary diagnostic on stderr.

```selka
# doc: expect count 0
func main(args: str[], out: Stream) -> int:
    print(out, "count", len(args))
    return 0
```

## Standard input

An entry point that reads its standard input declares a parameter of type `Input`; the type selects the stream, so the
name is free (the guides write `stdin: Input`). It is granted like `Stream`: `selka run`, installed executables and a
test all hand it over, and `--restrict` cannot take it away. A `main` may declare at most one. Every read blocks until it has an answer,
and a read the operating system refuses (a closed descriptor, an I/O error) traps `R_INPUT`, the way a failed write to
standard output traps `R_OUTPUT`; so does a negative size.

| Method | Answers |
| --- | --- |
| `stdin.read(max: int) -> bytes` | up to `max` octets after at most one wait, and `b""` at the end of the input |
| `stdin.read_exact(n: int) -> bytes?` | exactly `n` octets, waiting for more as needed, or `None` when the input ends first |
| `stdin.read_line() -> bytes?` | through the next `\n`, or the final unterminated line, or `None` at the end |
| `stdin.read_into(mut buffer: byte_buffer, max: int) -> int` | appends what one `read(max)` answers to the buffer and counts it, 0 at the end |

`read_exact` consumes what it read even when it answers `None`: a truncated frame leaves nothing behind. A line keeps its
newline (and a carriage return before it); the caller strips what it does not want. `read_into` needs the buffer
bound to a name and marked `mut` at the call, like any call that writes a place.

A test reaches its input two ways. A test function that declares an `Input` parameter is handed an empty one, and
`streams.input_from(data)` builds an in-memory input over `bytes` that reads them once, in order, then ends:

```selka
# doc: expect b'GET /' [b'one\n', b'two']
import streams

func lines(stdin: Input) -> bytes[]:
    mut found: bytes[] = []
    while True:
        match stdin.read_line():
            case Some(line):
                append(mut found, own line)
            case None:
                return found

func main(out: Stream) -> int:
    const request = streams.input_from(b"GET /ok")
    print(out, request.read(5), lines(streams.input_from(b"one\ntwo")))
    return 0
```

The same helpers run on the real standard input, because they take the `Input` they are handed:

```selka
# doc: check
func count_lines(stdin: Input) -> int:
    mut count = 0
    while True:
        match stdin.read_line():
            case Some(_):
                count += 1
            case None:
                return count

func main(stdin: Input, out: Stream) -> int:
    print(out, count_lines(stdin))
    return 0
```

A program that sits in a shell pipeline reads with `main(stdin: Input, out: Stream)` and writes with `write(out, data)`.
Output is buffered, so a program that answers a peer that waits for the answer calls `flush(out)` after each reply;
without it the peer sees nothing until the program next waits (it reads its next request, for one), the buffer fills or
the program ends. The component worker of the self-hosting
plan is such a program (`selfhost/worker/echo.selka`, specified in the design record
`docs/tooling/component-protocol.md`, "Resident worker v1").

## Capabilities

The entry point declares the authority it needs by parameter type. `Filesystem`,
`Network`, `Clock`, `Entropy` and `Environment` are Python spellings of the
existing `filesystem_cap`, `network_cap`, `clock_cap`, `random_cap` and
`environment_cap` types, and name exactly the same checked types. `Process` is the
authority to start programs ([below](#processes)), and `Stop` lets the program hear that it is being stopped
([hearing a stop](#hearing-a-stop)). They resolve
only when no declared or imported type claims the name, so a module with its own
`record Clock` still gets its own type.

`selka run` and `run-project` grant every capability by default: the filesystem
with no directory restriction, the clock, entropy, the whole process
environment and the right to start programs. Relative paths resolve against the process working directory and
absolute paths name themselves, exactly as they would for any other program.

`--restrict` switches the command to deny-by-default. Only then do these flags
narrow anything:

| Flag | Grant under `--restrict` |
| --- | --- |
| `--allow-read=DIR` | read the directory tree at `DIR` (repeatable, up to eight) |
| `--allow-write=DIR` | read **and** write that tree, including create, truncate, `mkdir` and `remove` |
| `--allow-clock` | wall-clock time in Unix-epoch nanoseconds (`time.now`); a `Clock` without it still starts, reads `time.monotonic` and sleeps |
| `--allow-random[=SEED]` | a pseudorandom stream, reproducible when `SEED` is given |
| `--allow-env[=NAME,...]` | the process environment, restricted to the named variables |
| `--allow-process` | start programs and read their output (the `Process` capability) |
| `--allow-endpoint=IP:PORT` | connect to that one endpoint (repeatable, up to eight), as `network.connect` and a `Poller`'s `dial` do |
| `--allow-listen=IP:PORT` | listen on that one endpoint, as `network.listen` and `network.open_poller` do (repeatable, up to eight) |
| `--allow-all` | clock, entropy, every environment name, starting programs, every network endpoint and listener, and read/write on the working directory |

Without `--restrict` these flags are accepted and narrow nothing, so a command
line written for an older build keeps working. The one exception is
`--allow-random=SEED`, which pins the entropy seed in either mode because it
selects a stream rather than withholding one; an unseeded stream is seeded from
the wall clock.

### Network grants

The two network grants are separate: a connect grant does not let the program listen, and a listen grant does not let it
connect. Each names one IPv4 literal and a port, and the program reaches it through `net.host("IP:PORT")` with the same
literal or through an operation given the same text at run time, `network.connect_to`, `listen_at`, `open_poller_at` or
`dial_to` (the match is verbatim, see [the network host](effects.md#network-host) and [addresses given at run
time](standard-library.md#addresses-given-at-run-time)). What a grant does not accept:

- A pattern such as `--allow-endpoint=127.0.0.1:*` or `--allow-listen=127.0.0.1:*` stops the launch with exit 2 (a built
  program names it "not a usable capability grant"); so does a host name, an IPv6 address and, for `--allow-endpoint`, port 0,
  because dialling port 0 reaches nothing.
- `--allow-listen=127.0.0.1:0` grants only the address `127.0.0.1:0` (`net.host("127.0.0.1:0")`, or
  `network.open_poller_at(net, "127.0.0.1:0")`), which binds a port the kernel chooses and a `Poller` reports with
  `network.port`. It does not permit `127.0.0.1:8080`, and a `:8080` grant does not permit port 0.
- A port written with a sign, a space or anything after its digits is malformed, in a grant (exit 2) and in an address
  alike: `127.0.0.1:80 ` is not read as port 80.
- `*` in place of the address (`--allow-endpoint=*`, `--allow-listen=*`) grants every endpoint or every listener, in
  `selka run` and in a built program's `SELKA_OPTIONS` alike (a pattern around it, such as `127.0.0.1:*` or `*:80`, is
  refused as above). Each `*` counts toward the eight. `--allow-all` grants both everywhere, and the directories and the
  clock too.

A program that only connects out and holds many connections in a `Poller` opens it with `network.open_client_poller(net)`, which
listens on nothing and so needs no `--allow-listen`: the connect grants are all it asks for, each dial against the endpoint it
names, and a launch with no `--allow-endpoint` at all refuses the open with 1. It does not widen the grants: a dial to an address
no `--allow-endpoint` names is `OUTCOME_DENIED` with 2, as a `connect_to` to it is.

```selka
# doc: allow-endpoint 127.0.0.1:1
# doc: expect True True 2
import network


func main(net: Network, out: Stream) -> int:
    match network.open_client_poller(net):
        case ok(poller):
            mut live = own poller
            mut granted = network.new_outcome()
            mut other = network.new_outcome()
            network.dial_to(mut live, net, "127.0.0.1:1", mut granted)
            network.dial_to(mut live, net, "127.0.0.1:2", mut other)
            _ = own live
            print(out, granted.code != network.OUTCOME_DENIED, other.code == network.OUTCOME_DENIED, other.value)
            return 0
        case err(code):
            return 100 + code
```

A program that asks for an endpoint outside the grants gets `Connected.err` or `Polling.err` code 2 (`network.describe`:
"denied: outside the granted endpoints"); one that asks for a kind of network use with no grant of that kind at all gets code 1
("no network authority is available"). An entry point that declares a `Network` and is given neither grant does not start.

```selka
# doc: allow-listen 127.0.0.1:0
# doc: expect 12
import network

# 1 when the poller listens, else the refusal's code.
func bind_any(net: Network) -> int:
    with net.host("127.0.0.1:0") as scoped:
        match network.open_poller(scoped):
            case ok(poller):
                mut polled = own poller
                mut outcome = network.new_outcome()
                polled = network.port(own polled, network.LISTENER, mut outcome)
                _ = own polled
                if outcome.value > 0:
                    return 1
                return 0
            case err(code):
                return code


func bind_fixed(net: Network) -> int:
    with net.host("127.0.0.1:8080") as scoped:
        match network.open_poller(scoped):
            case ok(poller):
                _ = own poller
                return 1
            case err(code):
                return code


func main(net: Network) -> int:
    return bind_any(net) * 10 + bind_fixed(net)
```

The document gate runs that example under `--restrict --allow-listen=127.0.0.1:0`: the port the kernel chooses is granted
(the first digit, 1) and `127.0.0.1:8080` is not (the second, code 2). The next one runs under `--allow-endpoint=127.0.0.1:1`:
the granted endpoint is tried, and nothing listens there (code 3, `failed`), while the neighbouring one is refused (code 2).

```selka
# doc: allow-endpoint 127.0.0.1:1
# doc: expect 32
import network

func dial_granted(net: Network) -> int:
    with net.host("127.0.0.1:1") as scoped:
        match network.connect(scoped):
            case ok(conn):
                _ = network.close(own conn)
                return 1
            case err(code):
                return code


func dial_other(net: Network) -> int:
    with net.host("127.0.0.1:2") as scoped:
        match network.connect(scoped):
            case ok(conn):
                _ = network.close(own conn)
                return 1
            case err(code):
                return code


func main(net: Network) -> int:
    return dial_granted(net) * 10 + dial_other(net)
```

The grants hold for an address the program has only at run time in the same way. Under `--restrict
--allow-listen=127.0.0.1:0` this example's first address is granted and its second is not:

```selka
# doc: allow-listen 127.0.0.1:0
# doc: expect 0 2
import network

# 0 when a poller listens on `address`, else the refusal's code.
func listen_code(net: Network, address: str) -> int:
    match network.open_poller_at(net, address):
        case ok(poller):
            _ = own poller
            return 0
        case err(code):
            return code


func main(net: Network, out: Stream) -> int:
    const host = "127.0.0.1"
    print(out, listen_code(net, host + ":" + str(0)), listen_code(net, host + ":" + str(8080)))
    return 0
```

Running a program whose `main` requests an ungranted capability fails before the
first guest instruction — and that can only happen under `--restrict`:

```text
$ selka run report.selka --restrict
selka: --restrict is active and this command line did not grant a capability the entry point requests; pass --allow-read=DIR or --allow-write=DIR, or drop --restrict to grant every capability; or, if the program can run without it, declare the parameter optional (`fs: Filesystem?`)
```

The last clause names the way to keep `--restrict` and still start: a `main` that can do without the capability writes
the parameter `T?` (`fs: Filesystem?`, `net: Network?`, `rng: Entropy?`, `env: Environment?`, `proc: Process?`,
`host: Host?`), as [the next section](#capabilities-a-program-may-go-without) shows, and the run starts with `None` there.

A `Clock` is the exception: it needs no grant to start, because its monotonic reading and `time.sleep` reveal no
wall time. Its wall-clock read does: under `--restrict` without `--allow-clock`, `time.now(clock)` fails with "the wall
clock is not granted: pass `--allow-clock`" (a logger given that clock writes its lines without a time).

### Capabilities a program may go without

An entry parameter of a capability that a command line grants may be written `T?` (`fs: Filesystem?`, `net: Network?`,
`clock: Clock?`, `rng: Entropy?`, `env: Environment?`, `proc: Process?`, `host: Host?`). Such a program always starts:
the parameter is `Some` when the command line grants anything of that capability and `None` when `--restrict` grants
nothing of it, and the program decides what to do without it. A `Filesystem?` counts any `--allow-read` or
`--allow-write`, a `Network?` any `--allow-endpoint` or `--allow-listen`, and a `Clock?` only `--allow-clock`. Without
`--restrict` every one is `Some`. A `Some` holds exactly what the plain `T` would: the optional form grants nothing more.
`Stream`, `Input` and `Stop` need no grant, so `Stream?` and the others are `E_MAIN`.

```selka
# doc: expect files: False
func main(fs: Filesystem?, out: Stream) -> int:
    match fs:
        case Some(files):
            print(out, "files:", files.exists("notes.txt"))
        case None:
            print(out, "no files: reading standard input only")
    return 0
```

Run with the default grants it prints `files: False`; with `--restrict` and no `--allow-read` or `--allow-write` it
prints the `None` line.

The language itself is unchanged: helpers receive authority as ordinary
arguments, nothing is ambient, and no cast or copy mints a capability. What the
default changes is only how generous the command line is.

**Neither mode is a sandbox.** The providers run inside the compiler process, the
host filesystem tree is trusted, directory handles keep their authority across
renames, and directory scoping does not distinguish hard links to the same inode.
`--allow-process` is the plainest case: a started program runs with the caller's own
authority, so no directory grant contains it, and the flag takes no list of programs
because a list would look like containment without being it.
A compromised compiler, or a host that edits the adapters, is outside this
boundary. `--restrict` is a way to say what a program is allowed to reach, not a
containment mechanism.

### Records that hold capabilities

A capability is a shareable handle, a value like `Stream`: it is copied, stored in any record, list, dictionary, option
or union payload, passed and returned, with no `own`. Copies share their provider. A task is the one place it cannot go:
a task takes values, not capabilities ([concurrency](concurrency.md#tasks-take-values)). Two copies of a
memory filesystem see one tree, as copies of the real filesystem do, and two copies of a seeded `Entropy` draw from one
stream, which stays deterministic.

```selka
# doc: expect 2 True 2
import filesystem
import random

record Services:
    fs: Filesystem
    entropy: Entropy
    runs: int

func start(fs: Filesystem, entropy: Entropy) -> Services:
    return Services(fs=fs, entropy=entropy, runs=0)

func record_run(mut services: Services):
    services.runs = services.runs + 1
    _ = services.fs.write_text("runs", "logged")

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    mut services = start(fs, random.seeded_entropy(7))
    record_run(mut services)
    record_run(mut services)
    const every = [services, start(fs, random.seeded_entropy(8))]
    print(out, services.runs, fs.exists("runs"), len(every))
    return 0
```

Restriction is unchanged. A copy keeps the grants of the handle it copies, and a narrowing (`fs.dir(path)`,
`fs.read_only()`, `net.host(endpoint)`, `env.only(...)`) answers a new handle with the narrower scope, which a `with`
scope may bind or a plain `const` may hold. Every copy of a narrowed handle stays as narrow, and `--restrict` and the
`--allow-*` grants apply to every copy as they apply to the original. A `Filesystem` narrowed by `fs.dir(path)` follows
no symbolic link in any run, with or without `--restrict` (the unnarrowed handle of a run without `--restrict` still
follows them, as an ordinary process does): a link on the way to a path, at its end or as the narrowing's own prefix is
refused as a granted directory refuses it. That holds for a grant named through a link too: under `--allow-read=LINK`,
every call on `fs.dir("LINK")` or `fs.dir("LINK/sub")` is refused with the reason a run without `--restrict` gives,
while a plain read such as `fs.read_text("LINK/a.txt")` follows the link. A path on a handle narrowed by `fs.dir` or `filesystem.dir_at` stays relative
to its folder in every run: `..`, `.`, an empty part and an absolute path are refused there, as before the rule of
[How a path is read](#how-a-path-is-read), which covers the unnarrowed handle a run hands to `main`. A backslash is an
ordinary byte of a name, as it is to Linux: `dest.write_text("a\\b", "x")` writes the file `a\b` in the folder, as
`fs.write_text("dest/a\\b", "x")` does, and `..\x` or `a\..\b` is one name in the folder, never a step out of it.
`fs.read_only()` narrows what a handle may do, not which paths it may name: it refuses every write and reads a path as
the handle it narrows does (the table in that section lists what each kind of handle refuses).

```selka
# doc: expect True False
import filesystem

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("data")
    _ = fs.write_text("top.txt", "outside")
    const data = fs.dir("data")
    const kept = [data]
    _ = kept[0].write_text("inside.txt", "inside")
    print(out, fs.exists("data/inside.txt"), kept[0].exists("top.txt"))
    return 0
```

#### A folder named at run time: `filesystem.dir_at`

`fs.dir` takes only a literal. A folder the program learns at run time, from its command line or its configuration, is
narrowed to with `filesystem.dir_at(fs, path) -> Filesystem fails str`, as `network.connect_to` takes the address a
`net.host` literal cannot. The handle it returns is a `fs.dir` handle, and narrowing only ever removes access:

1. **What may be named.** Any folder `fs` itself reaches, with `path` read as `fs` reads a path: on the `Filesystem` a
   run hands to `main`, by [How a path is read](#how-a-path-is-read) (absolute, or against the working directory, with
   `.`, `..`, doubled and trailing slashes; under `--restrict` inside a granted directory of either kind); on a narrowed
   handle by that handle's own rule (relative to its folder, without `..`, `.`, an empty part or a leading `/`); on
   `filesystem.memory()` and a test's filesystem as they read a path (their root is the working directory). The folder
   must exist and be a directory. An empty path is refused, so a missing command-line argument is not taken for the
   working directory, which `.` names.
2. **No symbolic link.** No component the path names may be a symbolic link: not the folder, not a folder on the way to
   it, and not a folder that a `..` steps back out of, in every run, restricted or not, as `fs.dir` refuses one. That
   holds for a grant named through a link too: under `--allow-read=LINK`, `dir_at(fs, "LINK")` and `dir_at(fs, "LINK/sub")`
   are refused with the reasons a plain run gives, while a plain read such as `fs.read_text("LINK/a.txt")` follows it.
3. **What it returns** is what `fs.dir` gives: a path on it is relative to the folder, and `..`, `.`, an empty part, an
   absolute path and a symbolic link are refused there in every run (a backslash is a byte of a name); it reads only when `fs`
   reads only, and under `--restrict` it writes only inside a write grant. Like a `fs.dir` handle it keeps the folder's name, not the folder:
   every call walks that name again and follows no link, so a link made inside the folder later, or the folder replaced
   by a link, is refused at that call, and a folder renamed away leaves the handle naming whatever is put at its name,
   which `fs` reached too. `dir_at` on a narrowed handle goes further in, and nothing on it names the folder's parent.
   `canonical_path` and `filesystem.cwd` answer below the folder, `""` for the folder itself.
4. **Failures** read `dir_at 'PATH': REASON`: the refusal or failure a `filesystem.stat` of the path gives (outside the
   granted directories, the narrowed handle's rule, nothing there), `is not a directory`, or `is a symbolic link the
   sandbox does not follow`.
5. **Naming the folder itself in a call on the handle.** Inside the handle the folder is the empty path `""`, not `"."`:
   `handle.exists("")`, `filesystem.stat(handle, "")` and `filesystem.list_entries(handle, "")` answer for the folder, as
   the same calls with `""` answer for the working directory on the `Filesystem` that `main` gets. `"."` is refused
   there with the rest of the narrowed rule, `denied: a Filesystem narrowed by fs.dir takes a path inside its folder,
   without '..', '.', an empty part or a leading '/'`, and so is every path that has a `.` or an empty part or ends in
   a slash: `"./"`, `"./notes.txt"`, `"sub/"`, `"sub/."`. Write `notes.txt` and `sub/notes.txt`, with no `./` before the
   first name and no `/` after the last. `exists` has no failure to report, so it answers `False` for a refused path
   (`handle.exists(".")` is `False` though the folder is there). A call that needs a name inside the folder
   (`read_text`, `open`, `write_text`, `mkdir`, `remove`) refuses `""` with the same text. `.` is accepted in one place,
   `filesystem.realpath(handle, ".")` (and so `filesystem.cwd(handle)`), which answers `""`. The folder's own parent has
   no name here (`..` is refused), and `filesystem.dir_at(handle, "")` is refused as item 1 says: narrow further in by
   the sub-folder's name, `filesystem.dir_at(handle, "sub")`. The `.` of `filesystem.dir_at(fs, ".")` in the restricted
   example below is the argument to `fs`, the handle `main` got, which reads it as a working directory; it is not a
   path on the narrowed handle. All of this is the same on a real folder, under `--restrict` or not, and on
   `filesystem.memory()`.

```selka
# doc: expect True False
# doc: expect dir_at 'secret.txt': is not a directory
import filesystem

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("runs")
    _ = fs.mkdir("runs/today")
    _ = fs.write_text("secret.txt", "outside")
    const chosen = "runs/today"
    match filesystem.dir_at(fs, chosen):
        case Ok(today):
            _ = today.write_text("log.txt", "inside")
            print(out, fs.exists("runs/today/log.txt"), today.exists("../../secret.txt"))
        case Err(message):
            print(out, message)
    match filesystem.dir_at(fs, "secret.txt"):
        case Ok(_):
            print(out, "narrowed")
        case Err(message):
            print(out, message)
    return 0
```

A restricted run narrows the same way; this example starts in its granted folder, `notes`, and narrows to it with `.`:

```selka
# doc: allow-read notes
# doc: expect Ok('hello from a granted directory\n') False
import filesystem

func main(fs: Filesystem, out: Stream) -> int:
    match filesystem.dir_at(fs, "."):
        case Ok(here):
            print(out, here.read_text("greeting.txt"), here.exists("../notes/greeting.txt"))
        case Err(message):
            print(out, message)
    return 0
```

Inside the handle, `""` names the folder and `"."` and `"./log.txt"` name nothing (item 5):

```selka
# doc: expect True 1 False False True
import filesystem

func entries(handle: Filesystem) -> int:
    match filesystem.list_entries(handle, ""):
        case Ok(found):
            return len(found)
        case Err(_):
            return -1

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("runs")
    _ = fs.mkdir("runs/today")
    _ = fs.write_text("runs/today/log.txt", "inside")
    match filesystem.dir_at(fs, "runs/today"):
        case Ok(today):
            print(out, today.exists(""), entries(today), today.exists("."), today.exists("./log.txt"), today.exists("log.txt"))
        case Err(message):
            print(out, message)
    return 0
```

Narrowing happens once, and a read through the handle costs what it costs through `fs.dir`: the folder's name is joined
to each path as text, as for the literal form. Nothing the checker reports depends on the literal: no report or manifest
lists the folders a program narrows to, so a folder chosen at run time changes no output of `selka check`.

The provider state behind a handle lives in the runtime until the process ends, or until the `selka test` trial that
made it ends; nothing in the program destroys it. A program that makes memory filesystems or seeded entropies in a loop
therefore keeps each one until it exits, about 0.6 KiB of runtime memory per filesystem and less per entropy, plus the
entries written to it. A test trial starts with none: its capabilities are fresh stand-ins.

Code written before capabilities became handles passes them with `own`: `start(own fs, own entropy)`,
`Services(fs=own fs)`, `func start(own fs: Filesystem)`. Those markers still check, and each one is the warning
`W_CAPABILITY_OWN`, whose fix `selka fix` applies to remove it. An `own` marker on a value that still owns storage, a
record that also holds a list, is unchanged.

A `mut` capability parameter (`func read(mut fs: Filesystem)`) is legal, and it means what `mut` means on an integer: a
rebinding of `fs` in the body reaches the caller's binding. A function that never assigns the parameter and never passes
it on as `mut` hands nothing back, so `mut` there only makes every caller write `mut fs`; that is the warning
`W_CAPABILITY_MUT`. `selka fix` deletes the `mut` from the declaration, deletes the `mut` the call sites then carry
(`E_MUTATION_MARKER`), and goes on to the callers that passed the parameter along, until the chain is settled. A function
that is used as a value keeps its `mut`, because its function type spells it too.

## Hearing a stop

A program hears that it is being stopped by declaring a `Stop` on `main`. SIGTERM (`systemctl stop`, `kill`,
`process.stop`) and SIGINT (Ctrl-C) then turn `process.stop_requested(stop)` true instead of ending the program, and a
loop on it ends, says goodbye and returns:

```selka
# doc: check
import network
import process

func main(net: Network, out: Stream, err: Stream, stop: Stop) -> int:
    match network.open_poller_at(net, "127.0.0.1:0"):
        case ok(poller):
            mut polled = own poller
            mut ready = network.new_ready()
            print(out, "serving")
            while not process.stop_requested(stop):
                polled = network.wait(own polled, 1000, mut ready)
            print(err, "stopped on request")
            _ = own polled
            return 0
        case err(code):
            return code
```

- **Who gets it.** Only a program whose `main` declares a `Stop` (at most one) has the handler: it is installed before
  `main`'s first statement, with one wake-up descriptor. A program that declares none has no handler and no descriptor,
  and SIGTERM ends it by the system's default, status 143 (130 for SIGINT), as always. A program that declares one has
  taken on ending itself: if it never reads `stop_requested` (`_stop: Stop`), its first SIGTERM only ends one wait early
  and the second ends it.
- **No grant.** Like `Stream` and `Input` it is always handed over, and `--restrict` cannot take it away: hearing a stop
  reaches nothing outside the program, and whoever can send the signal can already end the program. Declaring `Stop`
  only lets it end cleanly.
- **SIGHUP is not a stop.** A program that declares `Stop` still dies of SIGHUP. A signal that was ignored when the
  program started (a shell's `&` ignores SIGINT) stays ignored.
- **The second signal.** After the first stop, the next SIGTERM or SIGINT ends the program by the default action, so an
  operator who presses Ctrl-C twice gets it gone, and a goodbye that hangs cannot hold the machine (a service manager
  sends SIGKILL after its own timeout anyway). The one exception: the same signal from the same sender within half a
  second of the first is the same stop, however many times it arrives. `timeout` and other senders signal a process and
  then its whole group back to back, and `selka run` passes its copy on, so one stop can arrive two or three times and
  must not end the program before its goodbye. What that costs: a script's `kill PID; kill PID` with no pause between
  does not force the program; a different sender, a different signal, Ctrl-C twice, or the same signal half a second
  later does.
- **A `Stop` is a handle**, like `Stream`: copy it, keep it in a record, a list or an option, pass and return it; every
  copy reads one flag. A task cannot take one (`E_TASK_CAPABILITY`): ask `stop_requested` before each group or map and
  start no more work once it is true, or pass the task the answer as a `bool`.

What each wait does when a stop arrives. A stop the program has not yet read with `stop_requested` is pending; while it
is, the next `network.wait` of each poller and the next `time.sleep` on the real clock end early, once each, so a loop
on `stop_requested` hears it at once wherever it waits. Every other wait resumes, and the program sees the stop when it
returns. Once the program has read the stop, every wait lasts as long as it asks, so a goodbye can wait for its clients.

| Where the program waits | When a stop arrives |
| --- | --- |
| `network.wait` | returns at once with what is ready then, usually nothing, as a timeout returns; ask `stop_requested` to tell the two apart |
| `time.sleep` on the real clock | returns early (a simulated clock never waits) |
| a blocking read or accept on a connection or listener | resumes; with `read_ms` the limit counts again from the interruption |
| `connect`, `connect_within` | resumes; `connect_ms` still holds |
| standard input | resumes |
| `process.run`, `wait`, `wait_within` | resume; `wait_within`'s limit still holds |
| a blocking lease (`durable`) | resumes |
| a `parallel` join, a task | is not interrupted |

A test is handed a stand-in: a test function that declares a `Stop` parameter gets one that no signal reaches, not yet
requested; `process.simulated_stop()` makes another, and `process.request_stop(stop)` delivers the notice, so a test
checks the goodbye without a signal. `network.memory()` has no poller, so a test drives a serve loop's turn function and
its goodbye function on their own, with the stand-in deciding when the loop ends:

```selka
# doc: expect goodbye after 3 turns
import process

func serve(stop: Stop) -> int:
    mut turns = 0
    while not process.stop_requested(stop):
        turns += 1
        if turns == 3:
            process.request_stop(stop)
    return turns

func main(out: Stream) -> int:
    const stop = process.simulated_stop()
    print(out, "goodbye after " + str(serve(stop)) + " turns")
    return 0
```

On the real `Stop`, `request_stop` is the program asking itself to stop (a "quit" command takes the path SIGTERM takes):
the flag is set and the waits wake, but it is not a signal, so the next SIGTERM is the program's first.

## Register access

A `Registers` is the authority to read and write hardware registers (`import registers`): `registers.read32(reg,
address)` and `registers.write32(reg, address, value)`, and the 8- and 16-bit forms. Like the other capabilities it is a
shareable handle that needs no `own`, a record or a list may hold it, a `parallel` task cannot take one
(`E_TASK_CAPABILITY`), and `print`, `str` and a format hole refuse it. Code that was not handed a `Registers` cannot
reach a register.

On a device target (`selka build --target thumbv6m-none`, see [the native build guide](tooling/native-build.md)) `main`
is handed one: `func main(reg: Registers) -> int`, and each read or write is one volatile load or store of its width at
the address, in the program's order. The check accepts that `main` everywhere; a build for Linux refuses it with
`E_TARGET_CAPABILITY`, and a device build refuses the functions only a simulated bank has (`simulated`, `poke32`,
`script32`, `pin32` and the log readers) with `E_TARGET_SIMULATED_REGISTERS`, which names the function. The processor's
own instructions (wait for an event, send one, a barrier, interrupts held off) are [the `cpu` module](standard-library.md#cpu),
which takes the same capability and records each call on a simulated bank. A test makes a
simulated bank with `registers.simulated()` and checks what the code under test wrote:

```selka
# doc: expect 17 [64, 68]
import registers

# Start the timer at `base`: set the enable bit, then load the period.
func start_timer(reg: Registers, base: u32, period: u32):
    registers.write32(reg, base, bit_or(registers.read32(reg, base), 0x1))
    registers.write32(reg, base + 4, period)


func main(out: Stream) -> int:
    const reg = registers.simulated()
    registers.poke32(reg, 64, 0x10)
    start_timer(reg, 64, 1000)
    mut addresses: int[] = []
    for entry in registers.writes(reg):
        append(mut addresses, int(entry.address))
    print(out, registers.read32(reg, 64), addresses)
    return 0
```

A bank can also model hardware that changes under the code. `registers.script32(reg, address, values)` makes the next
reads of a word answer `values` in order, and then the stored word again: a running timer, or a status that turns ready.
`registers.pin32(reg, address, mask, value)` makes the bits of `mask` always read as `value`'s, whatever the code
writes there, as a read-only lock bit inside a control register does; the log still holds what the code wrote:

```selka
# doc: expect 3 3 Some(1)
import registers

# Start the PLL at `base` (bit 0) and wait for its lock bit (bit 31), counting the reads.
func start_pll(reg: Registers, base: u32) -> int:
    registers.write32(reg, base, 1)
    mut reads = 1
    while bit_and(registers.read32(reg, base), 0x80000000) == 0:
        reads += 1
    return reads


func main(out: Stream) -> int:
    const reg = registers.simulated()
    registers.script32(reg, 0x100, [0, 0, 0x80000000])
    registers.pin32(reg, 0x100, 0x2, 0x2)
    const reads = start_pll(reg, 0x100)
    print(out, reads, registers.read32(reg, 0x100), registers.last_write(reg, 0x100))
    return 0
```

A simulated bank holds 4,096 distinct words and logs 16,384 writes; past either it traps `R_REGISTER_BANK`. Its other
rules, and the log's readers, are in the [standard library guide](standard-library.md#registers).

A device with two cores runs a second loop with `registers.start_core1(reg, entry)`: `entry` is a top-level
`func(Registers) -> int` (a function value captures nothing), and core 1 runs it with its own `Registers`, its own stack
and its own heap while `main` goes on. The call answers `False` when the platform has one core (QEMU's) or core 1 was
started already. The two cores share no heap value: they talk through the hardware, the SIO FIFOs and spinlocks (the
`rp2040` package's `sio` module) or a memory window both reach through `Registers`. A build for the host refuses a
program that calls it with `E_TARGET_DEVICE_REGISTERS`, which names the function. What core 1's return, a trap on either
core and the end of `main` do is in [the native build guide](tooling/native-build.md#the-second-core-registersstart_core1).

## Environment

Environment access needs an explicit `Environment` entry parameter. On a
capability value, `env.get(name)` returns `Option[str]`: `Some(value)` for a
present name and `None` when the provider has no such name, decoded as UTF-8. The
name is any `str`, a literal or a computed one (`env.get(prefix + "HOME")`); a name
that is empty, holds a NUL or an `=`, or is longer than 255 octets can be no
variable's name, so it answers `None`. A name outside the active `--allow-env`
allow-list or the `env.only` scope is a denied authority, which traps rather than
answering `None`. `env.only("HOME", "PATH")` narrows an
`Environment` to the listed literal names (the scope of a narrowing stays a literal
list, so it can be read from the source), and `env.names()` returns every visible
name, sorted, as `list[str]` (a fixed `Environment` stand-in holds at most 64). `selka run` and installed executables grant the
process environment (including `SELKA_OPTIONS`) by default; under `--restrict`, `--allow-env[=NAME,...]`
selects the visible names. All launch paths now report an ungranted capability
with the same stderr line and exit 2.

```selka
# doc: check
func main(env: Environment) -> int:
    mut home = env.get("HOME")
    with env.only("HOME") as narrowed:
        _ = home
        _ = narrowed
        return len(env.names())
```

A program that reads many variables with one prefix computes the names:

```selka
# doc: check
func setting(env: Environment, key: str) -> str:
    match env.get("APP_" + key):
        case Some(value):
            return copy(value)
        case None:
            return ""

func main(env: Environment) -> int:
    return len(setting(env, "HOME")) + len(setting(env, "MODE"))
```

## Processes

A `main(proc: Process, ...)` entry point may start programs. `selka run` and installed executables grant it by default;
under `--restrict` it needs `--allow-process` (or `--allow-all`), and without it the program refuses to start with the
same line as any other withheld capability (`pass --allow-process`, exit 2).

The one builtin is `run_process(proc, request, limit) -> Result[bytes, str]`, whose request and answer are packed octets
(the [`binary`](standard-library.md#binary) format); the typed layer is the standard module
[`process`](standard-library.md#process), which a program uses instead. `process.run(proc, request)` runs a program to
completion and answers an `Output`: whether it exited (`exited`, with its status in `code`) or died to a signal (`code`
is the signal number), the octets it wrote to standard output and standard error, and whether either was cut at the
`limit`. There is no shell: a request is the program and its arguments as a list, the program is a path or a name
searched on `PATH`, and an empty working directory keeps the caller's. A request may carry octets for the child's
standard input and, as `Some([...])`, exactly the environment the child gets. A program that is not there is
`Error.NotFound(program)` and any other refusal to start it is `Error.Failed(message)`, so a caller can match them.

```selka
# doc: expect True 0 b'hello\n'
# doc: expect not found
import process

func main(proc: Process, out: Stream) -> int:
    match process.run(proc, process.command(["/bin/sh", "-c", "echo hello"])):
        case Ok(result):
            print(out, result.exited, result.code, result.stdout)
        case Err(_):
            print(out, "unexpected")
    match process.run(proc, process.command(["no-such-program-xyz"])):
        case Ok(_):
            print(out, "unexpected")
        case Err(error):
            match error:
                case NotFound(program=_):
                    print(out, "not found")
                case Failed(message=_):
                    print(out, "unexpected")
    return 0
```

Standard output and standard error are read while the input is written, so a child that fills its output before reading
its input does not stall; output beyond the limit is read and dropped (never left in the pipe), and the `truncated`
flag says so. A child that stops reading its input does not take the caller down with a broken pipe. The child starts
with an empty signal mask, the default `SIGPIPE` and only descriptors 0, 1 and 2 (the runtime's other descriptors are
close-on-exec, and any that is not is closed in the child). It gets the caller's environment unless the request gives
one, the caller's working directory unless the request names one, and the caller's other resource limits, with one
exception: its address-space limit (`RLIMIT_AS`, `ulimit -v`) is the one the Selka program itself started with, not the
memory ceiling `selka run` puts on the program (its `--max-memory`, 4 GiB by default, plus 256 MiB). The ceiling bounds
the Selka program; a browser or a compiler it starts reserves address space of its own. The call waits for the child
and has no timeout of its own; to bound a program, run it under `timeout(1)`, or start it and wait with a limit
([below](#starting-a-program-without-waiting)). Like the file builtins, `run_process` and so
`process.run` are refused inside a generic function body; write an ordinary function and call it from the generic one.

`process.executable_path(proc)` answers the absolute path of the running program (`/proc/self/exe`), for a program that
starts a copy of itself or reports where it is installed. It fails with the system's reason when the path cannot be read.

### Starting a program without waiting

`process.start(proc, request, stdout_path, stderr_path)` starts a program and returns at once with a `process.Child`,
while the program runs: a server a test talks to, a browser it drives. The program's standard input is `/dev/null`
(`request.input` must be empty), and its standard output and standard error go to the files named (each emptied when
the program starts; one path for both keeps their order, as `>LOG 2>&1` does) or to `/dev/null` for `None`, so nothing
the caller holds stays open in a program that outlives it. A path is relative to the caller's working directory and is
opened with the `Process` capability's authority, as the program could open it. Otherwise the program starts exactly as
`process.run` starts one, and a missing program fails `Error.NotFound` the same way.

```text
# doc: not-selka
start(proc, request, stdout_path: str?, stderr_path: str?) -> Child fails Error
pid(mut child) -> int                                     SIGHUP SIGINT SIGQUIT SIGKILL SIGUSR1 SIGUSR2 SIGTERM SIGCONT SIGSTOP
signal(proc, mut child, number: int) -> Unit fails Error  # 1 to 64; nothing is sent once a wait has seen the end
wait_within(proc, mut child, millis: int) -> Output? fails Error   # None: still running; 0 asks without waiting
wait(proc, own child) -> Output fails Error               # as long as it takes; ends the Child
stop(proc, own child, grace_millis: int) -> Output fails Error     # SIGTERM, the grace, then SIGKILL; ends the Child
```

The `Output` of a wait says how the program ended, as `process.run`'s does: `exited` with its status in `code`, or a
signal number in `code`; its output went to the files, so `stdout` and `stderr` are empty. A `Child` is a
[sealed](records-and-unions.md#sealed-records) [`@linear`](records-and-unions.md#linear-records) record: only `start`
makes one, and every one is ended exactly once on every path, by `wait` or by `stop`. A program cannot forget a child
(which would leave a zombie), copy one, keep one in a list or wait for it twice; a function that only reads a Child
takes it `mut`, and `child.pid` reads its number. `on fail: _ = process.stop(proc, own child, 2000)` after the start
ends it on every failure exit that follows. `wait_within` may be called as often as needed; once it has seen the end it
answers the same at once, and the Child still ends by `wait` or `stop`, which then answer that `Output` at once too. A
server under test is started with its log in a file, `process.start(proc, request, Some("server.log"),
Some("server.log"))`, which the test reads while the server runs.

Only a program this program started can be signalled or waited for, through its Child: the runtime keeps every started
program that no wait has reaped, sends a signal only to one of them, and reaps one only when a wait sees it end, so a
signal never reaches a process number the system has given to someone else. A Selka program that ends while a Child is
still live (a trap, `--timeout`, a signal from outside; ordinary code cannot reach its end without ending its Child)
takes its started programs with it: the system kills each one still running (`PR_SET_PDEATHSIG`). `--restrict` without
`--allow-process` refuses the program that asks for a `Process` before anything starts, as it does for `process.run`.

```selka
# doc: expect started True
# doc: expect still running None
# doc: expect ended by signal 15
# doc: expect exited True 3
import process

func main(proc: Process, out: Stream) -> int:
    mut server = process.start(proc, process.command(["/bin/sleep", "30"]), None, None) else Err(error):
        print(out, process.message(error))
        return 1
    print(out, "started", process.pid(mut server) > 0)
    match process.wait_within(proc, mut server, 0):
        case Ok(found):
            print(out, "still running", found)
        case Err(error):
            print(out, process.message(error))
    match process.stop(proc, own server, 5000):
        case Ok(found):
            print(out, "ended by signal", found.code)
        case Err(error):
            print(out, process.message(error))
    mut job = process.start(proc, process.command(["/bin/sh", "-c", "exit 3"]), None, None) else Err(error):
        print(out, process.message(error))
        return 1
    match process.wait(proc, own job):
        case Ok(found):
            print(out, "exited", found.exited, found.code)
        case Err(error):
            print(out, process.message(error))
    return 0
```

### Letting a started program write to the caller's streams

`process.start_to(proc, request, stdout, stderr)` is `start` with a `process.Destination` for each of the program's two output
streams instead of an optional path: `Discard` (`/dev/null`), `File(path)` (emptied when the program starts, as `start`'s path is)
or `Caller`, which lets the program write straight to this program's own standard output (as the `stdout` destination) or
standard error (as the `stderr` destination) while it runs. That is what a shell does by default, so a deploy gate's compiler
and `git` show their output live instead of after they end, and `process.run` keeps capturing both streams as before.

```text
# doc: not-selka
start_to(proc, request, stdout: Destination, stderr: Destination) -> Child fails Error
enum Destination: Discard | File(path: str) | Caller      # start(proc, request, a, b) is File(a) or Discard, File(b) or Discard
```

- **Order.** What the caller has printed so far, on both streams, is flushed before the program starts, so it comes first. What the
  caller prints while the program runs goes out as the caller's output always does (when its buffer fills, at `flush(out)` or
  at its end), so a line that must not wait behind the program's own is printed before the start or after the wait, or
  followed by `flush(out)`. Two `Caller` destinations show the program's lines in the order the program wrote them, as a
  terminal does; one file for both keeps their order in the file.
- **What `Caller` means.** The caller's descriptors 1 and 2, whatever `Stream` values the program holds, so it is the terminal, the
  pipe or the file `selka run` was started with. A program started with its standard output or standard error closed
  (`>&-`) gives the child whatever that descriptor then names; the runtime does not check it.
- **Authority.** A program started with `Caller` gets nothing its caller lacks: the caller can already write both streams, so
  `--restrict` changes nothing about the destinations, and starting a program still needs `--allow-process` as for `start`
  and `run`. Every other rule of `start` holds (no standard input, the same environment, directory and address space, the
  program is killed if the caller ends before its `Child` does).
- **In a test.** A test's `Process` is scripted, so nothing starts and there is nothing to let through: `start_to` answers
  from the rules exactly as `start` does and ignores the destinations (no file is written either).

```selka
# doc: expect building
# doc: expect child says hi
# doc: expect exited True 0
import process

func main(proc: Process, out: Stream) -> int:
    print(out, "building")
    mut build = process.start_to(proc, process.command(["/bin/sh", "-c", "echo child says hi"]), process.Destination.Caller, process.Destination.Discard) else Err(error):
        print(out, process.message(error))
        return 1
    match process.wait(proc, own build):
        case Ok(found):
            print(out, "exited", found.exited, found.code)
        case Err(error):
            print(out, process.message(error))
    return 0
```

### Running several programs at once: a group

A `process.Child` is linear, so no list, dictionary or second record field can hold one: several programs at once are
kept in a `process.Group` instead, one linear owner that holds as many started programs as the system lets the caller
start. `make -j` is the shape: start up to N, wait for whichever ends first, start the next.

```text
# doc: not-selka
group() -> Group                                                  # empty; needs no capability
group_start(proc, mut g, request, stdout_path: str?, stderr_path: str?) -> int fails Error     # the key of the new program
group_start_to(proc, mut g, request, stdout: Destination, stderr: Destination) -> int fails Error
group_wait_any_within(proc, mut g, millis: int) -> Finished? fails Error   # None: none ended in time; 0 asks without waiting
group_wait_any(proc, mut g) -> Finished fails Error                        # as long as it takes
group_signal(proc, mut g, key: int, number: int) -> Unit fails Error       # the program and what it started
group_signal_all(proc, mut g, number: int) -> Unit fails Error
group_stop(proc, mut g, grace_millis: int) -> Finished[] fails Error       # SIGTERM, the grace, SIGKILL; the group stays open
group_size(mut g) -> int                                                   # started and not yet answered by a wait
group_pid(mut g, key: int) -> int?                                         # the system's number of the program
group_close(proc, own g, grace_millis: int) -> Finished[] fails Error      # stops what is left and ends the group
record Finished: key: int, output: Output                                  # `output` as a Child's wait answers: no output
```

- **Keys.** `group_start` answers a key: 0 for the first program of the group, then 1, 2 and so on, never one twice, so a
  caller keeps its own table from key to job. The request, the output paths or `Destination`s, the environment, the
  directory and the `--allow-process` it needs under `--restrict` are exactly `start`'s and `start_to`'s; no new capability.
  A start that fails (`NotFound` for a missing program) leaves the group as it was.
- **Waiting.** `group_wait_any` answers the key and how the first program to end ended (`exited` with its status in `code`,
  or the signal's number), and the program leaves the group. When several have ended, the one started first answers first.
  A program that ends while nobody waits is not lost: it stays a zombie, held by the runtime, until a wait answers it. The
  wait sleeps in the kernel until a program ends (one `poll` over a `pidfd` of every program of the group, so it takes no CPU
  and answers as soon as one ends); only a kernel without `pidfd_open` (before Linux 5.3) makes it look every 10 ms. It
  is not woken by a `Stop`, so a loop that wants to hear one waits with `group_wait_any_within` and a short limit
  (50 milliseconds) and reads `process.stop_requested(stop)` between waits. Waiting on an empty group fails, since nothing
  could end.
- **Process groups.** Each program of a group is the leader of a process group of its own, so `group_signal`, `group_stop`
  and `group_close` reach what the program started too (`sh -c 'sleep 60; make'` leaves `sleep` as a grandchild, and a
  signal to the shell alone would not reach it). A program that moves itself to another process group or session
  (`setsid` forks when it leads a group, and the program it starts is no longer in the group) leaves it. Because the
  program is not in the terminal's foreground process group it does not hear the terminal's Ctrl-C: a caller that
  declares a `Stop` hears it and stops the group. Once a wait has answered a program, the group no longer holds it, and
  what it left running is out of the group's reach.
- **Stopping and closing.** `group_stop` sends `SIGTERM` to the process group of every program, gives them `grace_millis`
  milliseconds, then sends `SIGKILL` to every process group (also the groups of programs that ended in the grace, so a
  child that ignored `SIGTERM` does not stay behind) and waits for each, answering how each ended in the order they
  started. `group_close` does that and ends the group: **a group closed with programs still running stops them**, as a
  `Child` is stopped by `stop`, and the programs end reaped, no zombie left. Like a `Child`, a `Group` is `@sealed` and
  `@linear`: it cannot be copied, forgotten or kept in a list, and every path ends it, so `on fail: _ =
  process.group_close(proc, own jobs, 2000)` after `group()` closes it on every failure exit that follows. A program
  that ends without closing its group (a trap, `--timeout`, a signal from outside) takes the programs it started with it
  as a `Child`'s does (`PR_SET_PDEATHSIG`), but not what they started in turn.
- **In a test.** A scripted Process starts nothing, so `group_start` logs the request and answers from the rules as
  `start` does, and the program has already ended: waits answer the programs in the order they started, a signal does
  nothing and `group_stop` answers each program's rule, with the same keys.

```selka
# doc: expect started 2
# doc: expect first True True 3
# doc: expect still running 1
# doc: expect stopped True False 15
import process

func run_jobs(proc: Process, out: Stream) -> int fails process.Error:
    mut jobs = process.group()
    on fail: _ = process.group_close(proc, own jobs, 1000)
    const slow = try process.group_start(proc, mut jobs, process.command(["/bin/sleep", "30"]), None, None)
    const quick = try process.group_start(proc, mut jobs, process.command(["/bin/sh", "-c", "exit 3"]), None, None)
    print(out, "started", process.group_size(mut jobs))
    const done = try process.group_wait_any(proc, mut jobs)
    print(out, "first", done.key == quick, done.output.exited, done.output.code)
    print(out, "still running", process.group_size(mut jobs))
    const rest = try process.group_close(proc, own jobs, 1000)
    for item in rest:
        print(out, "stopped", item.key == slow, item.output.exited, item.output.code)
    return 0


func main(proc: Process, out: Stream) -> int:
    match run_jobs(proc, out):
        case Ok(code):
            return code
        case Err(error):
            print(out, process.message(error))
            return 1
```

### Testing code that runs programs

A test never starts a program (`selka test` runs no child process; the real-effect checks of an application are native
programs). A `proc: Process` parameter of a test, and `process.scripted(rules)` anywhere, is a **scripted Process**: it
needs no grant, starts nothing, and `process.run` on it logs the request and answers from a list of rules:

```text
# doc: not-selka
record Rule:                    enum Reply:
    program: str                    Exit(output: Output)        # a program that ran
    reply: Reply                    Missing                     # no such program: Error.NotFound
    args: str[]? = None             Refused(message: str)       # the system would not start it: Error.Failed
    times: int? = None

scripted(own rules: Rule[]) -> Process     expect(proc, rule)     calls(proc) -> Request[]
exited(code, stdout, stderr) -> Output     executable_path(proc) -> str fails str
```

A rule **covers** a request when its `program` is exactly the request's `argv[0]` and, if `args` is `Some(prefix)`, the
arguments after the program begin with `prefix` (`None` covers any arguments). `times` is how many requests the rule
answers: `None` without limit, `Some(n)` for the first n, after which it covers nothing and the next rule may answer. The
**first covering rule in order** answers, and a request nothing covers fails
`Error.Failed("scripted Process has no rule for ['git', 'status']")`, spelling the whole `argv`. `Reply.Exit` answers its
`Output` (an `Output` with `exited=False` is a program ended by a signal), `Reply.Missing` fails `Error.NotFound` naming
the requested program, and `Reply.Refused` fails `Error.Failed` with its message. The request checks of `process.run`
(an empty `argv`, a negative `limit`) come first and are not logged.

**Every other request is logged,** answered or not, with the directory, input, environment and `limit` it carried:
`process.calls(proc)` returns them, oldest first. `process.expect(proc, rule)` adds a rule after the existing ones, which is
how a test given an empty script builds one; `expect` and `calls` need a scripted Process and trap (`R_ASSERT`) on a real
one. The state is two byte strings in the stand-in, a function of the program text, so a test that uses a scripted
Process is cached like any other and a changed rule re-runs it. `process.executable_path(proc)` on a scripted Process
answers `process.SCRIPTED_EXECUTABLE_PATH` (`"/scripted/program"`), whatever program runs the test.

`process.start` on a scripted Process starts nothing either: it checks the request as on a real one, logs it, and the
rule that covers it answers as for `run` (`Missing` fails `NotFound`, `Refused` fails `Failed`, no rule fails the same
`Failed`). The `Child` of an `Exit` rule has already ended with that rule's `Output`, and its `pid` is
`process.SCRIPTED_PID` (0): `wait_within` answers the `Output` at once, `signal` sends nothing, and `wait` and `stop`
answer it and end the Child. No output file is written. So the code that starts and stops a server is tested for what it
does with the server's exit status, without a server.

```selka
# doc: expect True 0 b'clean\n'
# doc: expect scripted Process has no rule for ['git', 'log']
# doc: expect 2 ['git', 'status'] ['git', 'log']
import process

func main(out: Stream) -> int:
    const proc = process.scripted([
        process.Rule(program="git", reply=process.Reply.Exit(output=process.exited(0, b"clean\n", b"")), args=Some(["status"])),
    ])
    match process.run(proc, process.command(["git", "status"])):
        case Ok(result):
            print(out, result.exited, result.code, result.stdout)
        case Err(_):
            print(out, "unexpected")
    match process.run(proc, process.command(["git", "log"])):
        case Ok(_):
            print(out, "unexpected")
        case Err(error):
            print(out, process.message(error))
    const calls = process.calls(proc)
    print(out, len(calls), calls[0].argv, calls[1].argv)
    return 0
```

## Files

Data that never changes between runs needs no capability at all:
[`embed_bytes("path")` and `embed_str("path")`](bytes.md#embedding-a-file-at-compile-time)
read a project file when the program is compiled and store it in the executable.

File operations are methods of the `Filesystem` capability, so authority is
visible at every call site rather than hidden in a global: `fs.read_text(path)`.
The free spelling `read_text(fs, path)` was a second spelling and is refused since
W13-S5 (`E_REMOVED_SPELLING`); `selka fix` writes the method. The method belongs
to the receiver, so a declared function or local named `read_text` does not claim it.

```selka
# doc: allow-read notes
# doc: expect Ok('hello from a granted directory\n')
# doc: expect True False
func main(fs: Filesystem, out: Stream) -> int:
    print(out, fs.read_text("greeting.txt"))
    print(out, fs.exists("greeting.txt"), fs.exists("absent.txt"))
    return 0
```

`fs.open(path, mode)` returns `Result[File, str]` for a binary mode and
`Result[TextFile, str]` for a text mode. The mode is a literal: `"r"`, `"w"` or
`"a"` with an optional `"b"` or `"t"`. A binary handle reads `bytes`; a text
handle reads `str`. The free `fs.open(path, mode)` form is equivalent.

`with fs.open(...) as f:` opens the file and **traps** with a located `R_FILE`
error if it cannot (`open 'absent.txt': the path does not exist`), the way Python's `open` raises. Writing
`with try fs.open(...) as f:` propagates the failure instead, in a function that
returns a compatible `Result` (postfix `?` is rejected; see
[propagation](results-and-options.md#postfix-error-propagation)):

```selka
# doc: allow-read notes
# doc: expect b'hello from a granted directory\n'
# doc: expect 3
func count(fs: Filesystem) -> int fails str:
    mut total = 0
    with try fs.open("lines.txt", "r") as f:
        for line in f.readlines():
            total = total + 1
    return total

func main(fs: Filesystem, out: Stream) -> int:
    with fs.open("greeting.txt", "rb") as f:
        print(out, f.read())
    match count(fs):
        case Ok(value):
            print(out, value)
        case Err(message):
            print(out, message)
    return 0
```

A handle supports `f.read()`, `f.read(n)`, `f.readline()`, `f.readlines()`,
`f.write(data)`, `f.flush()`, `f.sync()` and `f.close()`. `readline` and `readlines` keep
their line terminators. `write` returns the number of bytes written and loops
over partial writes. `flush` exists for familiarity; writes are unbuffered, so
`flush` does nothing and **is not a durability promise**: a written record sits in
the operating system's cache until the system writes it out. `f.sync()` is the
promise (below). Iterate a file with `for line in f.readlines():` — a handle is not
itself iterable.

What a read answers is one buffer, and the fields of a header or a record in it are pieces of that buffer. A slice is read in
place and needs no copy; to hand a piece to a caller, to keep where it is, or to keep it for good, see
[Keeping pieces of a buffer](ownership-rules.md#keeping-pieces-of-a-buffer).

#### Making an appended record durable: `f.sync()`

`f.sync()` answers `Result[Unit, str]`. When it answers `Ok`, everything written through the
handle so far is on stable storage (`fsync(2)`; the handle holds no buffer of its own, so
that is the whole of the work, once, after the data). A log is "append a record, sync,
acknowledge", and this is the sync. It needs no authority beyond the handle's own: the
file was opened under the rules of its root.

It is a result, not a trap, because a full disk or an I/O error is something a program can
answer (stop acknowledging, report it). The text of the `Err` names the path and the
system's reason, written for a person: `sync 'wal.log': no space left on the device`.
A file that is not a regular file (a device) answers `sync '/dev/full': this kind of file
cannot be synchronized`. A handle opened only for reading has written nothing, so its `sync`
answers `Ok` and does nothing, as `flush` does. A test's in-memory filesystem has no
storage to wait for and answers `Ok`. Like every method, `sync` on a closed handle traps
with `R_FILE`.

A file that was just created is durable only when the folder that holds it is synced too: a
power loss can leave the data on disk and the name missing. `f.sync()` does not sync the
folder (nothing syncs it implicitly); call `fs.sync_directory(path)`
([below](#durable-storage)) once, after the file is created, and not again for each record.
The example runs on the in-memory filesystem a test is handed, so it writes no file; with the
`Filesystem` that `main` receives the calls are the same:

```selka
# doc: expect Ok(12)
# doc: expect Ok(None)
# doc: expect Ok(13)
# doc: expect Ok('first record\nsecond record\n')
import filesystem

func append_record(fs: Filesystem, record: str) -> int fails str:
    with try fs.open("wal.log", "a") as log:
        _ = log.write(record + "\n")
        _ = try log.sync()
    return len(record)

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    print(out, append_record(fs, "first record"))
    print(out, fs.sync_directory(""))
    print(out, append_record(fs, "second record"))
    print(out, fs.read_text("wal.log"))
    return 0
```

The scope closes its file exactly once at every exit: falling off the end,
`return`, `try` propagation, `break`, `continue`, an explicit `f.close()`, and a
trap or host allocation failure unwinding through it. A method on a closed handle
traps with `R_FILE`, as does any provider failure during a method, because
`f.read()` yields bytes rather than a result. The trap names the call, the path the program
gave and the system's reason in the words of the table below, so a program that fills its disk
ends with `error[R_FILE]: write '/dev/full': no space left on the device` (a method on a
closed handle: `write 'out.txt': the file is already closed`). A program that has to go on
after a failed write uses the whole-file calls, which answer a `Result`.

An open binding is used through its own methods, or lent whole to a helper as a `mut`
argument: the helper declares `mut f: File`, the call writes `put(mut f, data)`, and the
scope still closes the file once. It cannot be given away with `own`, stored in a record or
returned: each is `E_WITH_RESOURCE`. A type that would store one is refused where it is
declared, whether or not any function uses it: a record field of `File` or `TextFile`, a list,
dictionary or option of them, a variant case, a generic record instantiated with one
(`Box[File]`) and a callback type that takes or returns one. A `result` whose `ok` case is a
file, the shape `fs.open` returns, is the one way a type carries a file onward.

```selka
# doc: expect 8
import filesystem

func put(mut f: File, line: bytes) -> int:
    return f.write(line)

func main() -> int:
    mut fs = filesystem.memory()
    with fs.open("lines.bin", "wb") as f:
        const first = put(mut f, b"one\n")
        return first + put(mut f, b"two\n")
```

```selka
# doc: expect-error E_WITH_RESOURCE
func keep(fs: Filesystem) -> File:
    with fs.open("a.bin", "wb") as f:
        return f

func main() -> int:
    return 0
```

```selka
# doc: expect-error E_WITH_RESOURCE
record Journal:
    entries: int
    file: File

func main() -> int:
    return 0
```

The whole-path helpers are methods on the `Filesystem` value, and each keeps a
free-function spelling that takes the capability first:

| Method | Free form | Result |
| --- | --- | --- |
| `fs.read_file(path)` | `fs.read_file(path)` | `Result[bytes, str]` |
| `fs.read_text(path)` | `fs.read_text(path)` | `Result[str, str]` |
| `fs.write_file(path, data)` | `fs.write_file(path, data)` | `Result[Unit, str]` |
| `fs.write_text(path, text)` | `fs.write_text(path, text)` | `Result[Unit, str]` |
| `fs.exists(path)` | `fs.exists(path)` | `bool` |
| `fs.listdir(path)` | `fs.listdir(path)` | `Result[list[str], str]` |
| `fs.mkdir(path)` | `fs.mkdir(path)` | `Result[Unit, str]` |
| `fs.remove(path)` | `fs.remove(path)` | `Result[Unit, str]` |

**Walking a folder.** `fs.listdir(path)` answers names only. To know which names are folders, `import filesystem`
and call `filesystem.list_entries(fs, path)`: it answers `Entry[]` (`name` and `kind`: `Regular`, `Directory`,
`Symlink` or `Other`) in one listing, with no `stat` per name ([listings with entry kinds](#listings-with-entry-kinds)).
A walk of a whole tree keeps a list of folders still to read, and each pass reads one and adds its folders to the list:

```selka
# doc: expect ['tree/a.txt', 'tree/sub/b.txt']
import filesystem
import lists

# Every file below `root`: a list of folders still to read, and one listing for each.
func files_below(fs: Filesystem, root: str) -> str[] fails str:
    mut found: str[] = []
    mut pending: str[] = [copy(root)]
    while len(pending) > 0:
        const dir = lists.pop(mut pending)
        const entries = try filesystem.list_entries(fs, dir)
        for entry in entries:
            const path = dir + "/" + entry.name
            match entry.kind:
                case Directory:
                    append(mut pending, own path)
                case Regular:
                    append(mut found, own path)
                case _:
                    pass
    return sorted(found)


func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("tree")
    _ = fs.mkdir("tree/sub")
    _ = fs.write_text("tree/a.txt", "a")
    _ = fs.write_text("tree/sub/b.txt", "b")
    const files = files_below(fs, "tree") else Err(message):
        print(out, message)
        return 1
    print(out, files)
    return 0
```

The error text of these calls names the operation, the path and a readable reason, for example
`read 'absent.txt': the path does not exist`. When the operating system refuses, the reason
is its own, from one table for every call that touches a file (the whole-file calls, the
methods of an open file, the durable calls and `filesystem.memory()`; the last gives the
sentences it can produce): `no space left on the device`, `disk quota exceeded`, `the file is
too large for the size limit or for the filesystem`, `the filesystem is read-only`,
`permission denied`, `too many files are open`, `the path, or a name in it, is too long`,
`input/output error`, `is a directory`, `a parent of the path is not a directory`,
`the path does not exist` and, for a call that creates a file below a folder that is not
there, `a folder on the way does not exist`. A system error outside the table gives its number
and the system's own words (`error 71: protocol error`), so no reason is lost. For example
`write '/dev/full': no space left on the device`, `atomic write 'out/log-2': the file is too
large for the size limit or for the filesystem`, `write 'ro/new': permission denied`,
`read 'notes': is a directory`,
`read '/etc/shadow': permission denied`, `read 'f.txt/x': a parent of the path is
not a directory`, `mkdir 'made': already exists`, `mkdir 'a/b': the parent directory
does not exist`, `listdir 'f.txt': is not a directory`, `remove 'full': the directory
is not empty`. A refusal by `--restrict` or by a narrowed handle starts with `denied:` and says which of the three
refusals below it is; a run without `--restrict` never mentions grants.

#### How a path is read

One rule covers every call that takes a path on the `Filesystem` a run hands to `main`: the methods above, `fs.open`,
`fs.dir`'s folder and every call of the `filesystem` module (`stat`, `read_at`, `list_entries`, `set_modified`, `chmod`,
`symlink`, `rename` and the rest).

1. **Resolution.** A path is read as an ordinary process reads it: absolutely when it starts with `/`, otherwise
   against the working directory. `.`, `..`, doubled slashes and a trailing slash mean what they mean to the system, and
   a trailing slash on something that is not a directory fails as the system's call does (`a parent of the path is not
   a directory`). An empty path names the working directory for `exists`, `stat` and the listings and nothing for the
   other calls; a path that holds a NUL octet is refused (`the path contains a NUL octet`).
2. **Without `--restrict`** nothing else is checked: every call accepts what `read_text` accepts, the durable calls of
   `filesystem` included, so `filesystem.stat(fs, "../f")`, `filesystem.list_entries(fs, "dir/")` and `./a//b` work.
3. **Under `--restrict`** the resolved path must also fall inside a granted directory: a directory of `--allow-read` or
   `--allow-write` for a call that reads, one of `--allow-write` for a call that changes the disk. So the command line
   that works in a plain run works restricted: with `--restrict --allow-write=out`, `out/report.txt`,
   `./out/report.txt` and its absolute path all name the file, and `report.txt` names `report.txt` in the working
   directory (inside the grant only when the program was started in `out`). A path never means "this name in whichever
   grant has it" any more.
4. **A folder handle keeps its own rule; `fs.read_only()` does not.** On a handle from `fs.dir("d")` or
   `filesystem.dir_at` a path stays relative to the handle's folder, and `..`, `.`, an empty part, an absolute path and
   a symbolic link are refused, in every run (a backslash is an ordinary byte of a name, as on `fs`)
   ([Records that hold capabilities](#records-that-hold-capabilities)). Only the folder given to `fs.dir`, or to
   `filesystem.dir_at`, is read by rules 1 to 3 ([A folder named at run time](#a-folder-named-at-run-time-filesystemdir_at)).
   `fs.read_only()` is not a folder handle: it removes writing and nothing else, so it reads a path by rules 1 to 3 as
   the handle it narrows does, and `..` or an absolute path reads through it as through `fs`. The table after this
   list shows what each kind of handle refuses.
5. **Three refusals, three texts.** Outside every grant: `read '../x': denied: '/home/me/x' is outside the granted
   directories`, with the path as it was resolved. Inside a read grant by a call that writes: `write 'notes/a': denied:
   writing needs a write grant (--allow-write); '/srv/notes/a' is granted for reading only`. Refused by a narrowed
   handle: `write 'a': denied: this Filesystem was narrowed by fs.read_only() and does not write`, or `read '../a':
   denied: a Filesystem narrowed by fs.dir takes a path inside its folder, without '..', '.', an empty part or a
   leading '/'`.
6. **Every backend reads a path the same way**: the real filesystem, a native executable under
   `SELKA_OPTIONS=--restrict`, debug and `--release`. The in-memory filesystem (`filesystem.memory()`, and the one
   `selka test` gives a test) is a tree whose root is both its working directory and its one write grant: `./a`,
   `a//b`, `a/../b` and `dir/` work there, and `..` past the root or an absolute path is refused as outside it.

What each kind of handle refuses, found by running a read and each write below on a folder that held a file, a
sub-folder, a link to the sub-folder, a link to the file and a file whose name has a backslash, in a run with
`--restrict` and one without. "Rules 1 to 3" means the handle adds nothing, so the run's rules above decide; the other
cells name the handle's own refusal:

| The call names | `fs` as `main` gets it | `fs.read_only()` | `fs.dir("d")`, `filesystem.dir_at` | `fs.dir("d").read_only()` |
| --- | --- | --- | --- | --- |
| A write of any kind, on any path: `write_text`, `write_file`, `open` to write or append, `atomic_write_file`, `replace_file`, `mkdir`, `remove`, `rename_path`, `chmod_path`, `touch_path`, `set_modified_path`, `symlink_path`, `link_path`, `mkdir_mode`, `create_mode`, `lock_file` (every name a call takes, such as both of `rename_path`'s) | rules 1 to 3 | **refused**: `denied: this Filesystem was narrowed by fs.read_only() and does not write` | allowed, on the paths of the rows below | refused as `fs.read_only()` refuses it, before the path is looked at |
| `..` or an absolute path | rules 1 to 3 | **rules 1 to 3**: a read works as on `fs` | refused for every call, read or write: `denied: a Filesystem narrowed by fs.dir takes a path inside its folder, without '..', '.', an empty part or a leading '/'` | a read is refused as `fs.dir` refuses it |
| A `.` or an empty part (`./f`, `a//f`, and `.` alone: `""` names the folder itself) | rules 1 to 3 | **rules 1 to 3** | refused, with the same text | a read is refused as `fs.dir` refuses it |
| A backslash in a name (`a\b`, `..\x`) | rules 1 to 3: an ordinary name | **rules 1 to 3** | an ordinary name in the folder, as on `fs`: `..\x` and `a\..\b` are names, never a step out | a read works as on `fs.dir` |
| A symbolic link on the way (`link/f`) | rules 1 to 3: followed in a run without `--restrict`, refused under it | **rules 1 to 3** | refused for every call in every run: `a parent of the path is not a directory` | a read is refused as `fs.dir` refuses it |
| A symbolic link at the end | rules 1 to 3 for a read or a write; `link_path` takes no link as its source and `chmod_path` of a link fails, in every run | **rules 1 to 3** for a read | a read, a write and the source of `link_path` are refused: `is a symbolic link the sandbox does not follow, or links nest too deeply`; `chmod_path` of a link fails (`a symbolic link has no permission bits of its own`); `touch_path`, `set_modified_path`, `rename_path` and `remove` act on the link itself | a read is refused as `fs.dir` refuses it |

So `fs.read_only()` changes what a call may do, and `fs.dir` and `filesystem.dir_at` change which paths a call may
name. `exists` never fails: it answers `False` for a path a folder handle refuses, as for one that is not there. On a
folder handle that is also read-only a write is refused as a write whatever its path, and a read by the folder's rule.
In the example `ro` reads a path with a `.` part and refuses the write, and `folder` refuses the `.` part:

```selka
# doc: expect Ok('x') Err("write 'd/b.txt': denied: this Filesystem was narrowed by fs.read_only() and does not write")
# doc: expect Ok('x') Err("read './a.txt': denied: a Filesystem narrowed by fs.dir takes a path inside its folder, without '..', '.', an empty part or a leading '/'")
import filesystem

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("d")
    _ = fs.write_text("d/a.txt", "x")
    const ro = fs.read_only()
    const folder = fs.dir("d")
    print(out, ro.read_text("d/./a.txt"), ro.write_text("d/b.txt", "y"))
    print(out, folder.read_text("a.txt"), folder.read_text("./a.txt"))
    return 0
```

How "inside a grant" is decided, so that no spelling of a path reaches a file outside every grant:

- When the run starts, each grant is opened once, and two names are kept for it: the name on the command line made
  absolute against the working directory, and its real path, every symbolic link in it resolved. The working directory
  is taken once too, as the system names it.
- The path is made absolute, and its `.` and empty components are dropped and each `..` removes the component before it,
  as text. A `..` that removes a component of the working directory is exact, because that name has no link in it. A `..`
  that removes a component the program wrote (`a/..`) is accepted only when that component is a directory inside a grant
  and not a symbolic link, which the runtime checks by walking to it; otherwise the system, which follows a link before it
  climbs, could reach another directory than the text names, and the path is refused as outside. A `..` that climbs out
  of a grant named through a link is refused for the same reason.
- The result is inside a grant when it is one of the grant's two names or starts with one of them and a `/`: `g2/a` is
  not inside `g`. When several grants hold it, the one with the longest name serves it. A path that reaches a grant
  through a link of its own (`/home/me/shortcut/g/a`, with `shortcut` a link) names neither and is refused, because the
  text alone cannot tell where the link leads.
- The rest of the path is walked from the directory the grant opened when the run started, one component at a time and
  only downwards, and no symbolic link is followed, on the way or at the end; an append refuses a link at its end, and
  only regular files are read or written. A link made inside a grant after the start, a grant renamed or replaced by a
  link, or a name that spells its way around a grant with `..`, cannot move that walk out of the grant's directory.

A whole-file read (`read_file`, `read_text`, `File.read()` and `File.readline()` with no count) has no
size cap: it returns every octet of the file. The run's byte ceiling (`--max-memory`) still bounds it, and a
read past that ceiling traps `R_MEMORY_BUDGET` rather than returning a prefix. A count passed to
`File.read(n)` or `File.readline(n)` is the most that call returns.

A restricted example in this guide runs in its granted directory (`notes`), as a program started in the folder it
reads does. A directory granted with `--allow-write` is always readable too, so write authority is never narrower than
read authority:

```selka
# doc: allow-read notes
# doc: expect Err("read '/etc/hostname': denied: '/etc/hostname' is outside the granted directories")
# doc: expect True
# doc: expect True
import strings

func main(fs: Filesystem, out: Stream) -> int:
    print(out, fs.read_text("/etc/hostname"))
    match fs.read_text("../escape"):
        case Ok(_):
            print(out, False)
        case Err(message):
            print(out, strings.ends_with(message, "/fixtures/escape' is outside the granted directories"))
    match fs.write_text("new.txt", "x"):
        case Ok(_):
            print(out, False)
        case Err(message):
            print(out, strings.count(message, "denied: writing needs a write grant (--allow-write)") > 0)
    return 0
```

A whole-file read (`read_file`, `read_text`, `File.read()` and `File.readline()` with no count) has no
size cap: it returns every octet of the file. The run's byte ceiling (`--max-memory`) still bounds it, and a
read past that ceiling traps `R_MEMORY_BUDGET` rather than returning a prefix. A count passed to
`File.read(n)` or `File.readline(n)` is the most that call returns.

File operations require a `Filesystem` capability. The old `noio` clause
is retired:

```selka
# doc: expect-error E_EFFECTS_REMOVED
func main(fs: Filesystem) -> int noio:
    _ = fs.exists("notes.txt")
    return 0
```

An invalid resource type in `with` is rejected with `E_TYPE`
(the retired `with arena():` is rejected with
`E_ARENA_REMOVED`):

```selka
# doc: expect-error E_TYPE
func main() -> int:
    with 7 as value:
        return 0
```

Generic function bodies reject file operations.

## The native backend

`selka build` writes a native executable, and `selka run` and `selka build
--run` build one and run it. A native executable grants every capability by
default, exactly as `selka run` does. It never reads an option from its own
arguments — every one of them is the program's — so its runtime options travel
in the `SELKA_OPTIONS` environment variable instead: `--restrict`, the `--allow-*`
grants and `--print-result`, separated by spaces. Wrap an option that contains a
space in double quotes (a backslash inside the quotes escapes the next character).
An unknown option, a repeated grant or an unterminated quote exits 2 when the runtime
reads its grants, which happens at start-up for an entry point that takes a
capability. A binary's byte ceiling is `--max-memory=SIZE` in `SELKA_OPTIONS`, else
`SELKA_MEMORY_LIMIT`, else none (`K`/`M`/`G` suffixes, `0` for none; a size that is
not one exits 2): past it the binary traps `R_MEMORY_BUDGET` and exits 1, as under
`selka run` ([runtime budgets](tooling/runtime-budgets.md#guest-memory-ceilings)).
The step and frame budgets (`--max-steps`, `--max-frames`) are not runtime options:
`selka run` and `build --run` build them into the program they run, and a binary
from `selka build -o` has none. What bounds a binary's
recursion is its native stack, 8 MiB by default: a deeper recursion ends with
`R_FRAME_LIMIT`, and the message names `ulimit -s KBYTES` (set before starting the
binary) as the way to raise it. `selka build --run` takes
the grants on its own command line, before `--`, and passes the values after `--`
to the program:

```text
$ SELKA_OPTIONS='--restrict --allow-read=notes' ./report --format=json
$ selka build report.selka --run --restrict --allow-read=notes -- --format=json
```

`selka run`, `run-project` and `build --run` set `SELKA_OPTIONS` for the
program from their own command line, replacing any value they inherited.

A native executable exits with the entry point's `int` result (truncated to the
low 8 bits), the way `selka run` does, and writes that result after the
program's own output only when `SELKA_OPTIONS` names `--print-result`.

Generic function bodies still reject `print` and the file builtins, with
`E_GENERIC_BODY_UNSUPPORTED`. Write an ordinary function and call it from the
generic one.

## Related pages

- Scoped providers (the design record `experiments/scoped-providers.md`) — the adapter these grants configure

## Durable storage

Native `Filesystem` capabilities provide five explicit operations (four more, rename, stat and file locks, follow
the table):

| Operation | Result |
| --- | --- |
| `fs.list_directory(path, max_entries)` | `Result[str[], str]` |
| `fs.read_regular_file(path, max_bytes)` | `Result[bytes, str]` |
| `fs.atomic_write_file(path, data)` | `Result[Unit, str]` |
| `fs.sync_directory(path)` | `Result[Unit, str]` |
| `fs.lock_directory(path)` | `Result[File, str]` |

Use `with try fs.lock_directory("") as lease:` to own a narrowed root until
scope exit. The lease is exclusive across processes and is released after a
process dies. Busy ownership returns an error whose text ends `: the lock is held by another holder`, the text of a
held file lock. Overlapping grants must resolve to one physical
directory for a lease; ambiguous roots are rejected. Listing takes any non-negative bound, lists a
directory of any size whole under it, and rejects an incomplete read or a listing over the bound
([below](#large-directories-and-listing-bounds)). Reads reject symlinks, special
files and values above the requested limit before unbounded allocation. Scoped paths and write grants remain
checked. A 64 MiB ceiling belongs to some of these calls and not to every read and write ([which](#which-calls-have-a-64-mib-ceiling)).
The in-memory `filesystem.memory()`, which is also what a test's `fs`
parameter is, answers all of them from its own entries
([below](#the-durable-calls-on-a-tests-filesystem)); an embedding provider that cannot
promise durability returns an explicit unsupported error.

```selka
# doc: expect 42
import filesystem

func main() -> int:
    const fs = filesystem.memory()
    match fs.atomic_write_file("result", b"value"):
        case Err(_):
            return 1
        case Ok(_):
            match fs.read_regular_file("result", 16):
                case Ok(data):
                    return len(data) + 37
                case Err(_):
                    return 2
```

### Which calls have a 64 MiB ceiling

The ceiling is 64 MiB, 67,108,864 octets, and a size of exactly that is accepted. It belongs to the durable calls, and
the plain whole-file calls have none. Each call below was run on a file of 120 MiB, on a real folder:

| Call | At 120 MiB | Text |
| --- | --- | --- |
| `fs.read_file(path)`, `fs.read_text(path)`, `File.read()` | answers the whole file | none; the run's `--max-memory` still bounds the read |
| `fs.write_file(path, data)`, `fs.write_text(path, text)`, `File.write(data)` | writes it | none |
| `fs.atomic_write_file[_mode]`, `fs.replace_file[_mode]`, `fs.replace_file_synced[_mode]` | refused, nothing written | `atomic write 'PATH': is over the 64 MiB bound of one write` (`replace 'PATH': ...` for the other two) |
| `fs.read_regular_file(path, max_bytes)` | refused when `max_bytes` is over 64 MiB, and when the file is larger than `max_bytes` | `max_bytes is over the 64 MiB bound of one read`, or `is larger than max_bytes` |
| `filesystem.read_at(fs, path, offset, max_bytes)` | refused when `max_bytes` is over 64 MiB; any `offset` of the file works | `max_bytes is over the 64 MiB bound of one read` |

So a file over 64 MiB is read whole with `read_file`, in pieces of at most 64 MiB with `read_at`, and written with
`write_file` or `File.write`; it cannot be published with `atomic_write_file` or `replace_file` (write it to a
temporary name and `rename_path` it, which has no size to refuse and does not force the data to disk). A
`filesystem.memory()` filesystem, and a test's `fs`, holds 64 MiB of file bytes in all, whatever the calls: a
`write_file` that would take it past that answers `Err` with `no space left on the device`, and a `File.write` traps
`R_FILE` with the same text.

### Large directories and listing bounds

`listdir` and `list_directory` answer a directory of any size whole: nothing caps the number of entries, on a real
directory (granted, narrowed or unrestricted) or on `filesystem.memory()`. (A fixed 256-entry snapshot once refused a
directory of 257, and refused it as `denied: outside the granted directories`, a message that named the grants when
the grants were not the cause.) `listdir` has no bound of its own; a listing larger than the run's byte ceiling
(`--max-memory`) traps `R_MEMORY_BUDGET` like any other allocation.

The bound of `fs.list_directory(path, max_entries)` is the caller's, whatever its size. A directory that holds more
than `max_entries` entries is refused with a message that says so, and a negative bound is refused too; neither
names the grants:

| `fs.list_directory("big", n)` | Result |
| --- | --- |
| a directory of at most `n` entries | `Ok` of every name (a real directory in the system's order, the in-memory one sorted) |
| more than `n` entries | `Err("directory listing 'big': has more than 4999 entries (the max_entries bound)")` for `n = 4999` |
| `n < 0` | `Err("directory listing 'big': max_entries must not be negative")` |

```selka
# doc: expect 5000 5000
# doc: expect Err("directory listing 'big': has more than 4999 entries (the max_entries bound)")
import filesystem
import strings

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("big")
    for index in range(5000):
        match strings.pad_left(str(index), 5, "0"):
            case Ok(digits):
                _ = fs.write_text("big/" + digits, "")
            case Err(_):
                return 1
    match fs.listdir("big"):
        case Ok(all):
            match fs.list_directory("big", 5000):
                case Ok(bounded):
                    print(out, len(all), len(bounded))
                case Err(message):
                    print(out, message)
        case Err(message):
            print(out, message)
    print(out, fs.list_directory("big", 4999))
    return 0
```

### Listings with entry kinds

`listdir` answers names only, so a scan that needs to know which names are directories would `stat` every one of them.
`filesystem.list_entries(fs, path)` answers the names and the kinds in one listing:

| Operation | Result | Authority |
| --- | --- | --- |
| `fs.list_entries_path(path)` | `Result[bytes, str]`, packed | read |
| `filesystem.list_entries(fs, path)` | `Entry[] fails str` | read |

An `Entry` has `name: str` and `kind: PathKind` (`Regular`, `Directory`, `Symlink` or `Other`, the kinds `stat` reports).
The kind is the directory record's own (`d_type`), so the listing is as cheap as `listdir`: a read of the directory and no
`stat` of any entry. (An entry whose record carries no type, which a few filesystems report for every entry, costs one
`fstatat` of that entry.) It is the entry's own kind, as `stat` reports it and `stat_follow` does not: a symbolic link
is `Symlink` even when it names a directory, and `list_entries` of that link fails with `is not a directory` in every run,
while `fs.listdir` of it lists the folder it names in a run without `--restrict` (under a restriction or a narrowing both
refuse it). To list what the link points at, list `filesystem.realpath(fs, path)`, the folder's own name, which a
restriction allows while the folder is inside a grant. A real
directory lists in the system's order, `filesystem.memory()` sorted by name, and a directory of any size lists whole
([above](#large-directories-and-listing-bounds)). A path that is not a directory, is missing or is refused fails with
`directory listing 'path': ...` and the reason, never the grants unless a grant is the cause. A listing, like a stat, opens the
directory with one `openat` from a descriptor the capability keeps (no descriptor is duplicated; a path of more than one component
under a grant adds one confined `openat2`). The builtin
`list_entries_path` answers the packed octets the typed function decodes: for each entry a kind octet (1 regular file,
2 directory, 3 symbolic link, 0 anything else), a little-endian 16-bit name length and the name.

```selka
# doc: expect 3 files, 2 directories
import filesystem

# The files and directories below `dir`, one listing for each directory and no stat.
func count(fs: Filesystem, dir: str, mut files: int, mut dirs: int):
    match filesystem.list_entries(fs, dir):
        case Err(_):
            return
        case Ok(entries):
            for entry in entries:
                match entry.kind:
                    case Directory:
                        dirs += 1
                        count(fs, dir + "/" + entry.name, mut files, mut dirs)
                    case Regular:
                        files += 1
                    case _:
                        pass

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("tree")
    _ = fs.mkdir("tree/sub")
    _ = fs.mkdir("tree/sub/deep")
    _ = fs.write_text("tree/a.txt", "a")
    _ = fs.write_text("tree/sub/b.txt", "b")
    _ = fs.write_text("tree/sub/deep/c.txt", "c")
    mut files = 0
    mut dirs = 0
    count(fs, "tree", mut files, mut dirs)
    print(out, files, "files,", dirs, "directories")
    return 0
```

### Rename, stat and file locks

Four more durable operations let a program publish a file, look at it cheaply and serialize with other processes.
They read a path as every other call does ([How a path is read](#how-a-path-is-read): `.`, `..` and a trailing slash
mean what they mean to the system, and under `--restrict` the path must fall inside a grant, where a symbolic link is
never followed on the way), and each has the free and the `fs.` method spelling like the other helpers. Without `--restrict` the links on the way
to the final component are followed, as `read_text` follows them, so `stat` of `link/file` works when `link` names a
directory; the final component itself is never followed by these calls. A handle narrowed by `fs.dir(path)` is the
exception: it follows no link on the way in any run, as under `--restrict`.

| Operation | Result | Authority |
| --- | --- | --- |
| `fs.rename_path(from, to)` | `Result[Unit, str]` | write, over both paths |
| `fs.stat_path(path)` | `Result[bytes, str]` | read |
| `fs.lock_file(path)` | `Result[File, str]` | write |
| `fs.try_lock_file(path)` | `Result[File, str]` | write |

`rename_path` is the atomic `rename(2)` inside one granted directory: a file destination is replaced in one step, so
a reader sees the old file or the new one and never a partial one. It does not copy: a rename across filesystems
fails with `the paths are on different filesystems`, and both paths must resolve in the same granted directory. It
does not synchronize the directory; call `sync_directory` when the rename must survive a power loss.

`stat_path` answers 80 packed octets (size, modification time in nanoseconds since the Unix epoch, inode, kind,
permission bits, status-change time, device, owning user, owning group and number of hard links, ten little-endian 64-bit
words), or an **empty** `bytes` when nothing is at the path. The `filesystem` module wraps it as `filesystem.stat(fs, path)`,
which returns a `filesystem.Stat` (`kind`, `size`, `modified`, `inode`, `mode`, `changed`, `device`, `owner`, `group` and
`links`) and fails with `filesystem.StatError`: `Missing` when nothing is at the path, or under a
directory that does not exist, and `Failed(message)` for any other refusal, so a caller can match the missing case. The
final component is not followed, so a symbolic link is a `Symlink`; `filesystem.stat_follow` describes its target
instead (see [real paths, permissions and times](#real-paths-permissions-and-times)). `Stat.mode` holds the
permission bits (`0o644`, plus the set-user-ID, set-group-ID and sticky bits when set; the kind is not among them) and
defaults to `0` in a constructor that leaves it out.

A stat is one `fstatat` of the path relative to a directory the capability keeps open. Without a restriction the whole
path goes to that one call, which follows the links on the way (unless the handle is narrowed by `fs.dir`, which takes the
route of a grant); under a grant a path of one component is that same single call, and a deeper path adds one `openat2` (a
single call that refuses every symbolic link on the way and cannot leave the granted directory) and the close of the directory
it returns. No descriptor is duplicated for the call and no directory on
the way is opened one component at a time (it was three to five system calls without a restriction, and up to thirteen under a
grant). A kernel without `openat2` walks a granted path component by component, as before. The directory on the way is
opened for its search permission only, so a directory with no read permission no longer stops a stat below it.

`lock_file` takes an exclusive advisory `flock` on a regular file, creating it (mode 0600) when it does not exist,
and waits while another holder has it. `try_lock_file` is the same lock that fails at once instead of waiting; its
failure text ends with `: the lock is held by another holder`, which `filesystem.is_lock_busy(message)` recognizes.
Both return the `File` of a `with` scope, like `lock_directory`: the lock is released when the scope ends, on every
exit, or when the process dies, so a crashed holder never blocks anyone. Two locks on one file, even in one process,
exclude each other, so a second `lock_file` on a file the process already holds waits forever.

```selka
# doc: allow-read notes
# doc: expect regular 31
# doc: expect missing
# doc: expect rename: denied
# doc: expect lock: denied
import filesystem
import strings

func lock_it(fs: Filesystem) -> int fails str:
    with try fs.try_lock_file("work.lock") as held:
        return 1

func main(fs: Filesystem, out: Stream) -> int:
    match filesystem.stat(fs, "greeting.txt"):
        case Ok(info):
            match info.kind:
                case Regular:
                    print(out, "regular", info.size)
                case Directory:
                    print(out, "directory")
                case Symlink:
                    print(out, "symlink")
                case Other:
                    print(out, "other")
        case Err(_):
            print(out, "unexpected")
    match filesystem.stat(fs, "absent.txt"):
        case Ok(_):
            print(out, "unexpected")
        case Err(error):
            match error:
                case Missing:
                    print(out, "missing")
                case Failed(message=_):
                    print(out, "unexpected")
    match fs.rename_path("greeting.txt", "moved.txt"):
        case Ok(_):
            print(out, "unexpected")
        case Err(message):
            if strings.count(message, "needs a write grant") > 0:
                print(out, "rename: denied")
            else:
                print(out, message)
    match lock_it(fs):
        case Ok(_):
            print(out, "unexpected")
        case Err(message):
            if strings.count(message, "needs a write grant") > 0:
                print(out, "lock: denied")
            else:
                print(out, message)
    return 0
```

The publish-then-swap pattern a cache uses: write the new bytes beside the destination, then rename. A lock around
it keeps two processes from interleaving:

```selka
# doc: check
func publish(fs: Filesystem, name: str, data: bytes) -> int fails str:
    with try fs.lock_file("store.lock") as lease:
        _ = try fs.atomic_write_file(name + ".tmp", data)
        _ = try fs.rename_path(name + ".tmp", name)
        _ = try fs.sync_directory("")
        return len(data)

func main(fs: Filesystem) -> int:
    match publish(fs, "result", b"value"):
        case Ok(count):
            return count
        case Err(_):
            return 0
```

Atomic writes create an exclusive temporary file beside the destination,
complete the write, synchronize the file, rename it and synchronize its parent.
The old or new complete file survives an interrupted publication. A failure
after rename reports that publication may have occurred. Callers must retain
that uncertainty and recover from their journal. `File.flush()` is not a
durability promise; `f.sync()` on an open file is
([above](#making-an-appended-record-durable-fsync)). The native tests establish process-crash recovery; they do
not establish behavior under actual machine power loss.


### Device, free space and reads from an offset

Three more calls answer what a program that watches a machine or follows a file needs. All three take the grants `stat` and
`read_regular_file` take (read authority over the path, the same `.` and `..` rule, a link refused anywhere in the path under
`--restrict`), have the free and the `fs.` method spelling like the other durable calls, and are answered by a `memory()`
filesystem too.

| Operation | Result | Authority |
| --- | --- | --- |
| `fs.statfs_path(path)` | `Result[bytes, str]`, packed | read |
| `fs.read_at_path(path, offset, max_bytes)` | `Result[bytes, str]` | read |

**The device.** `Stat.device` is the `st_dev` the kernel names for the entry, the seventh word of `stat_path`'s answer. An
inode numbers a file only within its device, and `/proc/locks` writes a lock's file as `MAJ:MIN:INODE` (major and minor in
hexadecimal, the inode in decimal), so finding whether a given file is locked needs both. `filesystem.device_major(device)`
and `filesystem.device_minor(device)` take the number apart as `major(3)` and `minor(3)` do, so `fs.stat(path)` on a file and
the pair printed with `%x:%x` match the line `/proc/locks` has for it. A constructor may leave `device` out (`0`), and every entry
of a `memory()` filesystem is on the one device `filesystem.MEMORY_DEVICE` (`1`: major 0, minor 1).

**Owner, group and links.** `Stat.owner` and `Stat.group` are the numeric user and group that own the entry (`st_uid` and
`st_gid`, the numbers `ls -n` prints) and `Stat.links` is its number of hard links (`st_nlink`): the eighth, ninth and tenth
words of `stat_path`'s answer, for `stat` and `stat_follow` alike (`stat` of a symbolic link describes the link, whose count is
`1`). A file with a single name has one link, and a directory has two plus the directories inside it on the usual disk
filesystems (a few, such as `btrfs`, count `1`), so a tool that archives a tree can name each member's owner and tell a file
that has other names. A constructor may leave all three out (`0`). Every entry of a `memory()` filesystem is owned by the
user and the group `filesystem.MEMORY_OWNER` and `filesystem.MEMORY_GROUP` (`1000` both, the first ordinary account, whose
permission bits the stand-in honours, and a fixed number so a test reads the same on every machine); a file or a link there
has one link and a directory two plus the directories directly inside it, since no call makes a second name.

```selka
# doc: expect 1000 1000 1 1000 1000 3
import filesystem

func owned(fs: Filesystem, path: str) -> str:
    match filesystem.stat(fs, path):
        case Ok(info):
            return f"{info.owner} {info.group} {info.links}"
        case Err(_):
            return "missing"

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("d")
    _ = fs.mkdir("d/sub")
    _ = fs.write_text("d/file", "x")
    print(out, owned(fs, "d/file"), owned(fs, "d"))
    return 0
```

**Free space.** `filesystem.statfs(fs, path)` answers a `filesystem.Space` for the filesystem that holds `path`, as `statfs(2)`
does with the blocks multiplied by the fragment size: `size_bytes` (all of it), `free_bytes` and `available_bytes` (the bytes an
ordinary process may still use, at most the free ones, since the system keeps some back). A path with nothing at it fails with
`StatError.Missing`, any other refusal with `Failed(message)`, as `stat` does, and a symbolic link at the end is described by the
filesystem that holds the link, not by its target. On a `memory()` filesystem every existing path answers the same fixed numbers
whatever the filesystem holds, 1073741824 bytes in all, 536870912 free and 402653184 available (three different numbers, so a
test can tell the fields apart). Its path rules are those of a granted directory under `--restrict`, so its root is the empty
path `""`, and `.` and an absolute path such as `/` are refused with `Failed(message)` (`denied: outside the granted
directories`) by `statfs` and `stat` alike, as a restricted program's are.

**Reading from an offset.** `filesystem.read_at(fs, path, offset, max_bytes)` answers at most `max_bytes` octets of the regular
file at `path`, starting at byte `offset`, with `pread`: no octet before the offset is read. It answers fewer octets when the
file ends first, and none (an empty `bytes`) at or past the end, so a program that follows a file that only grows asks again
from the offset where its last answer ended and meets nothing it has read. An open `File` cannot be kept between the turns of a
loop, which is why this is a function of the path. The file is opened as `read_regular_file` opens it (a link, a directory or a
device is refused with the same words, a missing file with `the path does not exist`), the count
is bounded by 64 MiB (`max_bytes is over the 64 MiB bound of one read`; [which calls](#which-calls-have-a-64-mib-ceiling)), and a negative `offset` or `max_bytes` fails with its own message. The raw
builtin takes the offset as eight little-endian octets (`fs.read_at_path(path, offset: bytes, max_bytes)`), the way the
typed function packs it.

```selka
# doc: expect b'first line\n' 11
# doc: expect b'' 11
# doc: expect b'second line\n' 23
# doc: expect True True
import filesystem

func appended(fs: Filesystem, path: str, offset: int) -> bytes:
    match filesystem.read_at(fs, path, offset, 1048576):
        case Ok(data):
            return copy(data)
        case Err(_):
            return b"?"


func add(fs: Filesystem, path: str, data: bytes) -> Unit fails str:
    with try fs.open(path, "ab") as file:
        _ = file.write(data)


func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.write_file("log.jsonl", b"first line\n")
    mut offset = 0
    mut data = appended(fs, "log.jsonl", offset)
    offset += len(data)
    print(out, data, offset)
    data = appended(fs, "log.jsonl", offset)
    print(out, data, offset)
    match add(fs, "log.jsonl", b"second line\n"):
        case Ok(_):
            pass
        case Err(_):
            return 2
    data = appended(fs, "log.jsonl", offset)
    offset += len(data)
    print(out, data, offset)
    match filesystem.stat(fs, "log.jsonl"):
        case Ok(found):
            print(out, found.device == filesystem.MEMORY_DEVICE, filesystem.device_major(found.device) == 0)
        case Err(_):
            return 1
    return 0
```

### Replacing a file without forcing it to disk

`atomic_write_file` makes its bytes survive a power loss, and pays for it: it synchronizes the file before the rename and
the directory after it, two `fsync`s that took 8 ms a write on this machine's ext4 disk on 8 November (40 ms on 7
November and up to 130 ms in the G3 redo, so read the ratio, not the milliseconds). Most rewrites need less, and two more pairs
of calls say how much. `replace_file(fs,
path, data)` and `fs.replace_file_mode(path, data, mode)` publish the same way, a temporary beside the destination renamed
over it, and force nothing to disk, as Zig's `std.fs.AtomicFile` does. `fs.replace_file_synced(path, data)` and
`fs.replace_file_synced_mode(path, data, mode)` force the file to disk before the rename and not the directory after it,
the middle course a Zig program takes when it syncs its temporary file before `AtomicFile` renames it: one `fsync` where
the durable call makes two. 50 rewrites of a small file took 382 to 409 ms with `atomic_write_file` (100 `fsync`), 194 to
228 ms with `replace_file_synced` (50 `fsync`, the file's) and 5 to 12 ms with `replace_file` (none).

| | `atomic_write_file[_mode]` | `replace_file_synced[_mode]` | `replace_file[_mode]` |
| --- | --- | --- | --- |
| How it publishes | a temporary beside the destination, renamed over it | the same | the same |
| A reader sees | the old file or the new one, never a partial one | the same | the same |
| `fsync` of the file before the rename | yes | yes | no |
| `fsync` of the directory after it | yes | no | no |
| After a power loss or kernel crash | the new bytes | the old file (none, for a first write) or the complete new one; the rename may not have reached the disk | the old file; on a filesystem that reorders the rename ahead of the data, possibly a short new one |
| After a crash of the program alone | the old or the new file | the same | the same |
| A failure the call reports | before the rename, nothing changed; after it, "publication may have occurred" when the directory sync fails | before the rename, nothing changed (a failed file sync is such a failure) | none from a sync |
| Cost of a small write on ext4, 8 November | about 8 ms | about 4 ms | well under 1 ms |

Use `atomic_write_file` for a journal, a database record or a cache entry that must still be there after the machine
restarts. Use `replace_file_synced` where a torn file would lose something that an old one only repeats: a file a person
owns that the program rewrites, such as a source file rewritten with minted ids, where the last rewrite may be lost to a
power cut and the next run does it again, but a half-written file would not do. Use `replace_file` for what the next run can
regenerate or the user can redo: a build output, an index. The mode, the refusals and the `Result[Unit, str]` are
`atomic_write_file`'s: the file gets `0600` unless a `_mode` form says otherwise, a directory, a symbolic link or a path
outside the grant is refused, and a failure reads `replace 'path': reason` (the verb is `replace` for all four calls here). It
needs write authority, a test's filesystem answers all four whole (with no synchronization to skip), and the temporary is
removed when the write fails.

```selka
# doc: expect Ok(None) Ok('second')
# doc: expect Ok(None) Ok('third')
# doc: expect Err("replace 'no/dir/file': a folder on the way does not exist")
import filesystem

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.replace_file("notes.txt", b"first")
    print(out, fs.replace_file("notes.txt", b"second"), fs.read_text("notes.txt"))
    print(out, fs.replace_file_synced("notes.txt", b"third"), fs.read_text("notes.txt"))
    print(out, fs.replace_file_synced("no/dir/file", b"x"))
    return 0
```

### Real paths, permissions and times

Eleven more durable operations name a path canonically, change its permissions and times, publish a file with chosen
permissions, describe what a symbolic link points at, create one and read the text it holds, give a file a second name,
make a folder with its permissions and open a file for writing with its permissions. Each has the free and the `fs.` method spelling, takes a
path with no `.` or `..` component (except that `canonical_path` accepts `.` alone for the root), and works on the
in-memory `filesystem.memory()` too ([below](#the-durable-calls-on-a-tests-filesystem)).

| Operation | Result | Authority |
| --- | --- | --- |
| `fs.canonical_path(path)` | `Result[str, str]` | read |
| `fs.chmod_path(path, mode)` | `Result[Unit, str]` | write |
| `fs.touch_path(path)` | `Result[Unit, str]` | write |
| `fs.set_modified_path(path, nanoseconds)` | `Result[Unit, str]` | write |
| `fs.atomic_write_file_mode(path, data, mode)` | `Result[Unit, str]` | write |
| `fs.stat_follow_path(path)` | `Result[bytes, str]` | read |
| `fs.symlink_path(target, path)` | `Result[Unit, str]` | write |
| `fs.read_link_path(path)` | `Result[str, str]` | read |
| `fs.link_path(target, path)` | `Result[Unit, str]` | write |
| `fs.mkdir_mode(path, mode)` | `Result[Unit, str]` | write |
| `fs.create_mode(path, mode)` | `Result[File, str]` | write |

The `filesystem` module wraps them as typed functions that `fail` with the message:

| Function | Result |
| --- | --- |
| `filesystem.realpath(fs, path)` | `str fails str` |
| `filesystem.cwd(fs)` | `str fails str` |
| `filesystem.chmod(fs, path, mode)` | `Unit fails str` |
| `filesystem.touch(fs, path)` | `Unit fails str` |
| `filesystem.set_modified(fs, path, nanoseconds)` | `Unit fails str` |
| `filesystem.stat_follow(fs, path)` | `Stat fails StatError` |
| `filesystem.symlink(fs, target, path)` | `Unit fails str` |
| `filesystem.read_link(fs, path)` | `str fails str` |
| `filesystem.link(fs, target, path)` | `Unit fails str` |
| `filesystem.mkdir_mode(fs, path, mode)` | `Unit fails str` |
| `filesystem.create_mode(fs, path, mode)` | `File fails str` |

`canonical_path` resolves every symbolic link, as `realpath(3)` does, and a missing path fails. **Without a
restriction and under `--allow-read` and `--allow-write` grants** it answers the absolute, link-free path, and
`filesystem.cwd(fs)` (the `realpath` of `.`) is the process's working directory, so the name means the same file in a
plain and a restricted run (under a grant the working directory must itself be inside one). **On an `fs.dir(...)`
narrowing** it answers the path relative to the narrowing, so a program learns nothing of the host's layout beyond it:
the directory itself is the empty string `""`, which every directory operation accepts, and the name is a valid argument
to every other call on the same handle. Under a grant or a narrowing a link is followed only while it stays inside the
directory: an absolute link, or one that climbs out of it, fails with
`resolves outside the granted directory`, and so does a missing path behind such a link, so a failure leaks nothing
about what lies outside. (Every other operation refuses a symbolic link under a restriction, or through an `fs.dir(...)`
narrowing in any run, outright, an append (`open(path, "a")`) too: it writes nothing through a link and creates nothing
through a dangling one; only `canonical_path` and `stat_follow_path` resolve one.)

`stat_follow_path` and `filesystem.stat_follow` are `stat_path` and `stat` that follow a symbolic link at the end of the
path and describe its target, as Zig's `statFile` does; a link to nothing is `Missing`, and the same confinement
applies under a restriction. Without a restriction it answers what `stat(2)` answers, so `/dev/stdin`, `/dev/fd/0` or
`/proc/self/fd/0` when standard input is a pipe is a `Stat` of kind `Other`, as `/dev/null` is. Under `--restrict` and
through `fs.dir(...)` such a path is refused, as `fs.open` of it is: it is outside the grants, or it is a link out of the
granted folder (`resolves outside the granted directory`, where `fs.open` says it does not follow the link).

`chmod_path` sets the permission bits (`0` to `0o7777`; anything else fails with `the mode must be between 0 and
0o7777`), `touch_path` sets the access and modification times of an existing path to now, and `set_modified_path`
sets the modification time to `nanoseconds` since the Unix epoch and leaves the access time. None of them follows a
symbolic link at the end of the path: `chmod` of a link fails (`a symbolic link has no permission bits of its own`),
and `touch` and `set_modified` change the link itself. `touch_path` does not create a missing path, so a racing delete
cannot leave an empty file behind; write the file first.

`fs.symlink_path(target, path)` creates the symbolic link `path` holding the text `target`, written target first as `ln -s TARGET
LINK` and Zig's `symLink` take it. It is a write like the others: it needs write authority, the link's directory must be
inside a write grant and exist, and a path outside every grant, inside only a read grant, or already taken is refused
(`symlink 'path': already exists`, `denied: 'RESOLVED' is outside the granted directories`). The target
is only text: relative to the link's directory, absolute, or naming nothing, it is stored as written and is not looked at,
since a link does nothing until a call follows it, and the two calls that do (`canonical_path` and `stat_follow_path`)
follow it only while it stays inside the granted directory. Every other call refuses a link on the way to its path, and
a read, a write, an append or a lock of a link itself, so a program that makes one can build the tree that tests of that refusal need:
`fs.symlink_path("/etc", "outside")` then `fs.read_regular_file("outside/passwd", 100)` fails with `is a symbolic link
the sandbox does not follow`. `stat_path` of the link answers `Symlink` with its size the length of its target, `remove`
unlinks it and `rename_path` moves it. The target holds from 1 to 4094 octets and no NUL (`the link target must be text of 1
to 4094 octets with no NUL`).

```selka
# doc: expect Ok(None) 11 Ok('shared/data')
# doc: expect Err("realpath 'outside': resolves outside the granted directory")
# doc: expect Err("read 'link': is a symbolic link the sandbox does not follow, or links nest too deeply")
import filesystem

func link_size(fs: Filesystem, path: str) -> int:
    match filesystem.stat(fs, path):
        case Ok(info):
            return info.size
        case Err(_):
            return -1

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("shared")
    _ = fs.write_text("shared/data", "payload")
    print(out, filesystem.symlink(fs, "shared/data", "link"), link_size(fs, "link"), filesystem.realpath(fs, "link"))
    _ = filesystem.symlink(fs, "/etc/passwd", "outside")
    print(out, filesystem.realpath(fs, "outside"))
    print(out, fs.read_text("link"))
    return 0
```

`fs.link_path(target, path)` and `filesystem.link(fs, target, path)` create the hard link `path` to the existing file `target`
(`link(2)`, written target first as `ln TARGET LINK` and `symlink` take it): a second name for one file. The two names are
equal. They share the bytes, the permission bits, the times and the inode, so a write through either is read through the
other, `Stat.inode` is the same for both and `Stat.links` reads 2 for both; removing one name leaves the other with the file
and a count of 1, and a publication over one name (`atomic_write_file`, `replace_file` and the rest rename a new file over
it) makes that name a new file and ends the sharing, as on disk. A program that restores an archive makes a member that is
a second name for an earlier one with this call, and a program that wants a name to survive a rewrite of another uses it
instead of a copy.

Each of the two paths is resolved as `symlink` resolves its own ("How a path is read" above), and the call writes both: the
directory that holds the new name gets an entry, and the file gets a name it can be reached by, so a program that may only
read a file can never link it into a place it can write (it would then write the file). Under `--restrict` both paths
must fall inside write grants, the same grant or two, and two grants on different disks answer `the paths are on different
filesystems`. On a handle narrowed by `fs.dir` or `filesystem.dir_at` both stay inside its folder (no `..`, `.`, leading `/`
or empty part), and `fs.read_only()` refuses the call. No link is followed on the way to either name or at the end of
`target`. `target` must be a regular file: a folder fails with `is a directory`, a symbolic link (even one that names a
regular file) with `is a symbolic link the sandbox does not follow, or links nest too deeply`, and a pipe, socket or device
with `is not a regular file`, so the call cannot name a folder twice or reach through a link. A `path` that is taken fails with
`already exists` and one in a folder that does not exist with `the path does not exist`. A failure names both ends, as a
rename's does: `link 'TARGET' to 'PATH': REASON`.

| Root | `link(fs, target, path)` |
| --- | --- |
| no restriction | the paths are read as a process reads them (a link on the way is followed, `..` and an absolute path are accepted); the source is never a link or a folder |
| `--restrict` write grants (`--allow-write`) | each path must fall inside a write grant (an absolute one too); a path outside every grant fails with `denied: 'RESOLVED' is outside the granted directories`, one inside a read-only grant with `denied: writing needs a write grant (--allow-write); 'RESOLVED' is granted for reading only`; a link on the way or at the end is refused |
| a directory narrowed with `fs.dir(...)` | both paths inside its folder under its own rule, in any run; a link on the way fails with `a parent of the path is not a directory` |
| `fs.read_only()` | `denied: this Filesystem was narrowed by fs.read_only() and does not write` |
| `filesystem.memory()` | the same as a grant, with one shared file ([below](#the-durable-calls-on-a-tests-filesystem)) |

```selka
# doc: expect Ok(None) 2 2 True
# doc: expect Ok('through the second name') 1
# doc: expect Err("link 'shared' to 'folder': is a directory")
# doc: expect Err("link 'ln' to 'again': is a symbolic link the sandbox does not follow, or links nest too deeply")
# doc: expect Err("link 'data' to 'second': already exists")
import filesystem

func links(fs: Filesystem, path: str) -> int:
    match filesystem.stat(fs, path):
        case Ok(info):
            return info.links
        case Err(_):
            return -1

func same_file(fs: Filesystem, first: str, second: str) -> bool:
    match filesystem.stat(fs, first):
        case Ok(a):
            match filesystem.stat(fs, second):
                case Ok(b):
                    return a.inode == b.inode
                case Err(_):
                    return False
        case Err(_):
            return False

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("shared")
    _ = fs.write_text("data", "payload")
    print(out, filesystem.link(fs, "data", "second"), links(fs, "data"), links(fs, "second"), same_file(fs, "data", "second"))
    _ = fs.write_text("second", "through the second name")
    _ = fs.remove("data")
    print(out, fs.read_text("second"), links(fs, "second"))
    _ = filesystem.symlink(fs, "second", "ln")
    print(out, filesystem.link(fs, "shared", "folder"))
    print(out, filesystem.link(fs, "ln", "again"))
    _ = fs.write_text("data", "x")
    print(out, filesystem.link(fs, "data", "second"))
    return 0
```

`fs.mkdir_mode(path, mode)` and `filesystem.mkdir_mode(fs, path, mode)` create the folder `path` with the permission bits `mode`
(`0` to `0o7777`; anything else fails with `the mode must be between 0 and 0o7777`), as `mkdir(2)` takes them. The folder has
that mode from the moment it exists. `fs.mkdir(path)` followed by `chmod` does not: the folder is first made with the default
mode (`0o775` under the usual umask) and is open to every member of the group until the `chmod` runs, which a program
extracting an archive that records a folder `0o700` cannot accept (SP1-F-11). The process's umask narrows `mode` as it
narrows the mode of a file (`atomic_write_file_mode`), so `0o700` is `0o700` and `0o777` is `0o775` under `0o002`, and the
system keeps the nine permission bits and the sticky bit and leaves the set-user-ID and set-group-ID bits to `chmod`. A
program that wants a mode exactly, whatever the umask, makes the folder with an owner-only mode, fills it and then
sets the mode: a mode the umask would narrow is then never granted early, and a folder recorded `0o555` can be filled
before it stops being writable. The path is read as `fs.mkdir` reads it (a trailing slash names the folder to make), its
directory must exist and be both readable and writable, and a path that is taken fails with `already exists` and one in a
folder that does not exist with `the parent directory does not exist`; the failure reads `mkdir 'PATH': REASON`. The same
rules as `link` decide where the call may write: write grants, the folder of a narrowed handle, no link on the way, and a
refusal from `fs.read_only()`; a test's `memory()` filesystem stores the mode as given, since it has no umask.

```selka
# doc: expect Ok(None) 448 Ok(None)
# doc: expect 493 365 2
# doc: expect Err("mkdir 'tree': already exists")
import filesystem

func mode_of(fs: Filesystem, path: str) -> int:
    match filesystem.stat(fs, path):
        case Ok(info):
            return info.mode
        case Err(_):
            return -1

func links(fs: Filesystem, path: str) -> int:
    match filesystem.stat(fs, path):
        case Ok(info):
            return info.links
        case Err(_):
            return -1

# What an archive restore does: folders private while they fill, files and second names next, recorded modes last, folders deepest first.
func restore(fs: Filesystem) -> Unit fails str:
    _ = try filesystem.mkdir_mode(fs, "tree", 0o700)
    _ = try filesystem.mkdir_mode(fs, "tree/lib", 0o700)
    _ = try fs.write_text("tree/lib/data", "payload")
    _ = try filesystem.link(fs, "tree/lib/data", "tree/alias")
    _ = try filesystem.chmod(fs, "tree/lib", 0o555)
    _ = try filesystem.chmod(fs, "tree", 0o755)
    return

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    print(out, filesystem.mkdir_mode(fs, "private", 0o700), mode_of(fs, "private"), restore(fs))
    print(out, mode_of(fs, "tree"), mode_of(fs, "tree/lib"), links(fs, "tree/alias"))
    print(out, filesystem.mkdir_mode(fs, "tree", 0o700))
    return 0
```

`fs.create_mode(path, mode)` and `filesystem.create_mode(fs, path, mode)` are the counterpart for a file written in pieces
(SP1B-F-8): they open `path` for writing as `fs.open(path, "wb")` does, and a file they create has the permission bits `mode`
(`0` to `0o7777`) from the `open(2)` that makes it, as `creat(2)` takes them. `fs.open(path, "wb")` followed by `chmod` leaves
an archive member recorded `0o600` readable by the group for as long as it takes to fill. The umask narrows `mode` as it
narrows `mkdir_mode`'s. A file that already exists is what `fs.open(path, "wb")` makes of it: truncated to nothing, its
mode and owner kept (a program that wants the recorded mode on it too calls `chmod`, or removes the file first). The path
is read as every write reads one: under `--restrict` inside a write grant with no link followed, on a narrowed handle
inside its folder, refused by `fs.read_only()`; without a restriction a final link to an existing file is followed and a
pipe or a device is written, as `fs.open` does. A failure reads `open 'PATH': REASON`. The result is a `File` like the one
`fs.open(path, "wb")` gives, and `with fs.create_mode(path, mode) as f:` opens it as `with fs.open(...)` does. A test's
`memory()` filesystem gives a new file the mode as given.

```selka
# doc: expect Ok(384) Ok('payload') 384
# doc: expect Err("open 'missing/member.bin': a folder on the way does not exist")
import filesystem

func mode_of(fs: Filesystem, path: str) -> int:
    match filesystem.stat(fs, path):
        case Ok(info):
            return info.mode
        case Err(_):
            return -1

func extract(fs: Filesystem, path: str, data: bytes) -> int fails str:
    const f = try filesystem.create_mode(fs, path, 0o600)
    const filling = mode_of(fs, path)
    _ = f.write(data)
    _ = f.close()
    return filling

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    print(out, extract(fs, "member.bin", b"payload"), fs.read_text("member.bin"), mode_of(fs, "member.bin"))
    print(out, extract(fs, "missing/member.bin", b"payload"))
    return 0
```

`Stat` also carries `changed`, the status-change time (`ctime` of `stat(2)`), a sixth word of `stat_path`'s answer: the
nanosecond of the last change to the entry, a write, a rename, `chmod` or `set_modified`. It is the time a program cannot
set back: `set_modified_path` can give a rewritten file the modification time it had, and the kernel still moves
`changed`, which is why a tool that remembers a file by its identity compares it as well as the modification time.

`atomic_write_file` publishes with mode `0600`, because the private cache and journal writers rely on it.
`atomic_write_file_mode` is the same publication (a complete file or the previous one, never a partial) with the
temporary created with `mode`, so the file appears with those permissions, on a replacement too; the process umask
applies as it does to `open(2)`, so `0o666` becomes `0o664` under the common umask `0o002`.

`fs.read_link_path(path)` and `filesystem.read_link(fs, path)` answer the text stored in the symbolic link at `path`, exactly
as `symlink` stored it or `ln -s` wrote it, as `readlink(2)` does: relative or absolute, naming something or nothing, and
for a link to a link the text of the first link only. The link is never followed, so what it names is not looked at: a
dangling link, and a link whose target is outside the granted directory, are read like any other, because the text gives no
access to its target (a program that wants the target follows it with `realpath` or `stat_follow`, and meets their
confinement). The path is resolved as `stat_path` resolves it, on every kind of root, so `read_link` refuses what `stat`
refuses for the same path and nothing more:

| Root | `read_link(fs, path)` |
| --- | --- |
| no restriction | the links on the way to the final component are followed, an absolute path is accepted |
| `--restrict` grant (`--allow-read`, `--allow-write`) | the path must fall inside a grant (an absolute one too); a link on the way is refused (`is a symbolic link the sandbox does not follow, or links nest too deeply`); the final link is read |
| a directory narrowed with `fs.dir(...)` | the same as a grant, in any run, the narrowing's own prefix included; a link in the directory may name a target outside it |
| `fs.read_only()` | the same as the handle it narrows: reading a link needs read authority only |
| `filesystem.memory()` | the same as a grant, answered from the stand-in's links |

A `.` or `..` component means what it means to the system, as for every durable call, except on a handle narrowed by
`fs.dir` or `filesystem.dir_at`, which refuses it. An entry that is not a link (a file, a directory, the root `""`) fails with `read link 'PATH': is not a symbolic link`, a path with nothing at it, or under a directory that does not
exist, with `the path does not exist`, and a target that is not valid UTF-8 text with
`the bytes read are not valid UTF-8 text`. A link another program made may hold up to 4095 octets, which `read_link` reads
whole (`symlink` makes links of 1 to 4094).

```selka
# doc: expect Ok('shared/data') Ok('/etc/passwd') Ok('nowhere')
# doc: expect Err("read link 'shared/data': is not a symbolic link")
# doc: expect Err("read link 'missing': the path does not exist")
# doc: expect Err("read link 'shortcut/inside': is a symbolic link the sandbox does not follow, or links nest too deeply")
import filesystem

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("shared")
    _ = fs.write_text("shared/data", "payload")
    _ = filesystem.symlink(fs, "shared/data", "inside")
    _ = filesystem.symlink(fs, "/etc/passwd", "outside")
    _ = filesystem.symlink(fs, "nowhere", "dangling")
    _ = filesystem.symlink(fs, "shared", "shortcut")
    print(out, filesystem.read_link(fs, "inside"), filesystem.read_link(fs, "outside"), filesystem.read_link(fs, "dangling"))
    print(out, filesystem.read_link(fs, "shared/data"))
    print(out, filesystem.read_link(fs, "missing"))
    print(out, filesystem.read_link(fs, "shortcut/inside"))
    return 0
```

```selka
# doc: allow-read notes
# doc: expect True True
# doc: expect Err("realpath 'absent.txt': the path does not exist")
# doc: expect Err("realpath '/etc': denied: '/etc' is outside the granted directories")
# doc: expect True
# doc: expect True
import filesystem
import strings

func ends(result: Result[str, str], tail: str) -> bool:
    match result:
        case Ok(name):
            return strings.ends_with(name, tail)
        case Err(message):
            return strings.ends_with(message, tail)

func main(fs: Filesystem, out: Stream) -> int:
    print(out, ends(filesystem.cwd(fs), "/fixtures/notes"), ends(filesystem.realpath(fs, "greeting.txt"), "/notes/greeting.txt"))
    print(out, filesystem.realpath(fs, "absent.txt"))
    print(out, filesystem.realpath(fs, "/etc"))
    match filesystem.stat_follow(fs, "greeting.txt"):
        case Ok(info):
            print(out, info.size > 0 and info.mode > 0)
        case Err(_):
            print(out, "unexpected")
    match filesystem.chmod(fs, "greeting.txt", 0o600):
        case Ok(_):
            print(out, False)
        case Err(message):
            print(out, strings.ends_with(message, "/notes/greeting.txt' is granted for reading only"))
    return 0
```

Publishing a script that must be executable, then stamping it with a build time:

```selka
# doc: check
import filesystem

func install(fs: Filesystem, data: bytes, stamp: int) -> int fails str:
    _ = try fs.atomic_write_file_mode("run.sh", data, 0o755)
    _ = try filesystem.set_modified(fs, "run.sh", stamp)
    match filesystem.stat(fs, "run.sh"):
        case Ok(info):
            return info.mode
        case Err(_):
            return 0

func main(fs: Filesystem) -> int:
    match install(fs, b"#!/bin/sh\n", 1000000000):
        case Ok(mode):
            return mode
        case Err(_):
            return 0
```

### The durable calls on a test's filesystem

`filesystem.memory()`, and so the `fs: Filesystem` parameter of a test, answers every durable operation on this page
from its own entries: `atomic_write_file[_mode]`, `replace_file[_mode]`, `replace_file_synced[_mode]`, `rename_path`, `stat_path` and `stat_follow_path`, `sync_directory`,
`canonical_path`, `chmod_path`, `touch_path`, `set_modified_path`, `symlink_path`, `read_link_path`, `link_path`, `mkdir_mode`, `create_mode`, `read_regular_file`, `list_directory` and the three
locks. A test therefore runs the code a program ships, not a plain write standing in for the atomic one. The grants and
the path rules are the real ones (`fs.read_only()` refuses the writes, `fs.dir(path)` scopes the paths, a path is
relative and has no `.` or `..` component, and only the directory operations take the empty path for the root), and so
is the wording of a refusal. An embedding provider that cannot promise durability still refuses with `durable native
filesystem provider is unavailable`.

Everything is deterministic and needs no flag, so a test that uses these calls is cached like any other:

- **Modes and inodes.** A file is created `0644` and a directory `0755`; the root is a directory `0755` with inode 1.
  Inode numbers count up from 2 in the order entries are created. A rename keeps the inode, the mode and the time of
  what it moves; an `atomic_write_file` over a file is a new inode (a `File` that already holds the old file keeps
  reading it). There is no umask: a mode is stored exactly as given, so `fs.atomic_write_file_mode(path, data, 0o666)`
  is `0o666`, and `chmod` and `stat` round trip. The modes are honoured, too: see [permission bits on the in-memory
  filesystem](#permission-bits-on-the-in-memory-filesystem).
- **Times.** `Stat.modified` reads a logical clock that starts at 946684800 seconds (1 January 2000, the epoch of the
  test clock) and moves one second for each call that changes the filesystem: creating or truncating a file, the first
  write of an open `File`, `mkdir`, `remove`, `rename_path`, `atomic_write_file[_mode]`, `touch_path`, and the file a
  lock creates. The call stamps what it changed with the new reading: the file, and the directory that gained, lost or
  renamed an entry. `set_modified_path` stores the time it is given and `chmod_path` changes no modification time, so
  neither moves the clock, and a call that fails does not either. No test sleeps to make a file newer than another.
  `Stat.changed` is the same reading for a call that writes, and for `chmod_path` and `set_modified_path`, which leave the
  clock where it is, the nanosecond after the last change: it is later than every earlier change, so a file rewritten and
  given its old `modified` back still reads a newer `changed`.
- **Symbolic links** are entries `symlink_path` makes, holding their target text with mode `0777` and a size of that text's
  length; `Stat.kind` is `Symlink` for one. The rules are the granted directory's: `canonical_path` and `stat_follow_path`
  follow a link only while it stays inside the filesystem (an absolute target, or `..` past the root, fails with `resolves
  outside the granted directory`, more than 40 links in one walk with the link-nesting refusal, and a link to nothing is
  `Missing` to `stat_follow`), and every other call refuses a link on the way or a read, write or lock of one itself with the
  real wording; `read_link_path` answers the text of the link itself, a target outside the filesystem included, and says
  `is not a symbolic link` of any other entry. A listing names a link `Symlink`, `chmod_path` of one fails (`a symbolic link has no permission bits of its
  own`), `touch_path` and `set_modified_path` change it, and `remove` and `rename_path` move or unlink the link itself.
- **Hard links** are second entries for one file that `link_path` makes: they share the bytes, the mode, the times, the inode and the
  lock, so a write, a `chmod`, a `touch` or a lock through one name is seen through the other, `Stat.links` counts the names (and
  is 2 for both after one `link`), a removal or a rename of one name leaves the other, a rename of one onto another name of the
  same file does nothing, and a publication over one name makes it a new file. A handle that holds a removed name keeps the file
  and sees what the other name writes. A link changes the file's status time and its directory's modification time. The source
  must be a regular file (a folder is refused with `is a directory`, a symbolic link with the link wording); the new name must be
  free and in a directory the stand-in may write. `mkdir_mode` stores the nine permission bits and the sticky bit as given (there is
  no umask) and drops the set-user-ID and set-group-ID bits, as the system does; `create_mode` gives a new file the mode as given.
- **Listings** are sorted by name (the real provider answers in the system's order), and hidden names are included.
- **Locks** are held on the entry, as `flock` holds an inode, until the `File` that `lock_directory`, `lock_file` or
  `try_lock_file` returned is released: on `return`, on `fail`, when the `with` block falls through, and when a trap
  ends the test and the filesystem with it. `try_lock_file` and a second `lock_directory` on a held path fail with `: the
  lock is held by another holder` (`filesystem.is_lock_busy` is true). `lock_file` would wait for the holder, but a test
  has one thread to release it, so it fails at once with `: the lock is held (a stand-in cannot wait)`. A lock is
  advisory: it does not stop reads or writes, and `lock_file` creates a missing file with mode `0600`, as the real one
  does.

```selka
# doc: expect 946684801000000000 946684802000000000 True
# doc: expect Ok("try lock file 'store.lock': the lock is held by another holder")
import filesystem

func stamp(fs: Filesystem, path: str) -> int:
    match filesystem.stat(fs, path):
        case Ok(info):
            return info.modified
        case Err(_):
            return -1

func busy(fs: Filesystem) -> str fails str:
    with try fs.try_lock_file("store.lock") as lease:
        match fs.try_lock_file("store.lock"):
            case Ok(_):
                return "granted"
            case Err(message):
                return copy(message)

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.atomic_write_file("a", b"1")
    _ = fs.atomic_write_file("b", b"2")
    print(out, stamp(fs, "a"), stamp(fs, "b"), stamp(fs, "b") > stamp(fs, "a"))
    print(out, busy(fs))
    return 0
```

### Permission bits on the in-memory filesystem

`filesystem.memory()`, and so a test's `fs`, keeps a mode for every entry (`0644` for a file and `0755` for a directory unless
`chmod_path` or a `_mode` publication set another) and honours it: the stand-in acts as an ordinary user who owns every entry, so
the **owner** bits of the mode decide, the way they do on disk for any user but a privileged one (which passes every check, and
which a test never is). Group and other bits, the set-user-ID, set-group-ID and sticky bits and the owner of an entry play no part.
A call that the bits forbid fails with the real provider's words, `permission denied` in the message of the call, and changes
nothing. Three bits are asked for:

- **read** (`4`): of a file, to read it; of a directory, to list it, or to open it for reading;
- **write** (`2`): of a file, to write into it in place; of a directory, to add, remove or rename one of its entries;
- **search** (`1`): of every directory above the path, so no path goes through a directory without it.

| Call | Search | Then it needs |
| --- | --- | --- |
| `read_file`, `read_text`, `open(path, "r")` | every directory above | read of the file |
| `read_regular_file`, `read_at` | every directory above | read of the file, read of its directory |
| `write_file`, `write_text`, `open(path, "w")` and `"a"` of an existing file | every directory above | write of the file |
| the same of a file that does not exist yet | every directory above | write of its directory |
| `mkdir` | every directory above | write of its directory |
| `remove` of a file or an empty directory | every directory above | write of its directory |
| `atomic_write_file[_mode]`, `replace_file[_mode]`, `replace_file_synced[_mode]` | every directory above | read and write of its directory (never the destination's own mode) |
| `symlink_path` | every directory above | read and write of its directory |
| `link_path` | every directory above both paths | read and write of both directories (the source file's own mode is not asked) |
| `mkdir_mode` | every directory above | read and write of its directory (`mkdir` asks for the write bit alone) |
| `create_mode` | every directory above | write of an existing file, or write of its directory for a new one; read of its directory |
| `rename_path` | every directory above both paths | read and write of both directories; write of a moved directory that changes parent |
| `lock_file`, `try_lock_file` | every directory above | read and write of an existing file, or write of its directory for a new one; read of its directory |
| `lock_directory`, `sync_directory` | every directory above | read of the directory, and read of the directory that holds it |
| `listdir`, `list_directory`, `list_entries` | every directory above | read of the directory |
| `chmod_path`, `touch_path`, `set_modified_path` | every directory above | read of its directory |
| `stat_path`, `stat_follow_path`, `statfs_path`, `read_link_path`, `canonical_path`, `exists` | every directory above | nothing |

Some details follow the real provider, not what `chmod` suggests. A creation in a directory without the write bit fails with
`permission denied` for every call (`write_file`, `write_text` and `open(path, "w")` try to create the file and then to open an
existing one; when both find nothing, the answer is the first one's reason). A durable call that creates, removes or renames needs the read bit of the directory as well as the write bit,
because the real provider opens that directory for reading to reach the path, and `chmod_path`, `touch_path` and
`set_modified_path` need that read bit too; `exists` of a path the search bit hides is `False`. A read-only file in a writable
directory is replaced by a publication (the new file is renamed over it) and refuses an in-place write, as on disk, so the way
to make an install fail in a test is a directory without the write bit. A stat of a directory itself needs nothing of the
directory, only of those above it. An open file keeps working when `chmod` changes its mode afterwards, as on disk.

The table is pinned against a real directory: `test/fs_permissions_cli_test.zig` runs one program of about 490 calls on a real
directory and on `filesystem.memory()` and requires both to print the same file, `test/fixtures/fs-permissions/expected.txt`.

```selka
# doc: expect replace refused: replace 'lib/binary': permission denied
# doc: expect write refused: write 'lib/new': permission denied
# doc: expect read-only file: write refused write 'lib/binary': permission denied True
import filesystem

func main(out: Stream) -> int:
    const fs = filesystem.memory()
    _ = fs.mkdir("lib")
    _ = fs.write_file("lib/binary", b"old")
    _ = filesystem.chmod(fs, "lib", 0o555)
    match fs.replace_file_synced_mode("lib/binary", b"new", 0o755):
        case Ok(_):
            print(out, "replaced")
        case Err(message):
            print(out, "replace refused:", message)
    match fs.write_file("lib/new", b"x"):
        case Ok(_):
            print(out, "written")
        case Err(message):
            print(out, "write refused:", message)
    _ = filesystem.chmod(fs, "lib", 0o755)
    _ = filesystem.chmod(fs, "lib/binary", 0o444)
    mut refused = "no"
    match fs.write_file("lib/binary", b"new"):
        case Ok(_):
            pass
        case Err(message):
            refused = copy(message)
    print(out, "read-only file: write refused", refused, fs.read_file("lib/binary") == Ok(b"old"))
    return 0
```
