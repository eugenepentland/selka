# Sets (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## Representation and cost

A set is a dictionary from its elements to unit: the same insertion-ordered entry
list and open-addressing hash index, with owned backing storage. Membership, `add`, `remove` and `discard` probe the index
once. Removing an element from the middle takes its slot out of the index and leaves
its entry to be squeezed out the next time the entries are read in order, so a
removal moves nothing; `dicts.pop(mut d, key)` shares that path. The combining operators
and the subset tests walk one operand and probe the other, so they are linear in the
operands' sizes.
