# The formatter

`selka fmt FILE.selka` writes the one canonical layout of a source file to stdout. It reads tokens and the parse and never
type-checks, so a draft whose names do not resolve still formats.

| Command | What it does |
| --- | --- |
| `fmt FILE` | Prints the canonical layout. |
| `fmt --check FILE` | Nonzero when the file differs. Prints `path:line:column: formatting differs: ` and what the formatter wants at the first difference (a blank-line run of another length, trailing whitespace, another indent, a missing final newline, or the line as written and as wanted), then the `fmt --write` command that repairs it. A canonical file prints nothing and exits 0. |
| `fmt --write FILE` | Replaces the file. |
| `fmt --diff FILE` | Prints what would change. |
| `fmt-module FILE` | Formats a module file whose imports are not loaded. |
| `fmt-project --check` | Checks every module a project reaches. |

## A block of constants stays together

One-line top-level `const` declarations that follow one another with no blank line keep that layout: five
`const S_NONE: int = 0` lines in a row stay five lines, and a comment above the block or between two constants stays
put. A constant that spans lines, a blank line between two constants and any other declaration get the usual two blank
lines.

## Delimiters that take no trailing comma

A call, constructor, collection literal or parameter list that spans source lines keeps one item per line with a trailing
comma. A few delimiters are not item lists, and none takes a comma after its last item, because the text would not
parse:

- a parenthesized expression, `return (a and b)`: the expression goes on a line of its own (`(a and b,)` is a
  one-element tuple, which is not a value);
- an attribute's arguments, `@ensures(result >= 0, "message")`, and a pattern that ends with the rest marker,
  `case atom(text, ..)`: one item per line, the last without a comma;
- a comprehension or generator, `sum(x * x for x in xs)`: on one line inside its delimiters;
- the type arguments of a keyword intrinsic, `accept_resource[network.Accepted](listener)`.

A tuple, a call and a constructor keep their trailing comma. The formatter writes this source as it stands:

```selka
func both(a: bool, b: bool, c: bool) -> bool:
    return (
        a and b
        or c
    )


func main() -> int:
    if both(True, False, True):
        return 0
    return 1
```

## The safety net

`fmt`, `fmt-module` and `fmt-project` parse their output again and compare its syntax with the input's before they write
or print anything. Layout, comments, a comma before a closing delimiter, string quoting and the order of a `from` clause
are not differences; a name, an operator, a literal, a statement or an `import` directive is. A difference stops the
command: nothing is written, the status is 2, and the report names the input line and the formatted line.

```console
$ selka fmt both.selka
both.selka:4:9: error[E_FORMAT_VERIFY]: the formatted text does not parse, so nothing was written: E_SYNTAX: a one-element tuple is not a value; write the element alone or a two-element tuple (formatted line 3: `a and b,`)
```

`E_FORMAT_VERIFY` is a defect of the formatter, not of the source: report the file. A canonical source is not
re-checked.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/formatter.md).
