# Time and randomness

`time` and `random` are embedded guest modules written in the ordinary Python
style. Their external reads take the existing `clock_cap` and `random_cap`
parameters and carry the transitive `clock` and `random` effects. Importing a
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
failed categories apart in its message. These are wall-clock instants: a clock may
move backward. The capability surface exposes no monotonic counter, so this module
has no monotonic clock, no sleeping, no calendar conversion and no time zones.
Host allocation failure aborts execution as usual.

```mylang
# doc: expect 42
module main
import time

def main() -> int:
    match time.seconds(9223372037):
        case Ok(_):
            return 1
        case Err(_):
            return bounded()

def bounded() -> int:
    match time.milliseconds(42):
        case Ok(step):
            if time.to_milliseconds(step) != 42 or time.compare(step, step) != 0:
                return 2
            return int(time.to_seconds(step) * 1000.0)
        case Err(message):
            return 0 - len(message)
```

## Reproducible streams

`random.seeded` builds SplitMix64 state from a signed seed and `random.from_word`
from a raw 64-bit word. `next_word` advances the stream by exactly one step and
returns its full-width output. Seed zero's first two words are
`16294208416658607535` and `7960286522194355700`. This generator is for
reproducible simulation and tests; it is not a cryptographic generator.

A `Random` value holds its state in a managed cell. Copying the value therefore
shares one stream instead of forking it, which is the opposite of the old
explicit-state API and matches how a generator is normally passed around.

`randint(generator, low, high)` samples the inclusive range uniformly. It computes
the width without overflowing either bound, so `randint(generator, -2^63, 2^63-1)`
is valid, and it removes modulo bias by rejecting words below
`(-width mod 2^64) mod width`. `random` returns one of the 2^53 multiples of 2^-53
in `[0, 1)`. `choice` reports `None` for an empty list and `shuffle` performs an
in-place Fisher-Yates pass.

```mylang
# doc: expect 42
module main
import random

def main() -> int:
    first = random.seeded(0)
    if random.next_word(first) != 16294208416658607535u64:
        return 1
    if random.next_word(first) != 7960286522194355700u64:
        return 2
    replay = random.seeded(0)
    if random.next_word(replay) != 16294208416658607535u64:
        return 3
    alias = replay
    if random.next_word(alias) != 7960286522194355700u64:
        return 4
    fresh = random.seeded(0)
    _ = random.next_word(fresh)
    _ = random.next_word(fresh)
    if random.next_word(replay) != random.next_word(fresh):
        return 5
    return sampled()

def sampled() -> int:
    generator = random.seeded(11)
    lowest = 42
    highest = 42
    index = 0
    while index < 200:
        match random.randint(generator, 42, 43):
            case Ok(value):
                if value < lowest:
                    lowest = value
                if value > highest:
                    highest = value
            case Err(message):
                return 0 - len(message)
        index += 1
    if highest != 43:
        return 6
    return lowest
```

## Authority

`random.from_entropy` reads one provider word through an explicit `random_cap` and
returns `Result[Random, str]`; `time.now` does the same through `clock_cap`. Both
declare `effects(clock, managed_allocation)` or `effects(random, managed_allocation)`,
so a caller with a tighter ceiling is rejected at check time rather than at run
time. Neither deterministic nor provider functions silently acquire authority.

The [example](../examples/standard-time-random/main.my) exercises arithmetic
limits, reproducible sequences and rejected bounds without any ambient authority.
