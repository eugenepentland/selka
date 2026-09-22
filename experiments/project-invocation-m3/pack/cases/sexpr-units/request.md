# Restore mil-to-millimetre conversion

`app/` is the mylang port of the EDA S-expression reader (`sexpr/` holds the
tokenizer, parser, printer and AST; `tests/` holds the guest suite; `main.my` is
the CLI).

## Reported behavior

Dimension values given in `mil` no longer convert correctly. A clearance
written as `10mil` should measure 0.254 mm and `1000mil` should measure
25.4 mm, and both currently come out off by a constant factor, so every
`value_sum` and every rendered `mm` value that came from a `mil` literal is
wrong. Values written directly in `mm` are unaffected.

## What is required

- `mil` dimensions convert to millimetres with the exact factor the contract
  uses, across small, large and fractional magnitudes (for example `1mil`,
  `2.5mil`, `1000mil`), so the printed value is the normalised millimetre value.
- `mm` dimensions, plain numbers and every suffixed literal (`220k`, `100nF`,
  `10%`) keep their current values.
- The same behavior is required for every input, not only the examples in the
  public fixtures.

## How to check your work

The active project is described by `app/project.json`. `MYLANG_M3_PROJECT`
points at that description; it names the project's entry and verification
manifest with paths relative to the description's directory.

{{COMMAND}}

## Constraints

- Work only inside this working copy.
- Do not edit `app/tests/`, `app/verify.json` or the public fixtures; the
  project's checks are the contract, not part of the repair.
- Do not spawn subagents.
- The session deadline is {{DEADLINE}} seconds. When you are done, leave the
  repaired sources in `app/` and run the project's verification once more so its
  final result is on the record.
