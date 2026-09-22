# Restore rendering of nested empty forms

`app/` is the mylang port of the EDA S-expression reader (`sexpr/` holds the
tokenizer, parser, printer and AST; `tests/` holds the guest suite; `main.my` is
the CLI).

## Reported behavior

Empty forms disappear when a document is rendered. This document

```sexp
(a () (b ()))
```

should render back exactly as written, and an empty form inside a deeper list
should survive at every depth. Empty forms currently vanish from the output, so
parse → render → parse is no longer the fixed point it was.

## What is required

- An empty form renders as `()` wherever it appears: at the top level, as a
  direct child of a list, and nested at any depth.
- Non-empty forms keep their current layout, including the existing short-list
  and multi-line rules.
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
