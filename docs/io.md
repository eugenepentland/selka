# Printing, files and command-line authority

`print`, files, the clock and the command line are how a program meets the outside world. Printing needs no grant.
Everything else is a capability that `main` names as a parameter, and `selka run` grants all of them unless you pass
`--restrict`.

## print

```selka
# doc: expect hello 42 True None
# doc: expect ['a', 'b'] {'k': 1} b'\x00\xff'
func main(out: Stream) -> int:
    print(out, "hello", 42, True, ())
    print(out, ["a", "b"], {"k": 1}, b"\x00\xff")
    return 0
```

Arguments are separated by single spaces and followed by one newline; `sep=` and `end=` replace either and take any `str`:

```selka
# doc: expect 1-2-3!
func main(out: Stream) -> int:
    print(out, 1, 2, 3, sep="-", end="!\n")
    return 0
```

Values print the way Python spells them: `str` raw at the top level and `repr`-quoted inside a container, `bytes` as
`b'...'`, a `float` with its `.0`, records as `Name(field=value)`, enum and union cases as `Name.case`, results and options as
`Ok(...)`, `Err(...)`, `Some(...)` and `None`. Sets and dictionaries print in insertion order; nesting deeper than 24
levels prints `...`. `str(x)`, `repr(x)` and a format-string hole give the same text
([the text of a collection](text.md#the-text-of-a-collection)).

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

Capabilities, open files and callbacks have no text, nor has a value that holds one: `print(out, [stream])` is
`E_IO_ARGUMENT` at the check.

```selka
# doc: expect-error E_IO_ARGUMENT
func twice(n: int) -> int:
    return n * 2

func main(out: Stream) -> int:
    print(out, [twice])
    return 0
```

| Python habit | Selka |
| --- | --- |
| `print("x")`, `eprint("x")` | `E_OUTPUT_CAPABILITY`: add `out: Stream` and pass one from `main` (`debug(...)` needs none) |
| a `noio` clause | `E_EFFECTS_REMOVED` |

```selka
# doc: expect-error E_OUTPUT_CAPABILITY
func main() -> int:
    print("no stream")
    return 0
```

`print(err, …)` writes standard error only. For a program's own messages (level, time, fields) use
[`logging`](logging.md) (`selka docs logging`).

## Format strings

An f-string passed to `print` or `write` is written piece by piece, so it allocates nothing when its holes hold an integer,
`float`, `bool`, `str` or `bytes`. Used as a `str`, it makes one allocation.

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

`write(out, data)` writes bytes (NUL and non-UTF-8 octets included) with no quotes or newline and answers unit; a `str` is
written as UTF-8. `write(out, data[a:b])` writes a window of a `bytes` with no copy; `write(out, buffer)` writes what a
`byte_buffer` holds now.

```selka
# doc: expect world! 5
func main(out: Stream) -> int:
    const line = b"hello world\n"
    write(out, line[6:11])
    print(out, "!", len(line[6:11]))
    return 0
```

`Stream` is a capability: `main` declares the standard streams it wants (`out`, `err`) and a helper takes any `Stream`.
Streams are granted unconditionally, so `--restrict` cannot take standard output away.

```selka
# doc: check
func main(out: Stream, err: Stream) -> int:
    print(out, "result:", 42)
    print(err, "note", sep=": ")
    write(out, "raw")
    return 0
```

A `Stream` in a record field is used as the field (`print(ctx.err, "note")`, `flush(self.log.stream)`); a field that holds no
`Stream` is `E_OUTPUT_CAPABILITY`.

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

When a write or flush fails:

| Failure | Standard output | Standard error |
| --- | --- | --- |
| the reader has gone (`prog \| head -5`), `EPIPE` | ends the program quietly, status 141 | the same |
| a full device (`> /dev/full`), a closed descriptor (`>&-`) | traps `R_OUTPUT`, status 1 | ignored: the line is lost |

A test's streams are captured and never fail, and neither does `streams.memory()`. A file on a
FIFO whose reader has gone traps `R_FILE`; a write to a closed socket is an error result.

### Passing the stream as the first argument

`print(out, values..., sep=, end=)`, `write(out, data)` and `flush(out)` take a name, or a field of a name, that holds a
`Stream`, and answer unit.

Output is buffered: it reaches the descriptor at `flush(out)`, when the buffer fills, or when the program ends (a trap
flushes standard output first). Standard error is unbuffered. The runtime also flushes standard output before the program
waits for something outside it (a poller wait, a blocking read or connect, `process.run`, `time.sleep`), so a service's log
shows each line. A program that computes for long between prints holds its output until it waits or ends: call `flush(out)`
for a line that must not wait.

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

## debug

`debug(values...)` writes to standard error without a capability, rendered like `print`. A debug build, `selka run`,
`build --run` and `selka test` write it; a `selka build --release` executable writes nothing but still evaluates every
argument in order, so a program means the same in every build mode. A generic function may call it (`print` is not supported
in a generic body); a type that cannot be rendered, such as a capability, is refused where the instance is checked.

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

`selka run` does not print the entry's `int` result; `--print-result` writes it after the output:

```text
$ selka run hello.selka
hello
$ selka run hello.selka --print-result
hello
0
```

The `int` result is the process exit status, truncated to the low 8 bits (`Ok(300)` exits 44), with or without
`--print-result`; a runtime trap exits 1. `run-project` and a native executable follow the same rule. An entry may return
`Result[int, E]`: `Ok(code)` as above; `Err(message)` writes `error: message` and the
[return trace](results-and-options.md#error-return-traces) to standard error and exits 1 (an `int` error is the status).

## Runtime diagnostics

A native trap keeps its code, location, call stack and omitted frame count. Bounds failures add the index and length;
division and checked overflow add the operands and width. `selka run` prints this detail, and with `--diagnostics json` puts
it under `trap_detail`. Traps with no detail (step and memory budgets, capability and host failures) omit the field.

```text
example.selka:2:12: error[R_LIST_BOUNDS]: native execution failed (index 14, length 1)
```

## Arguments

A `main(args: str[], ...)` entry point receives guest arguments as data, never authority. `selka run` and `build --run` keep
their own options before `--` and pass every value after it, in order, with no program name. An installed executable passes
every OS argument after `argv[0]` unchanged, because it reads its options from `SELKA_OPTIONS`
([the native backend](#the-native-backend)). Arguments are validated as Unicode first.

```console
$ selka run report.selka -- --format=json "two words" ""
```

```selka
# doc: expect count 0
func main(args: str[], out: Stream) -> int:
    print(out, "count", len(args))
    return 0
```

## Standard input

A parameter of type `Input` reads standard input; the type selects the stream, so the name is free (`stdin: Input`). It is
granted like `Stream`, `--restrict` cannot take it away, and a `main` may declare at most one. Every read blocks; a read the
operating system refuses, or a negative size, traps `R_INPUT`.

| Method | Answers |
| --- | --- |
| `stdin.read(max: int) -> bytes` | up to `max` octets after at most one wait; `b""` at the end |
| `stdin.read_exact(n: int) -> bytes?` | exactly `n` octets, or `None` when the input ends first (what it read is consumed) |
| `stdin.read_line() -> bytes?` | through the next `\n` (kept, with a carriage return before it), the final unterminated line, or `None` |
| `stdin.read_into(mut buffer: byte_buffer, max: int) -> int` | appends one `read(max)` to a named `mut` buffer and counts it, 0 at the end |

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

A test function that declares an `Input` is handed an empty one; `streams.input_from(data)` builds an in-memory input over
`bytes`, read once in order, so the same helpers run in a test:

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

## Capabilities

`main` declares the authority it needs by parameter type: `Filesystem`, `Network`, `Clock`, `Entropy`, `Environment`,
`Process` ([below](#processes)) and `Stop` ([hearing a stop](#hearing-a-stop)). They are the Python spellings of
`filesystem_cap`, `network_cap`, `clock_cap`, `random_cap` and `environment_cap`, and resolve only when no declared or
imported type claims the name.

`selka run` and `run-project` grant every capability by default: the filesystem with no restriction (relative paths against
the working directory, absolute paths as they are), clock, entropy, the whole environment and starting programs. `--restrict`
switches to deny-by-default, and only then do these flags narrow anything:

| Flag | Grant under `--restrict` |
| --- | --- |
| `--allow-read=DIR` | read the tree at `DIR` (repeatable, up to eight) |
| `--allow-write=DIR` | read and write that tree: create, truncate, `mkdir`, `remove` |
| `--allow-clock` | wall-clock time (`time.now`); a `Clock` without it still starts, reads `time.monotonic` and sleeps |
| `--allow-random[=SEED]` | a pseudorandom stream, reproducible with `SEED` |
| `--allow-env[=NAME,...]` | the environment, restricted to the named variables |
| `--allow-process` | start programs (the `Process` capability) |
| `--allow-endpoint=IP:PORT` | connect to that endpoint (repeatable, up to eight) |
| `--allow-listen=IP:PORT` | listen on that endpoint (repeatable, up to eight) |
| `--allow-all` | clock, entropy, all environment names, processes, every endpoint and listener, read/write on the working directory |

Without `--restrict` the flags are accepted and narrow nothing, except `--allow-random=SEED`, which pins the seed in either
mode (an unseeded stream is seeded from the wall clock). Under `--restrict`, a `main` that requests an ungranted capability
fails before its first instruction:

```text
$ selka run report.selka --restrict
selka: --restrict is active and this command line did not grant a capability the entry point requests; pass --allow-read=DIR or --allow-write=DIR, or drop --restrict to grant every capability; or, if the program can run without it, declare the parameter optional (`fs: Filesystem?`)
```

Write the parameter `T?` to start anyway ([next section](#capabilities-a-program-may-go-without)). Under `--restrict`
without `--allow-clock`, `time.now(clock)` fails with "the wall clock is not granted: pass `--allow-clock`".

**Neither mode is a sandbox.** The providers run inside the compiler process and the host tree is trusted; directory scoping
does not tell hard links to one inode apart. A started program runs with the caller's authority, so `--allow-process` takes no
list of programs. `--restrict` says what a program may reach; it is not containment.

### Network grants

Connect (`--allow-endpoint`) and listen (`--allow-listen`) grants are separate. Each names one IPv4 literal and a port,
reached through `net.host("IP:PORT")` with the same literal or through an operation given the same text at run time
(`network.connect_to`, `listen_at`, `open_poller_at`, `dial_to`); the match is verbatim
([the network host](effects.md#network-host), [addresses given at run time](standard-library.md#addresses-given-at-run-time)).

- A pattern (`127.0.0.1:*`), a host name or an IPv6 address stops the launch with exit 2; so does port 0 for
  `--allow-endpoint` (dialling it reaches nothing). A port with a sign, a space or anything after its digits is malformed.
- `--allow-listen=127.0.0.1:0` grants only `127.0.0.1:0`, a kernel-chosen port that a `Poller` reports with `network.port`;
  it does not permit `127.0.0.1:8080`, and a `:8080` grant does not permit port 0.
- `*` in place of the address grants every endpoint or listener (each `*` counts toward the eight); `--allow-all` grants both.
- A program that only connects out opens its `Poller` with `network.open_client_poller(net)`, which needs no
  `--allow-listen`; a dial to an address no `--allow-endpoint` names is `OUTCOME_DENIED` with 2.
- An endpoint outside the grants gives `Connected.err` or `Polling.err` code 2 ("denied: outside the granted endpoints"); a
  kind of use with no grant of that kind at all gives code 1 ("no network authority is available").

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

Run with `--restrict --allow-listen=127.0.0.1:0`, the `:0` listener is granted (digit 1) and `:8080` refused (code 2). Run
with `--allow-endpoint=127.0.0.1:1`, the granted endpoint is tried and nothing listens (code 3), its neighbour is refused
(code 2).

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

### Capabilities a program may go without

Write an entry parameter `T?` (`fs: Filesystem?`, `net: Network?`, `clock: Clock?`, `rng: Entropy?`, `env: Environment?`,
`proc: Process?`, `host: Host?`) and the program always starts: the parameter is `Some` when the command line grants anything
of that capability, `None` when `--restrict` grants none of it (`Filesystem?` counts `--allow-read` and `--allow-write`,
`Network?` the two network flags, `Clock?` only `--allow-clock`). Without `--restrict` every one is `Some`, and a `Some` holds
what the plain `T` would. `Stream?`, `Input?` and `Stop?` are `E_MAIN`.

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

### Records that hold capabilities

A capability is a shareable handle, like `Stream`: copy it, store it in a record, list, dictionary, option or union, pass and
return it, with no `own`. Copies share their provider. A task cannot take one
([concurrency](concurrency.md#tasks-take-values)).

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

A copy keeps the grants of its source. A narrowing (`fs.dir(path)`, `fs.read_only()`, `net.host(endpoint)`, `env.only(...)`)
answers a new, narrower handle that a `with` may bind or a `const` may hold. For a `Filesystem`:

- `fs.dir(path)` follows no symbolic link in any run, with or without `--restrict` (the unnarrowed handle of an unrestricted
  run still does): a link on the way, at the end or in its own prefix is refused.
- A path on a `fs.dir` or `filesystem.dir_at` handle stays relative to its folder: `..`, `.`, an empty part and an absolute
  path are refused. A backslash is an ordinary byte of a name.
- `fs.read_only()` narrows what a handle may do, not which paths it may name: it refuses every write and reads as the handle
  it narrows does ([How a path is read](#how-a-path-is-read)).

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

`own` on a capability is the warning `W_CAPABILITY_OWN` (the marker transfers nothing); a `mut` capability parameter that the
function never assigns or passes on as `mut` is `W_CAPABILITY_MUT`. `selka fix` removes both, and the `mut` that call sites
then carry (`E_MUTATION_MARKER`). The state behind a handle lives until the process or test ends.

#### A folder named at run time: `filesystem.dir_at`

`fs.dir` takes only a literal. `filesystem.dir_at(fs, path) -> Filesystem fails str` narrows to a folder the program learns at
run time and returns a `fs.dir` handle; narrowing only removes access.

1. **What may be named.** Any existing folder `fs` reaches, with `path` read as `fs` reads one
   ([How a path is read](#how-a-path-is-read); a narrowed handle by its own rule). An empty path is refused: `.` names the
   working directory.
2. **No symbolic link** in any component, in every run.
3. **What it returns** is what `fs.dir` gives: `..`, `.`, an empty part, an absolute path and a link are refused on it; it
   reads only when `fs` does and, under `--restrict`, writes only inside a write grant. It keeps the folder's name, so a link
   made later, or the folder replaced by one, is refused at that call. `canonical_path` and `filesystem.cwd` answer relative
   to the folder, `""` for the folder itself.
4. **Failures** read `dir_at 'PATH': REASON`: the refusal of `filesystem.stat` of the path, `is not a directory`, or `is a
   symbolic link the sandbox does not follow`.
5. **The folder itself** is `""`, not `"."`: `handle.exists("")`, `filesystem.stat(handle, "")` and
   `filesystem.list_entries(handle, "")` answer for it. A path with a `.` or an empty part, or ending in a slash, is refused;
   write `notes.txt` and `sub/notes.txt`. `exists` answers `False` for a refused path. The parent has no name; narrow
   further with `filesystem.dir_at(handle, "sub")`.

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

## Hearing a stop

Declare a `Stop` on `main`, and SIGTERM (`systemctl stop`, `kill`, `process.stop`) and SIGINT (Ctrl-C) turn
`process.stop_requested(stop)` true instead of ending the program, so a loop on it can say goodbye and return:

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

- **Who gets it.** Only a program whose `main` declares a `Stop` (at most one). Without one, SIGTERM ends the program as
  always (status 143, 130 for SIGINT). It needs no grant, and `--restrict` keeps it.
- **SIGHUP is not a stop**, and a signal ignored at start stays ignored.
- **The second signal.** After the first stop, the next SIGTERM or SIGINT ends the program, unless it is the same signal from
  the same sender within half a second, which counts as the same stop.
- **A `Stop` is a handle**: copy it or keep it in a record; every copy reads one flag. A task cannot take one
  (`E_TASK_CAPABILITY`): ask `stop_requested` before each group, or pass the task the answer as a `bool`.

A stop not yet read ends the next `network.wait` of each poller (it returns at once, usually with nothing: ask
`stop_requested`) and the next `time.sleep` on the real clock early, once each; once read, every wait lasts as long as it
asks, so a goodbye can wait for its clients. Every other wait (a blocking read or accept, `connect`, standard input, a
`durable` lease, `process.run`, `wait`, `wait_within`) resumes with its own limit unchanged (`read_ms`, `connect_ms`), and a
`parallel` join or task is not interrupted.

A test's `Stop` is a stand-in no signal reaches: `process.simulated_stop()` makes another and `process.request_stop(stop)`
delivers the notice. `network.memory()` has no poller, so a test drives a serve loop's turn and goodbye functions itself:

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

On a real `Stop`, `request_stop` is the program asking itself to stop; it is not a signal.

## Register access

A `Registers` is the authority to read and write hardware registers (`import registers`): `registers.read32(reg, address)`,
`registers.write32(reg, address, value)` and the 8- and 16-bit forms. It is a shareable handle; a task cannot take one
(`E_TASK_CAPABILITY`), and `print`, `str` and a format hole refuse it.

On a device target (`selka build --target thumbv6m-none`, [the native build guide](tooling/native-build.md)) `main` is handed
one, `func main(reg: Registers) -> int`, and each read or write is one volatile access in program order. A Linux build refuses
that `main` with `E_TARGET_CAPABILITY`; a device build refuses the functions only a simulated bank has (`simulated`,
`poke32`, `script32`, `pin32`, the log readers) with `E_TARGET_SIMULATED_REGISTERS`. The processor's own instructions are
[the `cpu` module](standard-library.md#cpu). A test makes a bank with `registers.simulated()`:

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

`registers.script32(reg, address, values)` makes the next reads of a word answer `values` in order; `registers.pin32(reg,
address, mask, value)` makes the bits of `mask` always read as `value`'s (a read-only lock bit):

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

A simulated bank holds 4,096 words and logs 16,384 writes; past either it traps `R_REGISTER_BANK`
([standard library guide](standard-library.md#registers)).

`registers.start_core1(reg, entry)` runs `entry`, a top-level `func(Registers) -> int`, on core 1 with its own `Registers`,
stack and heap; it answers `False` on a one-core platform or when core 1 already started. The cores share no heap value
(they talk through the hardware, such as the `rp2040` package's `sio` module). A host build refuses it with
`E_TARGET_DEVICE_REGISTERS`; the rest is in
[the native build guide](tooling/native-build.md#the-second-core-registersstart_core1).

## Environment

An `Environment` parameter gives `env.get(name) -> Option[str]`: `Some(value)` (UTF-8) for a present name, `None` otherwise,
also for a name that is empty, holds NUL or `=`, or is over 255 octets. A name outside the active `--allow-env` list or
`env.only` scope traps. `env.only("HOME", "PATH")` narrows to the listed literal names; `env.names()` returns every visible
name, sorted (a fixed stand-in holds at most 64). `selka run` and installed executables grant the whole environment; under `--restrict`,
`--allow-env[=NAME,...]` selects the names.

```selka
# doc: check
func main(env: Environment) -> int:
    mut home = env.get("HOME")
    with env.only("HOME") as narrowed:
        _ = home
        _ = narrowed
        return len(env.names())
```

## Processes

A `main(proc: Process, ...)` entry point may start programs. `selka run` and installed executables grant it; under
`--restrict` it needs `--allow-process`, else the program refuses to start (`pass --allow-process`, exit 2).

`process.run(proc, request)` runs a program to completion and answers an `Output`: `exited` (status in `code`, or the signal
number), the octets written to standard output and standard error, and whether either was cut at the `limit`. Use the typed
[`process`](standard-library.md#process) module; the builtin `run_process(proc, request, limit)` takes packed octets (the
[`binary`](standard-library.md#binary) format).

- There is no shell: a request is the program and its arguments as a list, the program a path or a name searched on `PATH`.
  An empty working directory keeps the caller's. A request may carry input octets and, as `Some([...])`, exactly the child's
  environment.
- A program that is not there is `Error.NotFound(program)`; any other refusal is `Error.Failed(message)`.
- Output is read while input is written, so a child that fills its output first does not stall; output past the limit is
  dropped and `truncated` says so.
- The child gets the caller's environment, directory and resource limits, except `RLIMIT_AS`: that is the limit the Selka
  program started with, not the `--max-memory` ceiling. The call has no timeout of its own: run under `timeout(1)`, or start
  the program and wait with a limit.
- `run_process` and `process.run` are refused in a generic function body. `process.executable_path(proc)` answers the
  absolute path of the running program.

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

### Starting a program without waiting

`process.start(proc, request, stdout_path, stderr_path)` returns at once with a `process.Child`: a server a test talks to. The
program's standard input is `/dev/null` (`request.input` must be empty); its output goes to the named files (emptied at
start; one path for both keeps their order) or to `/dev/null` for `None`. A path is relative to the caller's working
directory. A missing program fails `Error.NotFound`.

```text
# doc: not-selka
start(proc, request, stdout_path: str?, stderr_path: str?) -> Child fails Error
pid(mut child) -> int                                     SIGHUP SIGINT SIGQUIT SIGKILL SIGUSR1 SIGUSR2 SIGTERM SIGCONT SIGSTOP
signal(proc, mut child, number: int) -> Unit fails Error  # 1 to 64; nothing is sent once a wait has seen the end
wait_within(proc, mut child, millis: int) -> Output? fails Error   # None: still running; 0 asks without waiting
wait(proc, own child) -> Output fails Error               # as long as it takes; ends the Child
stop(proc, own child, grace_millis: int) -> Output fails Error     # SIGTERM, the grace, then SIGKILL; ends the Child
```

A wait's `Output` says how the program ended (`exited`, `code`); `stdout` and `stderr` are empty. A `Child` is a
[sealed](records-and-unions.md#sealed-records) [`@linear`](records-and-unions.md#linear-records) record: only `start` makes
one, and every path ends it exactly once, by `wait` or `stop`. You cannot forget, copy or list one; a function that only reads
one takes it `mut`, and `child.pid` reads its number. `on fail: _ = process.stop(proc, own child, 2000)` ends it on every
later failure exit. `wait_within` may repeat; once it has seen the end it answers the same at once. Only a program this
program started can be signalled or waited for, through its Child. A program that ends while a Child is live takes its started
programs with it (`PR_SET_PDEATHSIG`).

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

`process.start_to(proc, request, stdout, stderr)` is `start` with a `process.Destination` per stream: `Discard`
(`/dev/null`), `File(path)` (emptied at start) or `Caller`, which writes straight to this program's own standard output or
standard error while it runs, as a shell does.

```text
# doc: not-selka
start_to(proc, request, stdout: Destination, stderr: Destination) -> Child fails Error
enum Destination: Discard | File(path: str) | Caller      # start(proc, request, a, b) is File(a) or Discard, File(b) or Discard
```

- **Order.** What the caller printed so far is flushed before the program starts. What it prints while the program runs goes
  out as usual, so print a line that must not wait before the start or after the wait, or follow it with `flush(out)`.
- **Authority.** `Caller` is the caller's descriptors 1 and 2; `--restrict` changes nothing about destinations, and starting
  still needs `--allow-process`. In a test nothing starts and the destinations are ignored.

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

A `process.Child` is linear, so no list can hold one. A `process.Group` is one linear owner for as many started programs as
the system allows: `make -j` is the shape (start up to N, wait for whichever ends first, start the next).

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

- **Keys.** `group_start` answers a key: 0 for the first program, then 1, 2 and so on, never reused, so a caller keeps its own
  table from key to job. A start that fails leaves the group as it was.
- **Waiting.** `group_wait_any` answers the key and outcome of the first program to end, and that program leaves the group. A
  `Stop` does not wake it: a loop that wants to hear one waits with `group_wait_any_within` and a short limit. Waiting on an
  empty group fails.
- **Process groups.** Each program leads a process group, so `group_signal`, `group_stop` and `group_close` reach what it
  started too. Programs do not hear the terminal's Ctrl-C: a caller that declares a `Stop` hears it and stops the group.
- **Stopping and closing.** `group_stop` sends `SIGTERM` to every program's group, waits `grace_millis`, sends `SIGKILL` and
  reaps each. `group_close` does that and ends the group: **a group closed with programs running stops them.** A `Group` is
  `@sealed` and `@linear`, so `on fail: _ = process.group_close(proc, own jobs, 2000)` after `group()` closes it on every
  later failure exit. A program that ends without closing takes its started programs with it (`PR_SET_PDEATHSIG`).
- **In a test** a scripted Process starts nothing: `group_start` logs and answers from the rules, the program has already
  ended, and waits answer in start order.

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

A test never starts a program. A `proc: Process` parameter of a test, and `process.scripted(rules)` anywhere, is a **scripted
Process**: it needs no grant, starts nothing, and `process.run` on it logs the request and answers from a list of rules:

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

- A rule **covers** a request when `program` equals the request's `argv[0]` and, if `args` is `Some(prefix)`, the arguments
  begin with `prefix`. `times` is how many requests the rule answers (`None`: no limit).
- The **first covering rule** answers; a request nothing covers fails
  `Error.Failed("scripted Process has no rule for ['git', 'status']")`. `Reply.Exit` answers its `Output`, `Reply.Missing`
  fails `Error.NotFound`, `Reply.Refused` fails `Error.Failed` with its message.
- Every request is logged, answered or not: `process.calls(proc)` returns them, oldest first; `process.expect(proc, rule)`
  adds a rule. Both trap `R_ASSERT` on a real Process. `process.executable_path(proc)` answers
  `process.SCRIPTED_EXECUTABLE_PATH`.
- `process.start` on a scripted Process logs the request and the rule answers as for `run`: the `Child` has already ended with
  that `Output`, its `pid` is `process.SCRIPTED_PID` (0), and no output file is written.

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

Data that never changes between runs needs no capability: [`embed_bytes("path")` and
`embed_str("path")`](bytes.md#embedding-a-file-at-compile-time) store a project file in the executable at compile time.
Everything else is a method of the `Filesystem` capability: `fs.read_text(path)`. The free spelling `read_text(fs, path)` is
`E_REMOVED_SPELLING`; `selka fix` writes the method.

```selka
# doc: allow-read notes
# doc: expect Ok('hello from a granted directory\n')
# doc: expect True False
func main(fs: Filesystem, out: Stream) -> int:
    print(out, fs.read_text("greeting.txt"))
    print(out, fs.exists("greeting.txt"), fs.exists("absent.txt"))
    return 0
```

The whole-path methods are `fs.read_file(path)` (`Result[bytes, str]`), `fs.read_text(path)` (`Result[str, str]`),
`fs.write_file(path, data)`, `fs.write_text(path, text)`, `fs.mkdir(path)` and `fs.remove(path)` (`Result[Unit, str]`),
`fs.exists(path)` (`bool`) and `fs.listdir(path)` (`Result[list[str], str]`, names only).
`filesystem.list_entries(fs, path)` answers names and kinds in one listing
([listings with entry kinds](#listings-with-entry-kinds)). A tree walk keeps a list of folders still to read:

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

`fs.open(path, mode)` returns `Result[File, str]` for a binary mode and `Result[TextFile, str]` for a text mode. The mode is
a literal: `"r"`, `"w"` or `"a"` with an optional `"b"` or `"t"`. `with fs.open(...) as f:` **traps** with a located `R_FILE`
error if it cannot open; `with try fs.open(...) as f:` propagates the failure in a function that returns a compatible
`Result` ([propagation](results-and-options.md#postfix-error-propagation)).

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

- A handle has `f.read()`, `f.read(n)`, `f.readline()`, `f.readlines()` (lines keep their terminators), `f.write(data)`,
  `f.flush()`, `f.sync()` and `f.close()`. A handle is not iterable: write `for line in f.readlines():`.
- `write` returns the bytes written and loops over partial writes. `flush` does nothing (writes are unbuffered) and is not a
  durability promise; `f.sync()` is.
- A whole-file read (no count) has no size cap; `--max-memory` bounds it, and a read past that traps `R_MEMORY_BUDGET`. A count
  to `read(n)` or `readline(n)` is the most that call returns. To hand a piece of a read buffer on, see
  [Keeping pieces of a buffer](ownership-rules.md#keeping-pieces-of-a-buffer).
- The scope closes its file once at every exit (end, `return`, `try`, `break`, `continue`, `f.close()`, a trap). A method on a
  closed handle, or any provider failure in a method, traps `R_FILE` naming the call, path and reason
  (`write '/dev/full': no space left on the device`); to go on after a failed write use the whole-file calls, which answer a
  `Result`.
- An open binding is used through its methods, or lent to a helper as `mut` (`func put(mut f: File, ...)`). Giving it away
  with `own`, storing it in a record or returning it is `E_WITH_RESOURCE`, and so is declaring a type that would store one (a
  record field, list, dictionary, option, variant case, `Box[File]` or callback type of `File` or `TextFile`). A `result` whose
  `ok` case is a file, as `fs.open` returns, is the one way to carry a file onward. `with 7 as value:` is `E_TYPE`;
  `with arena():` is `E_ARENA_REMOVED`.
- Generic function bodies reject `print` and the file builtins (`E_GENERIC_BODY_UNSUPPORTED`); call an ordinary function.

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

The error text names the operation, the path and a reason: `read 'absent.txt': the path does not exist`. The reasons come from
one table for every call that touches a file: `no space left on the device`, `disk quota exceeded`, `the file is too large
for the size limit or for the filesystem`, `the filesystem is read-only`, `permission denied`, `too many files are open`,
`the path, or a name in it, is too long`, `input/output error`, `is a directory`, `a parent of the path is not a directory`,
`the path does not exist`, `already exists`, `is not a directory`, `the directory is not empty`, and `a folder on the way
does not exist`. An error outside the table gives its number and the system's words (`error 71: protocol error`). A refusal
by `--restrict` or a narrowed handle starts with `denied:`; a run without `--restrict` never mentions grants.

#### Making an appended record durable: `f.sync()`

`f.sync()` answers `Result[Unit, str]`; on `Ok` everything written through the handle is on stable storage (`fsync(2)`). A full disk is a result, not a trap: the `Err` names the path and reason
(`sync 'wal.log': no space left on the device`; a device: `this kind of file cannot be synchronized`). A read-only handle and a
test's in-memory file answer `Ok` and do nothing; a closed handle traps `R_FILE`.

A new file is durable only when its folder is synced too: call `fs.sync_directory(path)` ([below](#durable-storage)) once
after creating it, not per record. The example runs on a test's in-memory filesystem; the calls are the same on `main`'s:

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

#### How a path is read

One rule covers every call that takes a path on the `Filesystem` a run hands to `main`, including every `filesystem` call.

1. **Resolution.** A path is read as an ordinary process reads it: absolute with a leading `/`, else against the working
   directory; `.`, `..`, doubled and trailing slashes mean what they mean to the system. An empty path names the working
   directory for `exists`, `stat` and the listings and nothing for other calls. A NUL octet is refused.
2. **Without `--restrict`** nothing else is checked: every call accepts what `read_text` accepts (`./a//b`,
   `filesystem.stat(fs, "../f")`).
3. **Under `--restrict`** the resolved path must also fall inside a granted directory: `--allow-read` or `--allow-write` for a
   call that reads, `--allow-write` for one that changes the disk. With `--allow-write=out`, `out/report.txt`,
   `./out/report.txt` and its absolute path name the file; `report.txt` names the working directory's.
4. **A folder handle keeps its own rule; `fs.read_only()` does not.** On `fs.dir("d")` or `filesystem.dir_at` a path stays
   relative to the folder in every run; only the folder itself is read by rules 1 to 3. `fs.read_only()` only removes
   writing: `..` and absolute paths read through it as through `fs`.
5. **Three refusals, three texts.** Outside every grant: `read '../x': denied: '/home/me/x' is outside the granted
   directories`. A write inside a read grant: `write 'notes/a': denied: writing needs a write grant (--allow-write);
   '/srv/notes/a' is granted for reading only`. A narrowed handle: `write 'a': denied: this Filesystem was narrowed by
   fs.read_only() and does not write`, or `read '../a': denied: a Filesystem narrowed by fs.dir takes a path inside its
   folder, without '..', '.', an empty part or a leading '/'`.
6. **Every backend reads a path the same way**: the real filesystem, a native executable under `SELKA_OPTIONS=--restrict`,
   debug and `--release`. The in-memory filesystem (`filesystem.memory()`, a test's) is a tree whose root is its working
   directory and its one write grant; `..` past the root or an absolute path is refused.

What each kind of handle refuses beyond rules 1 to 3:

- `fs.read_only()`: every write, before the path is looked at; reads follow rules 1 to 3.
- `fs.dir("d")`, `filesystem.dir_at`: for every call, `..`, an absolute path and a `.` or empty part (`""` names the folder).
  A backslash is an ordinary name byte. A symbolic link on the way fails with `a parent of the path is not a directory`; a
  link at the end is refused for a read, a write and the source of `link_path` (`is a symbolic link the sandbox does not
  follow, or links nest too deeply`), `chmod_path` of one fails, and `touch_path`, `set_modified_path`, `rename_path` and
  `remove` act on the link itself.
- `fs.dir("d").read_only()`: a write is refused as `fs.read_only()` refuses it, a read as `fs.dir` refuses it.

`exists` never fails: it answers `False` for a path a folder handle refuses. Here `ro` reads a path with a `.` part and
refuses the write, and `folder` refuses the `.` part:

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

No spelling of a path reaches a file outside every grant: `..` is resolved as text only where that is exact, and the rest is
walked downwards from the grant's directory, following no symbolic link. A directory granted with `--allow-write` is always
readable too.

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

## Durable storage

Native `Filesystem` capabilities provide these durable operations:

| Operation | Result |
| --- | --- |
| `fs.list_directory(path, max_entries)` | `Result[str[], str]` |
| `fs.read_regular_file(path, max_bytes)` | `Result[bytes, str]` |
| `fs.atomic_write_file(path, data)` | `Result[Unit, str]` |
| `fs.sync_directory(path)` | `Result[Unit, str]` |
| `fs.lock_directory(path)` | `Result[File, str]` |

`with try fs.lock_directory("") as lease:` owns a narrowed root until scope exit; the lease is exclusive across processes,
released when a process dies, and a busy one fails with `: the lock is held by another holder`. Overlapping grants must
resolve to one directory. Reads refuse symlinks, special files and values over the requested limit. A 64 MiB ceiling belongs
to some calls ([which](#which-calls-have-a-64-mib-ceiling)). `filesystem.memory()`, also a test's `fs`, answers all of them
([below](#the-durable-calls-on-a-tests-filesystem)).

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

The ceiling is 64 MiB (67,108,864 octets; exactly that is accepted), for the durable calls only:

| Call | Over 64 MiB |
| --- | --- |
| `fs.read_file`, `fs.read_text`, `File.read()`, `fs.write_file`, `fs.write_text`, `File.write` | no ceiling (`--max-memory` still bounds a read) |
| `fs.atomic_write_file[_mode]`, `fs.replace_file[_mode]`, `fs.replace_file_synced[_mode]` | refused, nothing written: `atomic write 'PATH': is over the 64 MiB bound of one write` (`replace 'PATH': ...`) |
| `fs.read_regular_file(path, max_bytes)` | refused when `max_bytes` is over 64 MiB (`max_bytes is over the 64 MiB bound of one read`) or the file is larger than `max_bytes` |
| `filesystem.read_at(fs, path, offset, max_bytes)` | refused when `max_bytes` is over 64 MiB; any `offset` works |

Read a larger file with `read_file` or in pieces with `read_at`; publish it by writing a temporary name and `rename_path`. A
`filesystem.memory()` filesystem holds 64 MiB in all: past that `write_file` answers `Err` (`no space left on the device`)
and `File.write` traps `R_FILE`.

### Large directories and listing bounds

`listdir` and `list_directory` answer a directory of any size whole; a listing past `--max-memory` traps `R_MEMORY_BUDGET`.
The bound of `fs.list_directory(path, max_entries)` is the caller's:

| `fs.list_directory("big", n)` | Result |
| --- | --- |
| at most `n` entries | `Ok` of every name (a real directory in the system's order, the in-memory one sorted) |
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

`filesystem.list_entries(fs, path)` answers `Entry[] fails str` with `name: str` and `kind: PathKind` (`Regular`,
`Directory`, `Symlink`, `Other`) in one listing, so a scan need not `stat` every name (the builtin `fs.list_entries_path`
answers packed bytes). The kind is the entry's own, as `stat` reports it: a symbolic link is `Symlink` even when it names a
directory, `list_entries` of it fails with `is not a directory`, and `fs.listdir` of it lists the folder in a run without
`--restrict`. To list what a link points at, list `filesystem.realpath(fs, path)`. A real directory lists in the system's
order, `filesystem.memory()` sorted by name. A bad path fails with `directory listing 'path': ...` and the reason.

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

Four more durable operations publish a file, look at it and serialize with other processes. They read a path as every call
does ([How a path is read](#how-a-path-is-read)); a final link is never followed.

| Operation | Result | Authority |
| --- | --- | --- |
| `fs.rename_path(from, to)` | `Result[Unit, str]` | write, over both paths |
| `fs.stat_path(path)` | `Result[bytes, str]` | read |
| `fs.lock_file(path)` | `Result[File, str]` | write |
| `fs.try_lock_file(path)` | `Result[File, str]` | write |

- `rename_path` is the atomic `rename(2)` inside one granted directory: a reader sees the old file or the new one. It does not
  copy (`the paths are on different filesystems`) or sync the directory; call `sync_directory` for a power loss.
- `stat_path` answers 80 packed octets (ten little-endian 64-bit words: size, modification time in nanoseconds since the epoch,
  inode, kind, permission bits, status-change time, device, owner, group, hard links), or an **empty** `bytes` when nothing is
  there. `filesystem.stat(fs, path)` returns a `filesystem.Stat` (`kind`, `size`, `modified`, `inode`, `mode`, `changed`,
  `device`, `owner`, `group`, `links`) and fails with `filesystem.StatError`: `Missing` or `Failed(message)`. It describes a
  final symbolic link itself (`Symlink`); `filesystem.stat_follow` describes the target. `Stat.mode` is the permission bits
  (`0o644`, plus set-user-ID, set-group-ID and sticky; not the kind).
- `lock_file` takes an exclusive advisory `flock`, creating the file (mode 0600) if missing, and waits while another holder
  has it; `try_lock_file` fails at once with a text ending `: the lock is held by another holder`
  (`filesystem.is_lock_busy(message)` recognizes it). Both return the `File` of a `with` scope: the lock is released when the
  scope ends or the process dies. Two locks on one file exclude each other even in one process.

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

The publish-then-swap pattern a cache uses: write beside the destination, then rename, under a lock:

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

An atomic write syncs a temporary beside the destination, renames it and syncs its parent, so the old or the new complete
file survives an interruption. A failure after the rename reports that publication may have occurred; callers recover from
their journal.

### Device, free space and reads from an offset

Three more calls serve a program that watches a machine or follows a file. They need read authority, refuse a link under
`--restrict`, and work on `memory()` too.

| Operation | Result | Authority |
| --- | --- | --- |
| `fs.statfs_path(path)` | `Result[bytes, str]`, packed | read |
| `fs.read_at_path(path, offset, max_bytes)` | `Result[bytes, str]` | read |

- **The device.** `Stat.device` is the kernel's `st_dev`; `filesystem.device_major(device)` and `filesystem.device_minor(device)`
  take it apart, to match the `MAJ:MIN:INODE` of a `/proc/locks` line. A `memory()` entry is on `filesystem.MEMORY_DEVICE`
  (`1`).
- **Owner, group and links.** `Stat.owner` and `Stat.group` are the numeric user and group (`st_uid`, `st_gid`) and `Stat.links`
  the hard-link count (`st_nlink`). A `memory()` entry has owner `filesystem.MEMORY_OWNER` and group `filesystem.MEMORY_GROUP`
  (both `1000`). A constructor may leave `device`, `owner`, `group` and `links` out (`0`).
- **Free space.** `filesystem.statfs(fs, path)` answers a `filesystem.Space` for the filesystem that holds `path`: `size_bytes`,
  `free_bytes` and `available_bytes` (what an ordinary process may still use). Errors are `stat`'s. A `memory()` filesystem
  answers 1073741824, 536870912 and 402653184 for every existing path; its root is `""`, and `.` and `/` are refused.
- **Reading from an offset.** `filesystem.read_at(fs, path, offset, max_bytes)` answers at most `max_bytes` octets of the
  regular file at `path` from byte `offset` (`pread`): fewer when the file ends first, an empty `bytes` at or past the end,
  so a program that follows a growing file asks again from where its last answer ended. It opens the file as
  `read_regular_file` does; `max_bytes` is bounded by 64 MiB; a negative `offset` or `max_bytes` fails. The builtin takes the
  offset as eight little-endian octets.

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

`atomic_write_file` survives a power loss and pays two `fsync`s for it. Two more pairs ask for less:
`fs.replace_file(path, data)` and `fs.replace_file_mode(path, data, mode)` force nothing to disk;
`fs.replace_file_synced(path, data)` and `fs.replace_file_synced_mode(path, data, mode)` force the file but not the directory.

| | `atomic_write_file[_mode]` | `replace_file_synced[_mode]` | `replace_file[_mode]` |
| --- | --- | --- | --- |
| `fsync` of the file, then of the directory | both | the file only | neither |
| After a power loss or kernel crash | the new bytes | the old file (none, for a first write) or the new one | the old file; on a filesystem that reorders the rename ahead of the data, possibly a short new one |
| After a crash of the program alone | the old or the new file | the same | the same |
| A failure the call reports | before the rename, nothing changed; after it, "publication may have occurred" | before the rename, nothing changed | none from a sync |

All publish a temporary renamed over the destination, so a reader sees the old file or the new one. Use `atomic_write_file`
for a journal, a database record or a cache entry that must survive a restart; `replace_file_synced` where a torn file would
lose what an old one only repeats; `replace_file` for what the next run can regenerate. Mode and refusals are
`atomic_write_file`'s (`0600` unless a `_mode` form says otherwise); a failure reads `replace 'path': reason`.

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

Eleven more durable operations canonicalise paths, change permissions and times, make links, and create folders and files
with chosen permissions. Each takes a path with no `.` or `..` component (`canonical_path` also takes `.`) and works on
`filesystem.memory()`. A builtin answers `Result[_, str]`; the typed function `fail`s with the message (`Unit` when unmarked).

| Builtin | Typed function | Authority |
| --- | --- | --- |
| `fs.canonical_path(path)` | `filesystem.realpath(fs, path)` (`str`), `filesystem.cwd(fs)` | read |
| `fs.stat_follow_path(path)` | `filesystem.stat_follow(fs, path)` (`Stat fails StatError`) | read |
| `fs.read_link_path(path)` | `filesystem.read_link(fs, path)` (`str`) | read |
| `fs.chmod_path(path, mode)` | `filesystem.chmod(fs, path, mode)` | write |
| `fs.touch_path(path)` | `filesystem.touch(fs, path)` | write |
| `fs.set_modified_path(path, nanoseconds)` | `filesystem.set_modified(fs, path, nanoseconds)` | write |
| `fs.atomic_write_file_mode(path, data, mode)` | none | write |
| `fs.symlink_path(target, path)` | `filesystem.symlink(fs, target, path)` | write |
| `fs.link_path(target, path)` | `filesystem.link(fs, target, path)` | write |
| `fs.mkdir_mode(path, mode)` | `filesystem.mkdir_mode(fs, path, mode)` | write |
| `fs.create_mode(path, mode)` | `filesystem.create_mode(fs, path, mode)` (`File`) | write |

- **`canonical_path`** resolves every symbolic link, as `realpath(3)`; a missing path fails. It answers the absolute path
  (`filesystem.cwd(fs)` is the working directory), or on an `fs.dir(...)` handle the path relative to the folder (`""` for the
  folder). Under a grant or narrowing a link is followed only while it stays inside: an absolute link, one that climbs out,
  and a missing path behind one fail with `resolves outside the granted directory`. Only `canonical_path` and
  `stat_follow_path` resolve a link; every other call refuses one under a restriction or through `fs.dir`.
- **`stat_follow`** is `stat` that follows a final link (a link to nothing is `Missing`). Unrestricted it answers what
  `stat(2)` does, so `/dev/stdin` is kind `Other`; under `--restrict` and through `fs.dir` that path is refused.
- **`chmod_path`** sets the permission bits (`0` to `0o7777`, else `the mode must be between 0 and 0o7777`); `touch_path` sets
  an existing path's access and modification times to now; `set_modified_path` sets the modification time to `nanoseconds`
  since the epoch. None follows a final link: `chmod` of a link fails (`a symbolic link has no permission bits of its own`),
  `touch` and `set_modified` change the link.
- **`atomic_write_file_mode`** is `atomic_write_file` (`0600`) with the file created with `mode`, under the umask as for
  `open(2)`. **`Stat.changed`** is the status-change time, which a program cannot set back.
- **`symlink`** creates the link `path` holding the text `target` (target first, as `ln -s TARGET LINK`). It needs write
  authority; a path outside every grant, inside only a read grant, or taken is refused (`symlink 'path': already exists`).
  The target is only text, 1 to 4094 octets with no NUL, stored as written and never looked at. `stat` of the link is
  `Symlink` with the target's length as size; `remove` unlinks it and `rename_path` moves it.
- **`read_link`** answers the text stored in the link and never follows it, so a dangling link or one pointing outside the
  grant reads like any other; it resolves the path as `stat_path` does. Not a link: `read link 'PATH': is not a symbolic
  link`; nothing there: `the path does not exist`; a target that is not UTF-8: `the bytes read are not valid UTF-8 text`.

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

- **`link`** creates the hard link `path` to the existing file `target` (target first, as `ln TARGET LINK`): a second name for
  one file, sharing bytes, permission bits, times and inode (`Stat.links` reads 2 for both; removing one leaves the other). A
  publication over one name (`atomic_write_file`, `replace_file`) makes it a new file. It writes both paths, so each must be
  inside a write grant (two grants on different disks: `the paths are on different filesystems`), and no link is followed.
  `target` must be a regular file: a folder fails with `is a directory`, a symbolic link with `is a symbolic link the sandbox
  does not follow, or links nest too deeply`, a pipe, socket or device with `is not a regular file`. A taken `path` fails with
  `already exists`; failures read `link 'TARGET' to 'PATH': REASON`.

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

- **`mkdir_mode`** creates the folder with the permission bits `mode` (`0` to `0o7777`) from the moment it exists, which
  `fs.mkdir` then `chmod` does not (the folder is first open to its group). The umask narrows `mode`; set-user-ID and
  set-group-ID are left to `chmod`. For an exact mode, make the folder owner-only, fill it, then `chmod`. A taken path fails
  with `already exists`, one in a missing folder with `the parent directory does not exist` (`mkdir 'PATH': REASON`).

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

- **`create_mode`** opens `path` for writing as `fs.open(path, "wb")` does, and a file it creates has `mode` from the `open(2)`
  that makes it, so it is never group-readable while it fills; the umask narrows `mode`. A file that exists is truncated, its
  mode and owner kept. Failures read `open 'PATH': REASON`. The result is a `File`: `with fs.create_mode(path, mode) as f:`.

These writes follow the write rules of [How a path is read](#how-a-path-is-read). Publishing an executable script, then
stamping it with a build time:

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

`filesystem.memory()`, and so a test's `fs`, answers every durable operation on this page from its own entries, so a test runs
the code a program ships. Grants, path rules and the wording of refusals are the real ones. An embedding provider that cannot
promise durability refuses with `durable native filesystem provider is unavailable`. Everything is deterministic:

- **Modes and inodes.** A file is created `0644`, a directory `0755`, the root `0755` with inode 1; inodes count up from 2.
  There is no umask: a mode is stored as given. An `atomic_write_file` over a file is a new inode.
- **Times.** `Stat.modified` reads a logical clock that starts at 946684800 seconds (the test clock's epoch) and moves one
  second for each call that changes the filesystem; `set_modified_path`, `chmod_path` and failed calls do not move it.
  `Stat.changed` is later than every earlier change, so no test sleeps to make a file newer.
- **Links.** Symbolic links have mode `0777`; `canonical_path` and `stat_follow_path` follow one only inside the filesystem
  (over 40 in one walk is the link-nesting refusal). Hard links share bytes, mode, times, inode and lock.
- **Listings** are sorted by name and include hidden names.
- **Locks** are held until the `File` is released. A held `try_lock_file` or `lock_directory` fails with `: the lock is held by
  another holder`; `lock_file` would wait, so it fails at once with `: the lock is held (a stand-in cannot wait)`.

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

`filesystem.memory()`, and so a test's `fs`, honours the **owner** bits of every entry's mode; group, other and special bits
play no part. A call the bits forbid fails with `permission denied` and changes nothing. Three bits are asked for: **read**
(`4`: read a file, list a directory), **write** (`2`: write a file in place; add, remove or rename an entry of a directory)
and **search** (`1`) on every directory above the path.

- Reading a file needs read of the file (`read_regular_file` and `read_at` also read of its directory).
- Writing in place needs write of the file; creating a file needs write of its directory.
- Anything that creates, removes, renames, links or locks needs read and write of the directory (both directories for
  `link_path` and `rename_path`); `lock_directory` and `sync_directory` read the directory and the one that holds it.
- Listings, `chmod_path`, `touch_path` and `set_modified_path` need read of the directory; `stat_path`, `stat_follow_path`,
  `statfs_path`, `read_link_path`, `canonical_path` and `exists` need nothing.

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

## The native backend

`selka build` writes a native executable; `selka run` and `selka build --run` build one and run it. An executable grants every
capability by default and reads no option from its own arguments (every one is the program's), so its runtime options travel
in `SELKA_OPTIONS`: `--restrict`, the `--allow-*` grants and `--print-result`, separated by spaces (double quotes wrap an
option with a space). An unknown option, repeated grant or unterminated quote exits 2.

| Setting | Rule |
| --- | --- |
| Byte ceiling | `--max-memory=SIZE` in `SELKA_OPTIONS`, else `SELKA_MEMORY_LIMIT`, else none (`K`/`M`/`G`, `0` for none, a bad size exits 2); past it `R_MEMORY_BUDGET`, exit 1 ([runtime budgets](tooling/runtime-budgets.md#guest-memory-ceilings)) |
| Step and frame budgets | not runtime options: `selka run` and `build --run` build them in, a binary from `selka build -o` has none |
| Recursion | bounded by the native stack, 8 MiB by default; deeper ends with `R_FRAME_LIMIT`, naming `ulimit -s KBYTES` |
| Exit status | the entry's `int` result, low 8 bits; the result is written only when `SELKA_OPTIONS` names `--print-result` |

`selka run`, `run-project` and `build --run` set `SELKA_OPTIONS` for the program from their own command line, replacing any
inherited value. `selka build --run` takes the grants before `--` and passes the values after it to the program:

```text
$ SELKA_OPTIONS='--restrict --allow-read=notes' ./report --format=json
$ selka build report.selka --run --restrict --allow-read=notes -- --format=json
```

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/io.md).
