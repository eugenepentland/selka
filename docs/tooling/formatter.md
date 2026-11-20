# The formatter

`selka fmt FILE.selka` writes the one canonical layout of a source file to stdout; `--check` is nonzero when the file differs from
it, `--write` replaces the file and `--diff` prints what would change. `fmt-module` formats a module file whose imports are not
loaded, and `fmt-project --check` checks every module a project reaches. The formatter reads tokens and the parse of the file and
never type-checks, so a draft whose names do not resolve still formats. `--check` prints one line for each file that differs,
`path:line:column: formatting differs: ` and what the formatter wants at the first difference, then ``selka fmt --write path` repairs it``.
It reads that off the two texts: a run of blank lines of another length (the formatter wants two between top-level declarations, except between
one-line constants that follow one another with no blank line), trailing whitespace, another indent, a missing final newline, or else the line as written and as wanted; a
file that is already canonical prints nothing and exits 0. The layout rules are in
the formatter's design note (`docs/experiments/formatter.md`); this page holds what changed the contract since.

## A block of constants stays together

One-line top-level `const` declarations (`public` and `private` included) that follow one another with no blank line between them
keep that layout: five `const S_NONE: int = 0` lines in a row stay five lines, and a comment above the block or between two of its
constants stays where it is. A constant that spans lines, a blank line between two constants and any other declaration still get the
two blank lines, so a source with a blank line between two constants keeps two, and the formatter's output is its own fixed point.

## Delimiters that take no trailing comma

A call, constructor, collection literal or parameter list whose content spans source lines keeps one item per line with a
trailing comma, so a diff that adds an item touches one line. A few delimiters are not item lists, and none of them takes a comma
after its last item, because the text would not parse:

- a parenthesized expression, `return (a and b)`: the one expression goes on a line of its own between the parentheses. A comma
  after it, `(a and b,)`, is a one-element tuple, which is not a value;
- an attribute's arguments, `@ensures(result >= 0, "message")`: the items stand on lines of their own, the last without a comma;
- a pattern that ends with the rest marker, `case atom(text, ..)`, the same way;
- a comprehension or generator, `sum(x * x for x in xs)`: on one line inside its delimiters;
- the type arguments of a keyword intrinsic, `accept_resource[network.Accepted](listener)`, which collapse like any type argument list.

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

A formatter must never write code that does not parse. `fmt`, `fmt-module` and `fmt-project` parse their output again, as the
module or program the input was, and compare its syntax with the input's before they write or print anything. Layout, comments, a
comma before a closing delimiter, the quoting of a string literal and the order of a `from` clause are not differences; a name,
an operator, a literal, a statement or an `import` directive is. A difference stops the command: nothing is written (not to the
file under `--write`, not to stdout), the status is 2, and the report names the input line of the construct and the formatted
line beside it.

```console
$ selka fmt both.selka
both.selka:4:9: error[E_FORMAT_VERIFY]: the formatted text does not parse, so nothing was written: E_SYNTAX: a one-element tuple is not a value; write the element alone or a two-element tuple (formatted line 3: `a and b,`)
```

`E_FORMAT_VERIFY` is a defect of the formatter, not of the source: report the file. The check costs one more lex and parse of the
output and one walk over both syntax tables, which adds 50% to 70% to the CPU time of `fmt` for a file the formatter changes (a
242 KB module: 12.3 ms, 20.7 ms with the check). A source that is already canonical, the usual case of `fmt --check`, is not
checked, because its output is its input, and costs nothing.
