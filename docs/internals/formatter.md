# The formatter (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## The safety net

The check costs one more lex and parse of the
output and one walk over both syntax tables, which adds 50% to 70% to the CPU time of `fmt` for a file the formatter changes (a
242 KB module: 12.3 ms, 20.7 ms with the check). A source that is already canonical, the usual case of `fmt --check`, is not
checked, because its output is its input, and costs nothing.
