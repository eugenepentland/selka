# Structured loop exits (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## Structured loop exits

Lowering uses the existing checked jumps and local drops, so every
exit path shares the same cleanup sequence.
The formatter, source maps, generic checker and duplicate analysis preserve the
new statements.
