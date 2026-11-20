# Concurrency

Selka runs tasks on a pool of threads inside one process. Two forms start them: a **task group**, which submits named
functions and reads each result, and **`parallel.map`**, which applies one function to every item of a list. Both join
before they return, so a task never outlives the group or map that started it.

The rules are the ordinary ownership rules: a task receives its arguments read-only, or takes them with `own`, and a result
comes back by value. Nothing is shared mutably, and a task takes values, never a capability.

## In short

- **A task takes values and returns a value.** `g.submit(fn, ARGS)` and `parallel.map(values, fn, ARGS)` give `fn` its
  arguments as a direct call does.
- **A task takes no capability.** A `Stream`, `Filesystem`, `Network`, `Clock`, `Entropy`, `Environment`, `Process` or
  `Input`, or a value that holds one, is `E_TASK_CAPABILITY` (`E_TASK_HOST` for `Host`). Read before the tasks, write
  after ([tasks take values](#tasks-take-values)).
- **A `mut` argument is refused** (`E_TASK_MUT`): pass the value plainly, or with `own`.
- **A task handle cannot be stored in a list** (`E_TASK_HANDLE`). It initialises a `const`, `const t = g.submit(fn, ARGS)`,
  and is read once with `t.result()` in the block that submitted it. To run many tasks over a list, use
  `parallel.map(values, fn, ARGS)` ([mapping a list](#mapping-a-list)); the loop below is the refused shape.
- **The pool has one thread per CPU.** `--threads N` sets it for a run, `SELKA_THREADS=N` for a built binary
  ([the pool's size](#the-pools-size)).

```selka
# doc: expect-error E_TASK_HANDLE
import parallel

func square(n: int) -> int:
    return n * n

func main() -> int:
    mut jobs: int[] = []
    with parallel.group() as g:
        for i in range(3):
            append(mut jobs, g.submit(square, i))
    return 0
```

## Task groups

`with parallel.group() as g:` opens a group. `g.submit(fn, ARGS)` starts `fn` with the arguments written as in a direct
call `fn(ARGS)`, and returns a handle. `t.result()` waits for that task and returns its value. The group joins every task
when its block ends, on every way out: falling through, `return`, `break`, `continue`, `fail` and `try`.

```selka
# doc: expect 30
import parallel

func weigh(values: int[], scale: int) -> int:
    mut total = 0
    for v in values:
        total += v
    return total * scale

func main() -> int:
    mut values: int[] = []
    for i in range(10):
        append(mut values, i)
    mut first = 0
    mut second = 0
    with parallel.group() as g:
        const a = g.submit(weigh, values, 1)
        const b = g.submit(weigh, values, 2)
        first = a.result()
        second = b.result()
    return first + second - 105
```

A handle is read once, inside the block that submitted it. A procedure with no result (a `Unit` function that cannot fail)
can be submitted as a bare statement, `g.submit(note, values)`, with no handle. A fallible function returns its failure
through the handle, and `try t.result()` passes it out of the enclosing function after the group has joined:

```selka
# doc: expect 7
import parallel

func check(value: int) -> int fails str:
    if value < 0:
        fail "negative"
    return value

func total(values: int[]) -> int fails str:
    mut result = 0
    with parallel.group() as g:
        const t = g.submit(check, values[0])
        result = try t.result()
    return result

func main() -> int:
    match total([7]):
        case Ok(value):
            return value
        case Err(text):
            return 1
```

## Mapping a list

`parallel.map(values, fn, ARGS)` applies `fn` to every item and returns the results in input order. The trailing `ARGS` (up
to five) are written as in `fn(item, ARGS)`, and every item gets the same arguments. A reduction maps partial results, then combines them in one loop.

```selka
# doc: expect 6
import parallel

func scale(value: int, factor: int) -> int:
    return value * factor

func main() -> int:
    mut values: int[] = []
    for i in range(3):
        append(mut values, i + 1)
    const doubled = parallel.map(values, scale, 2)
    mut sum = 0
    for v in doubled:
        sum += v
    return sum - 6
```

A managed argument (a list, text, bytes, record or dictionary) is lent to every item, not copied, so one large model read
by every task costs no copy:

```selka
# doc: expect 1200
import parallel

record Design:
    name: str
    nets: int[]

func fanout(index: int, design: Design) -> int:
    return len(design.nets) + index

func main() -> int:
    mut nets: int[] = []
    for i in range(1000):
        append(mut nets, i)
    const design = Design(name="top", nets=own nets)
    mut starts: int[] = []
    append(mut starts, 0)
    append(mut starts, 100)
    append(mut starts, 200)
    const scores = parallel.map(starts, fanout, design)
    return scores[2]
```

A fallible function gives `R[] fails E` under `try`. Every item runs, and the failure returned is the one with the lowest
input index. `parallel.map_results` keeps one `Result` per item instead. `parallel.map` of a fallible function written
without `try` is `E_PARALLEL_MAP_FALLIBLE` (`selka fix` renames it `parallel.map_results`).

```selka
# doc: expect 2
import parallel

func check(value: int) -> int fails str:
    if value == 3:
        fail "three"
    return value * 10

func collect(values: int[]) -> int[] fails str:
    return try parallel.map(values, check)

func main() -> int:
    mut values: int[] = [1, 2]
    match collect(values):
        case Ok(results):
            return len(results)
        case Err(text):
            return 9
```

## The pool's size

The pool has one thread per CPU the process may use (at most 256). A program cannot set the size, only read it.

| Control | Effect |
| --- | --- |
| `--threads N` on `selka run`, `selka build --run`, `selka test` | N task threads, 1 to 256 |
| `SELKA_THREADS=N` | the same, for a built binary; an invalid value stops the program with `R_THREAD_START` |
| `--max-steps`, `--max-frames` | force one thread; a test child has both budgets by default, so it runs one thread whatever `--threads` says |
| `parallel.threads()` | the pool's size, an `int` of at least 1; takes no capability |
| `parallel.cpus()` | the CPUs the process may use, read when called, whatever `--threads` says |

The size is fixed when the pool starts, at the first task or first `parallel.threads()` call. Without a flag it is the
process's CPU affinity (`taskset -c 0,1 ./built` answers 2); `selka test` answers 1. Under a hard address-space limit
(`ulimit -v`) the pool starts only as many threads as fit (`R_THREAD_START` when not even two fit), so read the size after
the first task.

```console
$ selka run busy.selka --release --threads 8
$ selka build busy.selka -o busy --release && SELKA_THREADS=2 ./busy
```

A program that cuts its work into pieces asks how many:

```selka
# doc: expect 5050 True
import parallel

# The list cut into at most `pieces` runs of nearly equal length, in order.
func split(values: int[], pieces: int) -> int[][]:
    mut out: int[][] = []
    const size = (len(values) + pieces - 1) // pieces
    mut start = 0
    while start < len(values):
        mut stop = start + size
        if stop > len(values):
            stop = len(values)
        mut run: int[] = []
        for index in range(start, stop):
            append(mut run, values[index])
        append(mut out, own run)
        start = stop
    return out


func total(run: int[]) -> int:
    mut sum = 0
    for value in run:
        sum = sum + value
    return sum


func main(out: Stream) -> int:
    mut values: int[] = []
    for n in range(1, 101):
        append(mut values, n)
    const pieces = split(values, parallel.threads())
    mut sum = 0
    for part in parallel.map(pieces, total):
        sum = sum + part
    print(out, sum, len(pieces) <= parallel.threads())
    return 0
```

## Tasks take values

A task cannot take a capability (`Stream`, `Filesystem`, `Network`, `Clock`, `Entropy`, `Environment`, `Process`, `Input` or
`Host`), nor a record, list, dictionary, option or union that holds one: tasks sharing one provider would interleave its
calls differently every run. `E_TASK_CAPABILITY` names the field that holds it; a stand-in such as `filesystem.memory()`
is refused the same way. A task that would print returns the text instead, and results come back in a fixed order:

```selka
# doc: expect task 1 squared 1
# doc: expect task 2 squared 4
# doc: expect task 3 squared 9
import parallel

func report(n: int) -> str:
    return f"task {n} squared {n * n}"

func main(out: Stream) -> int:
    const lines = parallel.map([1, 2, 3], report)
    for line in lines:
        print(out, line)
    return 0
```

A task may make its own stand-in (`filesystem.memory()`, `random.seeded_entropy(seed)`) inside its body. A service and a
client in one program are one event loop, not two tasks ([dialling from the event
loop](standard-library.md#dialling-from-the-event-loop)).

## What is refused, and the repair

The checker refuses these shapes, naming the task site; where the edit is certain the diagnostic carries the fix.

| Code | Refused | Repair |
|---|---|---|
| `E_TASK_GROUP` | a group opened outside `with`, or a `submit` of anything but a top-level function | `with parallel.group() as g:`; name the function |
| `E_TASK_ESCAPE` | a group or handle stored, passed or returned | use it only inside its block |
| `E_TASK_HANDLE` | a handle not bound by `const`, read outside its block, or in a loop | `const t = g.submit(...)`; in a loop use `parallel.map` |
| `E_TASK_RESULT_UNREAD` | a handle never read, or a bare submit of a function with a result or a failure | read it with `t.result()` |
| `E_TASK_MUT` | a `mut` argument to a task or to `parallel.map` | pass the value plainly, or give it with `own` |
| `E_TASK_CAPABILITY` | a capability other than Host, or a value holding one | read and write before or after the tasks |
| `E_TASK_HOST` | the Host capability, or a value holding it | keep Host authority on the calling thread |
| `E_TASK_RESOURCE` | an open file or other resource handle | read it before the tasks and pass the values |
| `E_TASK_LOAN` | a lent value written or moved while the group reads it; a list element passed directly; a lent value declared in a nested block | bind the element first (`const item = xs[i]`); declare the value before the group |

A borrowed call result or a dictionary fallback given directly to a task is refused with `copy(...)` around it. `parallel.map`
needs none: a slice, or a plain text, bytes or list parameter, is lent to every item as it is.

## Limits

- **One thread in test children.** `--threads` does not change that. A test that calls `parallel.map`, `parallel.threads()`
  or `parallel.cpus()` is not answered from a receipt; group tests are.
- **`parallel.map` lends what it is given.** A list, text or bytes in a plain parameter, a slice, a local, an `own`
  parameter or a record parameter is lent as the view itself; a list given to it is still the caller's after the call, and
  `own pieces` at the call is `E_OWN_MARKER`.
- **Capabilities and resources stay on the calling thread** ([tasks take values](#tasks-take-values)). `debug(...)` still
  writes from a task, so its lines from several tasks come in any order.
- **A handle is read once.**
- **Scheduling is not ordered.** Tasks run in any order on any thread; only the results are ordered (by input index for
  `parallel.map`, by handle for a group).

```selka
# doc: expect 3 3
import parallel

func size(piece: bytes) -> int:
    return len(piece)

func main(out: Stream) -> int:
    mut pieces: bytes[] = []
    append(mut pieces, b"abc")
    append(mut pieces, b"de")
    append(mut pieces, b"f")
    const sizes = parallel.map(pieces, size)
    print(out, len(sizes), len(pieces))
    return 0
```

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/concurrency.md).
