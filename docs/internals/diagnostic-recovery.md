# Checking independent function faults (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## Checking independent function faults

Repeating `check`, `emit`, or `execute` on the
same rejected compilation preserves its errors without accumulating duplicates.
Use a new compilation for edited source, as before.
