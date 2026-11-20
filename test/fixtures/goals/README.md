# Pinned examples for the goals register

The register is `docs/goals.md`. Each page under `docs/` here holds the pinned examples of one goal, as fenced examples
with the directives of the documentation gate (`docs/experiments/doc-examples.md`).

- An `H` example shows the goal holding.
- An `X` example pins a known exception to today's behaviour. When a fix lands, the example fails; update it and
  `docs/goals.md` in the same change.

A pin starts a paragraph with its id in bold, `**G9-H1.**` or `**G7-X1 and G7-X2 (what it shows; W3).**`, and is followed by
its example in a `selka` fence. Every id is cited in `docs/goals.md` and every id the page cites is defined here.

Run them:

```bash
zig-out/bin/selka doctest test/fixtures/goals
```

The folder is laid out as a documentation root (`docs/*.md`) so that the existing example runner reads it unchanged.
The gate runs them: the action `goals_register` (`zig build test-goals`, driver `tests/goals_register.py`) runs the command
above and checks `docs/goals.md` against these pages. "How this page is checked" in `docs/goals.md` states the format.
