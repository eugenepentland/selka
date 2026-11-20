# Typed holes (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## Running with holes

- No cache hides a hole from `check`. A debug build, `run` or `test` publishes check summaries too, and a function that holds a
  hole is left out of what they let a later check stand in, so `check` reports `E_TYPED_HOLE` after a debug build, in the same
  work directory or a new one beside a shared store. Nor does a refused check stop the next build from keeping the hole as a trap.
