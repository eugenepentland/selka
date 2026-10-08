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
has no monotonic clock, no sleeping, no calendar conversion and no time zones;
only a [simulated clock](#deterministic-stand-ins) can be moved.
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

A `Random` is a value record. Copying it snapshots its current position: each
copy produces the same remaining sequence, and advancing one leaves the other
unchanged. Pass `mut generator` to advance the caller's stream.

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
    if random.next_word(mut first) != 16294208416658607535u64:
        return 1
    if random.next_word(mut first) != 7960286522194355700u64:
        return 2
    replay = random.seeded(0)
    if random.next_word(mut replay) != 16294208416658607535u64:
        return 3
    snapshot = replay
    if random.next_word(mut snapshot) != 7960286522194355700u64:
        return 4
    if random.next_word(mut replay) != 7960286522194355700u64:
        return 5
    if random.next_word(mut replay) != random.next_word(mut snapshot):
        return 7
    return sampled()

def sampled() -> int:
    generator = random.seeded(11)
    lowest = 42
    highest = 42
    index = 0
    while index < 200:
        match random.randint(mut generator, 42, 43):
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

## Deterministic stand-ins

`time.simulated_clock(start)` builds a `Clock` that reads `start` until
`time.advance(clock, duration)` moves it, and `random.seeded_entropy(seed)` an
`Entropy` whose words are the SplitMix64 stream of `seed` — the same stream the
host's `--allow-random=SEED` grant produces. Neither needs a capability or
contributes an effect, and neither reads a host provider, so code written
against `now` and `from_entropy` can be exercised deterministically. A test that
declares `clock: Clock` or `entropy: Entropy` receives exactly these stand-ins
from `mylang test` ([capability parameters](tooling/guest-tests.md#capability-parameters)).

```mylang
# doc: expect True
module main
import random
import time

def first(entropy: Entropy) -> u64:
    match random.from_entropy(entropy):
        case Ok(sampled):
            generator = sampled
            return random.next_word(mut generator)
        case Err(_):
            return 0u64

def reading(clock: Clock) -> int:
    match time.now(clock):
        case Ok(instant):
            return instant.unix_nanoseconds
        case Err(_):
            return -1

def main(out: Stream) -> int:
    clock = time.simulated_clock(time.from_unix_nanoseconds(5))
    _ = time.advance(clock, time.nanoseconds(10))
    same = first(random.seeded_entropy(9)) == first(random.seeded_entropy(9))
    out.print(same and reading(clock) == 15)
    return 0
```

The [example](../examples/standard-time-random/main.my) exercises arithmetic
limits, reproducible sequences and rejected bounds without any ambient authority.
