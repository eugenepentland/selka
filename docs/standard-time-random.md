# Time and randomness

`std_time` and `std_random` are embedded guest modules. Their external reads use
existing `clock_cap` and `random_cap` parameters, with transitive `clock` and
`random` effects. Importing a module grants no authority. Embedders provide the
existing `vm.Options.external` callbacks or native provider ABI callbacks.

`Duration { nanoseconds:u64 }` and `Instant { unix_nanoseconds:i64 }` represent
elapsed quantities and wall-clock timestamps. `seconds` and `milliseconds`
reject overflow. `add` rejects timestamps beyond i64 maximum; `elapsed` supports
the entire signed timestamp range and rejects reversed timestamps. `expired`
compares a supplied current timestamp with a deadline. `now` preserves unavailable,
denied and failed provider categories. These are wall-clock instants: clocks may
move backward. This API does not provide monotonic scheduling, sleeping, calendar
conversion or time zones. Host OutOfMemory aborts execution as usual.

`std_random::seed` constructs explicitly passed, copyable SplitMix64 state.
`next` returns both the advanced generator and its full-width word. Copying a
state intentionally forks the same stream. Seed zero's first two words are
16294208416658607535 and 7960286522194355700. This generator is for reproducible
simulations and tests; it is not a cryptographic generator.

`bounded(generator, upper, max_draws)` samples `[0, upper)` using rejection of
values below `(-upper mod 2^64) mod upper`, avoiding modulo bias for uniform words.
Zero upper rejects without advancing. Exhaustion returns the advanced state and
an error so callers can resume. A zero draw budget always exhausts valid bounds.
`entropy_bounded` uses the same bounded rule with an explicit random capability.
It cannot loop indefinitely waiting for an adversarial provider.

`entropy` returns a provider word; its quality is the provider's contract.
`seed_from_entropy` starts deterministic state from one such word. `fill` writes
little-endian bytes from successive words into an exclusive slice; a failed read
returns `FillError { written, error }`. Only that prefix was initialized by the
call, and the remaining suffix is unchanged. Empty fills invoke no provider.
Neither deterministic nor provider functions silently acquire authority.

The [example](../examples/standard-time-random/main.my) exercises arithmetic limits,
reproducible sequences and rejection. Native acceptance runs the same fixtures
under O0/O2 with undefined-behavior sanitization, plus explicit provider failure
and missing-authority cases.
