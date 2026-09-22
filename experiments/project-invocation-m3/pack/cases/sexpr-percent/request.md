# Restore percent-literal handling

`app/` is the mylang port of the EDA S-expression reader (`sexpr/` holds the
tokenizer, parser, printer and AST; `tests/` holds the guest suite; `main.my` is
the CLI).

## Reported behavior

A user reports that tolerance values written with a percent sign no longer
behave like the other suffixed literals:

```sexp
(tolerance 10%)
```

The form above should carry **one** numeric child whose value is the number in
the source and whose spelling is preserved, exactly like `220k` or `100nF`. It
currently produces a different tree, so every count, sum and rendering that
depends on it is wrong.

## What is required

- Percent-terminated literals (`10%`, `0.1%`, `1.5%`) parse as scaled literals
  with the value the source spells.
- A standalone `%` is still the operator atom it is today (`(% a b)`, `a % b`).
- Values that continue with atom characters (for example `10%x`) keep their
  current behavior; do not widen the rule.
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
