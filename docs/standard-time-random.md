# Time and randomness

`time` and `random` are embedded guest modules written in the ordinary Python
style. Their external reads take the existing `Clock` and `Entropy`
parameters. Importing a
module grants no authority. Embedders supply the existing
`vm.Options.external` callbacks or the native provider ABI callbacks. Their
signatures are listed with the rest of the
[standard library](standard-library.md#time).

## Durations and instants

`Duration` and `Instant` are value records over a signed nanosecond count, which
reaches roughly 292 years either side of the Unix epoch. `nanoseconds` is exact.
`microseconds`, `milliseconds` and `seconds` reject a count whose product leaves
the signed range. `sum`, `difference` and `after` reject an overflowing result
rather than wrapping, and `elapsed` rejects a reversed pair and a span that cannot
be represented. `compare` gives a three-way ordering, `to_seconds` converts to
binary64 and `to_milliseconds` truncates toward zero.

`now` reads the host wall clock and keeps the provider's unavailable, denied and
failed categories apart in its message. Under `--restrict` the wall clock needs `--allow-clock`: without it `now` fails
with "the wall clock is not granted: pass `--allow-clock`", while `monotonic` and `sleep` work on the same clock, which
needs no grant. These are wall-clock instants: a clock may
move backward, so for elapsed time use the [monotonic reading](#monotonic-readings-and-sleep)
instead. This module has no calendar conversion and no time zones; only a
[simulated clock](#deterministic-stand-ins) can be moved.
Host allocation failure aborts execution as usual.

```selka
# doc: expect 42
import time
import strings

func main() -> int:
    match time.seconds(9223372037):
        case Ok(_):
            return 1
        case Err(_):
            return bounded()

func bounded() -> int:
    match time.milliseconds(42):
        case Ok(step):
            if time.to_milliseconds(step) != 42 or time.compare(step, step) != 0:
                return 2
            return int(time.to_seconds(step) * 1000.0)
        case Err(message):
            return 0 - strings.char_count(message)
```

## Reproducible streams

`random.seeded` builds SplitMix64 state from a signed seed and `random.from_word`
from a raw 64-bit word. `next_word` advances the stream by exactly one step and
returns its full-width output. Seed zero's first two words are
`16294208416658607535` and `7960286522194355700`. This generator is for
reproducible simulation and tests; it is not a cryptographic generator.

A `Random` is a value record. Copying it snapshots its current position: each
copy produces the same remaining sequence, and advancing one leaves the other
unchanged. Pass `mut generator` to advance the caller's stream.

`randint(generator, low, high)` samples the inclusive range uniformly. It computes
the width without overflowing either bound, so `randint(generator, -2^63, 2^63-1)`
is valid, and it removes modulo bias by rejecting words below
`(-width mod 2^64) mod width`. `random` returns one of the 2^53 multiples of 2^-53
in `[0, 1)`. `choice` reports `None` for an empty list and `shuffle` performs an
in-place Fisher-Yates pass.

```selka
# doc: expect 42
import random
import strings

func main() -> int:
    mut first = random.seeded(0)
    if random.next_word(mut first) != 16294208416658607535u64:
        return 1
    if random.next_word(mut first) != 7960286522194355700u64:
        return 2
    mut replay = random.seeded(0)
    if random.next_word(mut replay) != 16294208416658607535u64:
        return 3
    mut snapshot = copy(replay)
    if random.next_word(mut snapshot) != 7960286522194355700u64:
        return 4
    if random.next_word(mut replay) != 7960286522194355700u64:
        return 5
    if random.next_word(mut replay) != random.next_word(mut snapshot):
        return 7
    return sampled()

func sampled() -> int:
    mut generator = random.seeded(11)
    mut lowest = 42
    mut highest = 42
    mut index = 0
    while index < 200:
        match random.randint(mut generator, 42, 43):
            case Ok(value):
                if value < lowest:
                    lowest = value
                if value > highest:
                    highest = value
            case Err(message):
                return 0 - strings.char_count(message)
        index += 1
    if highest != 43:
        return 6
    return lowest
```

## Authority

`random.from_entropy` reads one provider word through an explicit `Entropy` and
returns `Result[Random, str]`; `time.now` does the same through `Clock`. The caller must pass the corresponding `Entropy` or `Clock` capability
value explicitly. Neither deterministic nor provider functions silently acquire authority.

## Deterministic stand-ins

`time.simulated_clock(start)` builds a `Clock` that reads `start` until
`time.advance(clock, duration)` moves it, and `random.seeded_entropy(seed)` an
`Entropy` whose words are the SplitMix64 stream of `seed` — the same stream the
host's `--allow-random=SEED` grant produces. Neither needs a capability or
contributes an effect, and neither reads a host provider, so code written
against `now` and `from_entropy` can be exercised deterministically. A test that
declares `clock: Clock` or `entropy: Entropy` receives exactly these stand-ins
from `selka test` ([capability parameters](tooling/guest-tests.md#capability-parameters)).

```selka
# doc: expect True
import random
import time

func first(entropy: Entropy) -> u64:
    match random.from_entropy(entropy):
        case Ok(sampled):
            mut generator = own sampled
            return random.next_word(mut generator)
        case Err(_):
            return 0u64

func reading(clock: Clock) -> int:
    match time.now(clock):
        case Ok(instant):
            return instant.unix_nanoseconds
        case Err(_):
            return -1

func main(out: Stream) -> int:
    mut clock = time.simulated_clock(time.from_unix_nanoseconds(5))
    _ = time.advance(clock, time.nanoseconds(10))
    mut same = first(random.seeded_entropy(9)) == first(random.seeded_entropy(9))
    print(out, same and reading(clock) == 15)
    return 0
```

## Monotonic readings and sleep

`time.monotonic(clock)` returns the clock's monotonic reading in nanoseconds. It never
decreases, and a wall-clock step does not move it, so it is the reading to measure
elapsed time with; `time.now` stays the wall clock. `time.sleep(clock, count)` waits
`count` nanoseconds on the clock, and a count of zero or less waits for nothing. A host
clock waits for real time. A simulated clock advances instead of waiting: its monotonic
reading and its wall reading both move forward by `count`, and `time.advance` moves only
the wall reading. A test that sleeps therefore runs at once and sees a deterministic
reading.

```selka
# doc: expect True
import time

func main(out: Stream) -> int:
    mut clock = time.simulated_clock(time.from_unix_nanoseconds(5))
    time.sleep(clock, 20)
    _ = time.advance(clock, time.nanoseconds(-7))
    print(out, time.monotonic(clock) == 20)
    return 0
```

The [example](../examples/standard-time-random/main.selka) exercises arithmetic
limits, reproducible sequences and rejected bounds without any ambient authority.
