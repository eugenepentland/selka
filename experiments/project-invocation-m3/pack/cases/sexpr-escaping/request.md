# Restore quote and backslash handling in strings

`app/` is the mylang port of the EDA S-expression reader (`sexpr/` holds the
tokenizer, parser, printer and AST; `tests/` holds the guest suite; `main.my` is
the CLI).

## Reported behavior

Strings whose content ends with an escaped backslash are read incorrectly. This
document is valid — the string closes at the quote after `\\`, and the second
string is quoted text:

```sexp
(note "ends with a backslash \\" "quoted \"inner\" text")
```

It currently swallows the text that follows, so the parse either merges two
strings or fails at the end of the file. A quote is closed by the *first quote
that is not escaped*, where a backslash escapes the next byte, and an escaped
backslash is not itself a quote-escaping backslash.

## What is required

- A quote preceded by an odd number of consecutive backslashes does not close the
  string; one preceded by an even number (including zero) does.
- Strings without backslashes, strings with `\"` inside, and escaped newlines
  inside strings keep their current behavior, byte for byte.
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
