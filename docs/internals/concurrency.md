# Concurrency: how it works

Implementation detail moved out of `docs/concurrency.md`. The guide keeps the user-visible rule.

## The pool's size

- `--threads N` on `selka run`, `selka build --run` and `selka test` sets the
  number of task threads, from 1 to 256. The flag is not part of any receipt key,
  so a test answered from a receipt is the same whatever thread count it ran with.

## Limits

- **One thread in test children.** A test child runs one thread: its default step and
  frame budgets force it, and `--threads` does not change that. Test receipts for a test
  that calls `parallel.map` are not reused: the stdlib map calls its function indirectly,
  which the receipt rule treats as unknown input. A test that calls `parallel.threads()`
  or `parallel.cpus()` is not reused either, because no key binds either count. Group
  tests are reused.
