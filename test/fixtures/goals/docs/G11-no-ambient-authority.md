# G11. No ambient authority: pinned examples

## Holds

**G11-H1.** Output needs a `Stream` parameter.

```selka
# doc: expect-error E_OUTPUT_CAPABILITY
func main() -> int:
    print("hello")
    return 0
```

**G11-H2.** A capability that a function takes and never uses is an error, so a signature does not overstate what the
function can reach.

```selka
# doc: expect-error E_UNUSED_CAPABILITY
func helper(out: Stream, n: int) -> int:
    return n + 1

func main(out: Stream) -> int:
    print(out, helper(out, 1))
    return 0
```

**G11-H3.** A task cannot take a capability that reads or writes the outside world (decision Q1, item W28). Three
tasks printing to one `Stream` gave 16 different outputs in 60 runs; the program is refused, and a task returns what it
would print.

```selka
# doc: expect-error E_TASK_CAPABILITY
import parallel

func shout(out: Stream, n: int) -> int:
    for i in range(0, 3):
        print(out, "task", n, "line", i)
    return n

func main(out: Stream) -> int:
    mut total = 0
    with parallel.group() as g:
        const a = g.submit(shout, out, 1)
        const b = g.submit(shout, out, 2)
        total = a.result() + b.result()
    return total
```

## Exceptions

**G11-X1 (`debug` writes to standard error with no capability; W5).**

```selka
# doc: check
func main() -> int:
    debug("no capability needed")
    return 0
```

**G11-X2 (a capability is shared state: a plain parameter advances the caller's clock; decision Q9).** This is the
design of capabilities. It is pinned so that a change to it is noticed.

```selka
# doc: expect 100 100
# doc: expect 5000000100 5000000100
import time

func read(c: Clock) -> int:
    match time.now(c):
        case Ok(i):
            return i.unix_nanoseconds
        case Err(_):
            return -1

func tick(c: Clock):
    match time.seconds(5):
        case Ok(d):
            _ = time.advance(c, d)
        case Err(_):
            pass

func main(out: Stream) -> int:
    const c = time.simulated_clock(time.from_unix_nanoseconds(100))
    const alias = c
    print(out, read(c), read(alias))
    tick(c)
    print(out, read(c), read(alias))
    return 0
```
