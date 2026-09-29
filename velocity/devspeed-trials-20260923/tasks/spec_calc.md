## Task: `calc`

Write an interpreter for a tiny line-oriented calculator language. The program takes
one argument, the path to a program file.

- Each line is one statement: `let NAME = EXPR` or `print EXPR`. Blank lines and lines
  whose first non-blank character is `#` are ignored. Lines are numbered from 1,
  counting every physical line.
- EXPR supports: integer literals (decimal digits), variable names
  (`[A-Za-z_][A-Za-z0-9_]*`), binary `+ - * / %` with the usual precedence (`* / %` bind
  tighter than `+ -`) and left associativity, unary minus, and parentheses. Spaces and
  tabs between tokens are ignored.
- Values are 64-bit signed integers (tests never overflow). `/` truncates toward zero
  and `%` takes the sign of the left operand (like C): `-7 / 2` is `-3`, `-7 % 3` is `-1`.
- Process the file line by line: tokenize the line, parse it into a syntax tree, then
  evaluate the tree (evaluate the left operand before the right). `print` writes the
  value on its own line. `let` may reassign an existing variable.
- On the first error, print exactly one line `error: line L col C: MESSAGE` to
  **standard output** and exit with status 1 (output from earlier lines stays). L and C
  are 1-based; C counts characters in the line. MESSAGE is one of:
  - `unexpected character 'X'` — at a character that cannot start a token (the whole
    line is tokenized before parsing, so this wins over parse errors on the same line);
  - `expected expression` — where an operand was required but the next token is not
    an integer, name, `-` or `(`; at the end of the line the column is
    (line length + 1);
  - `expected ')'` — at the token found instead of the closing parenthesis (or line
    length + 1 at end of line);
  - `unexpected token` — the line does not start with `let` or `print`, `let` is not
    followed by a name and `=`, or tokens remain after a complete statement; the column
    is that token's;
  - `undefined variable 'NAME'` — at the name;
  - `division by zero` — for `/` or `%` with a zero right operand, at the operator.
- If the file cannot be read, print `error: cannot read <path>` to standard error and
  exit with status 2. With the wrong number of arguments, print `usage: calc FILE` to
  standard error and exit with status 2.
- A 20,000-line program must run in well under 10 seconds.
- Include unit tests for the tokenizer, the parser and the evaluator.
