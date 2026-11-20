# Concurrency

Selka runs tasks on a pool of threads inside one process. Two forms start them:
a **task group**, which submits named functions and reads each result, and
**`parallel.map`**, which applies one function to every item of a list. Both
join before they return, so a task never outlives the group or map that started
it, and every value a task reads is still alive while it reads it.

The rules are the ordinary ownership rules. A task receives its arguments
read-only, as a direct call does, or takes them with `own`. A result comes back
by value. Nothing is shared mutably, and no task can see another task's
storage. A task takes values, never a capability, so it cannot print, read a
file or wait on the network: it computes and returns, and the caller does the
reading and writing ([below](#tasks-take-values)). The runtime checks the
lifetimes; the checker refuses what would break them, and names the call site
and the repair.

## In short

- **A task takes values and returns a value.** `g.submit(fn, ARGS)` and
  `parallel.map(values, fn, ARGS)` give `fn` its arguments as a direct call does
  (read-only, or with `own`), and its result comes back by value.
- **A task takes no capability, so it reads no file.** A `Stream`, `Filesystem`,
  `Network`, `Clock`, `Entropy`, `Environment`, `Process` or `Input`, or a value
  that holds one, is `E_TASK_CAPABILITY` (`E_TASK_HOST` for `Host`). Read before
  the tasks, pass the values in, and write after
  ([tasks take values](#tasks-take-values)).
- **A `mut` argument is refused** (`E_TASK_MUT`): nothing is shared mutably. Pass
  the value plainly, or give it with `own`.
- **A task handle cannot be stored in a list** (`E_TASK_HANDLE`). A handle
  initialises a `const` binding, `const t = g.submit(fn, ARGS)`, and is read once
  with `t.result()` in the block that submitted it. So a loop cannot submit one
  task per pass and join them later: to run many tasks over a list, write
  `parallel.map(values, fn, ARGS)` ([mapping a list](#mapping-a-list)).

The loop below is the refused shape; its repair is `parallel.map(values, square)`.

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

The pool has one thread per CPU. Its size is `--threads N` (1 to 256) or, for a
built binary, `SELKA_THREADS=N`, read once when the pool starts
([thread controls](#thread-controls)). A program cannot set the size, but it can
read it: `parallel.threads()` is the pool's size, and `parallel.cpus()` is the
number of CPUs the process may use ([the pool's size](#the-pools-size)).

## Task groups

`with parallel.group() as g:` opens a group. `g.submit(fn, ARGS)` starts `fn`
with the arguments written exactly as in a direct call `fn(ARGS)`, and returns a
handle. `t.result()` waits for that task and returns its value. The group joins
every task when its block ends, on every way out of the block: falling through,
`return`, `break`, `continue`, `fail` and `try`.

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

A handle is read once, inside the block that submitted it. A procedure with no
result (a `Unit` function that cannot fail) can be submitted as a bare statement,
with no handle:

```selka
# doc: expect 0
import parallel

func note(values: int[]):
    _ = len(values)

func main() -> int:
    mut values: int[] = [1, 2, 3]
    with parallel.group() as g:
        g.submit(note, values)
    return 0
```

A fallible function returns its failure through the handle, and `try` passes the
failure out of the enclosing function after the group has joined:

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

`parallel.map(values, fn, ARGS)` applies `fn` to every item and returns the
results in input order. The trailing `ARGS` (up to five) are written as in
`fn(item, ARGS)`, and every item gets the same arguments.

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

A managed argument (a list, text, bytes, record or dictionary) is lent to every item,
and is not copied for it. It may be held in a local or an `own` parameter; a list, text or
bytes held in a plain parameter has to be copied first ([Limits](#limits)):

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

A fallible function gives `R[] fails E` under `try`. Every item runs, and the
failure returned is the one with the lowest input index. `parallel.map_results`
keeps the list of results instead, one `Result` per item:

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

`parallel.threads()` returns the number of threads in the pool the program's tasks run
on, an `int` of at least 1: what `--threads N` or `SELKA_THREADS=N` set, else one per
CPU the process may use (at most 256). It takes no capability, because a task could
measure it anyway. A program that cuts its work into pieces asks it how many to cut.

The size is **fixed when the pool starts**: it is read once, at the program's first
task or its first call of `parallel.threads()`, whichever is first, and from then on it
does not change. A program cannot change it: there is no call that sets the size. A task
asks and gets the same count the calling thread gets. Three runs set it differently:

- `selka run FILE --threads N` and `SELKA_THREADS=N ./built` answer `N`.
- With neither, the answer is the number of CPUs the process may run on (its affinity
  mask, so `taskset -c 0,1 ./built` answers 2), capped at 256.
- `selka test` answers 1: a test child's step and frame budgets force one thread,
  with or without `--threads`, so the answer is what the test's tasks really get.
  `--max-steps` and `--max-frames` force one thread in a run too.

One exception: under a hard address-space limit (`ulimit -v`) the pool starts with only
as many threads as fit, which can be fewer than were asked for (`R_THREAD_START` when
not even two fit). A call made before the first task answers the count asked for, and a
call made after the pool started answers the count it has, so a program that must know
the real size reads it after its first task has run.

`parallel.cpus()` returns the CPUs the process may use, read when called, whatever
`--threads` says. It is the other half of "using N of M": `parallel.threads()` is N, and
`parallel.cpus()` is M.

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

The sum is the same for every pool size, and the list is never cut into more pieces than
the pool has threads. A program that prints its own use writes
`f"using {parallel.threads()} of {parallel.cpus()}"`.

## The shared-design idiom

One large model read by every task is the common case, and it costs no copy:
the record is lent to each task, and each task reads it in place. The copy
counters stay at zero at any record size and any number of tasks.

```selka
# doc: expect 0
import parallel

record Model:
    names: str[]
    weights: int[]

func weigh(index: int, model: Model) -> int:
    return model.weights[index] + len(model.names)

func main() -> int:
    mut weights: int[] = []
    for i in range(100000):
        append(mut weights, i)
    const model = Model(names=["a"], weights=own weights)
    mut indices: int[] = []
    for i in range(8):
        append(mut indices, i)
    const scores = parallel.map(indices, weigh, model)
    return scores[0] - 1
```

## Map, then merge

A reduction maps independent partial results and then combines them in one
ordinary loop, so the combining step needs no synchronisation:

```selka
# doc: expect 50
import parallel

func block_sum(start: int) -> int:
    mut total = 0
    for i in range(start, start + 10):
        total += i
    return total

func main() -> int:
    mut starts: int[] = []
    for i in range(10):
        append(mut starts, i * 10)
    const partial = parallel.map(starts, block_sum)
    mut total = 0
    for v in partial:
        total += v
    return total % 100
```

## Tasks take values

A task cannot take a capability: `Stream`, `Filesystem`, `Network`, `Clock`,
`Entropy`, `Environment`, `Process`, `Input` or `Host`, nor a record, list,
dictionary, option or union that holds one. Every task holding a copy of one
capability would share its provider, and a task's call would wait for, or
interleave with, every other task's calls: three tasks printing to one stream
printed in a different order from run to run, and a service and its client in
two tasks never finished. The checker refuses such an argument with
`E_TASK_CAPABILITY` and names the field that holds the capability. A stand-in
has the type of the real capability, so `filesystem.memory()` or a seeded
`Entropy` is refused the same way.

So a task computes and returns, and the caller reads before the group and
writes after it. A task that would print returns the text instead, and the
results come back in a fixed order, so the output is the same on every run:

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

The same program with `out` passed to the tasks is refused:

```selka
# doc: expect-error E_TASK_CAPABILITY
import parallel

func shout(n: int, out: Stream) -> int:
    print(out, "task", n)
    return n

func main(out: Stream) -> int:
    const all = parallel.map([1, 2, 3], shout, out)
    return len(all) - 3
```

A task may make its own stand-in (`filesystem.memory()`, `random.seeded_entropy(seed)`)
inside its body: nothing else holds it, so nothing interleaves. A program that
is a service and a client at once is one event loop, not two tasks: one
`network.Poller` accepts and dials, as in
[dialling from the event loop](standard-library.md#dialling-from-the-event-loop).

## What is refused, and the repair

The checker refuses these shapes before the program runs. Each message names the
task site, and where the edit is certain the diagnostic carries it as a fix.

| Code | Refused | Repair |
|---|---|---|
| `E_TASK_GROUP` | a group opened outside `with`, or a `submit` whose first argument is not a top-level function | open the group with `with parallel.group() as g:`; name the function |
| `E_TASK_ESCAPE` | a group or handle stored, passed or returned | use it only inside its block |
| `E_TASK_HANDLE` | a handle not bound by `const`, or read outside its block; a handle in a loop | bind it with `const t = g.submit(...)`; in a loop use `parallel.map` |
| `E_TASK_RESULT_UNREAD` | a handle never read, or a bare submit of a function with a result or a failure | read it with `t.result()` before the block ends |
| `E_TASK_MUT` | a `mut` argument to a task or to `parallel.map` | pass the value plainly, or give it with `own` |
| `E_TASK_CAPABILITY` | a capability other than Host (`Stream`, `Filesystem`, `Network`, ...), or a value holding one | read and write before or after the tasks; pass values and return results |
| `E_TASK_HOST` | the Host capability, or a value holding it | keep Host authority on the calling thread |
| `E_TASK_RESOURCE` | an open file or other resource handle | read it before the tasks and pass the values |
| `E_TASK_LOAN` | a lent value written or moved while the group reads it; a list element passed directly; a lent value declared inside a nested block | bind the element first (`const item = xs[i]`); declare the value before the group |

A `mut` argument and a list element each name their refusal in place:

```selka
# doc: expect-error E_TASK_MUT
import parallel

func touch(values: int[]) -> int:
    return len(values)

func main() -> int:
    mut values: int[] = [1]
    with parallel.group() as g:
        const t = g.submit(touch, mut values)
        return t.result()
```

```selka
# doc: expect-error E_TASK_LOAN
import parallel

record Row:
    cells: int[]

func weigh(row: Row) -> int:
    return len(row.cells)

func main() -> int:
    mut rows: Row[] = []
    append(mut rows, Row(cells=[1]))
    with parallel.group() as g:
        const t = g.submit(weigh, rows[0])
        return t.result()
```

One more shape needs a `copy(...)`: a borrowed call result or a dictionary
fallback given directly to a task is refused with `copy(...)` around it, so the
task has its own value. `parallel.map` needs none: a slice, or a plain text,
bytes or list parameter, given to it as the input or as a trailing argument is
lent to every item as it is, with no copy, because the map returns only after
every item has finished. `parallel.map` of a fallible function written without
`try` is `E_PARALLEL_MAP_FALLIBLE` (the fix renames it `parallel.map_results`).

## Thread controls

The program's pool has one thread per CPU by default. Three controls change it:

- `--threads N` on `selka run`, `selka build --run` and `selka test` sets the
  number of task threads, from 1 to 256. The flag is not part of any receipt key,
  so a test answered from a receipt is the same whatever thread count it ran with.
- `SELKA_THREADS=N` sets the same count for a built binary, which takes no
  flags. An invalid value stops the program with `R_THREAD_START`.
- `--max-steps` and `--max-frames` force one thread, because their counts are
  kept per thread. A test child has both budgets by default, so it runs one thread
  whatever `--threads` says.
- A program reads the size it ended up with through `parallel.threads()`
  ([the pool's size](#the-pools-size)); it cannot set it.

```console
$ selka run busy.selka --release --threads 8
$ selka build busy.selka -o busy --release && SELKA_THREADS=2 ./busy
```

## Limits

- **One thread in test children.** A test child runs one thread: its default step and
  frame budgets force it, and `--threads` does not change that. Test receipts for a test
  that calls `parallel.map` are not reused: the stdlib map calls its function indirectly,
  which the receipt rule treats as unknown input. A test that calls `parallel.threads()`
  or `parallel.cpus()` is not reused either, because no key binds either count. Group
  tests are reused.
- **`parallel.map` lends what it is given.** A trailing argument that is a list,
  text or bytes held in a plain parameter, or a slice, is lent to every item as the
  view itself, as is a local, an `own` parameter or a record parameter: nothing is
  copied for any of them.
- **A list given to `parallel.map` is read in place, wherever it is held.** A list in
  a local, a list in a plain parameter and a slice are all passed as they are, and the
  list is still the caller's after the call; `own` is refused at the call. The two
  cases follow, side by side.
- **Capabilities and resources stay on the calling thread.** A task cannot take a
  capability, an open file, or a value that holds either ([tasks take
  values](#tasks-take-values)). `debug(...)` needs no capability and still writes
  from a task, so its lines from several tasks come in any order.
- **A handle is read once.** A second `t.result()` has nothing left to take.
- **Scheduling is not ordered.** Tasks run in any order on any thread; only the
  results are ordered (by input index for `parallel.map`, and by handle for a
  group). Output that depends on timing is not a result the language gives.

### A list given to `parallel.map`: a local, and a parameter

| The list is held in | Write | Refused |
| --- | --- | --- |
| a local (`mut pieces: bytes[]`) | `parallel.map(pieces, fn)`: the list is only read, and it is still yours after the call | `parallel.map(own pieces, fn)`: `E_OWN_MARKER`, the argument is only read |
| a plain parameter (`pieces: bytes[]`) | `parallel.map(pieces, fn)`: the items read the caller's list, or its slice, in place, with no copy | `parallel.map(own pieces, fn)`: refused, the argument is only read |

A list in a local goes in plainly. A list of `bytes` shows that nothing is copied for it:

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

A list in a plain parameter goes in plainly too, whether the caller gave a whole list or a slice of one:

```selka
# doc: expect 6 3 3
import parallel

func size(piece: bytes) -> int:
    return len(piece)

func total(pieces: bytes[]) -> int:
    mut sum = 0
    for n in parallel.map(pieces, size):
        sum += n
    return sum

func main(out: Stream) -> int:
    mut pieces: bytes[] = []
    append(mut pieces, b"abc")
    append(mut pieces, b"de")
    append(mut pieces, b"f")
    print(out, total(pieces), total(pieces[1:3]), len(pieces))
    return 0
```

The refusal a reader of the table meets is `own` at the call:

```selka
# doc: expect-error E_OWN_MARKER
import parallel

func size(piece: bytes) -> int:
    return len(piece)

func main(out: Stream) -> int:
    mut pieces: bytes[] = [b"abc"]
    print(out, len(parallel.map(own pieces, size)))
    return 0
```
