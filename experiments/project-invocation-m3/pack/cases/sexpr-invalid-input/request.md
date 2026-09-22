# Restore rejection of unterminated strings

`app/` is the mylang port of the EDA S-expression reader (`sexpr/` holds the
tokenizer, parser, printer and AST; `tests/` holds the guest suite; `main.my` is
the CLI).

## Reported behavior

A malformed document is accepted instead of being rejected. A quoted string that
is never closed now reaches the end of the file without an error:

```sexp
(design (note "unterminated
```

The reader reports success for input like this, so a truncated file silently
produces a tree. Before, this category of malformed input was rejected with a
located lexical error.

## What is required

- A quoted string that reaches the end of the source without a closing quote is
  rejected: the CLI exits 1 and reports an `unterminated string` error located
  at the opening quote.
- Every other string behavior is unchanged: escaped quotes inside a string do
  not close it, a literal newline inside a string is allowed, and a string that
  does close is parsed exactly as it is today.
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
