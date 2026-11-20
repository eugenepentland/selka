# Constant length parameters (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## Constant length parameters

Both type and length arguments participate in specialization identity.

generated instance names print their numeric arguments. Existing limits remain: at most 16 combined arguments, 4,096 function specializations, bounded nominal/array shape counts and layout work.

Symbolic checking keeps unknown lengths separate from concrete zero.

Tests cover nominal element identities, zero and distinct lengths, forwarding, exported constructors and source relocation, formatter round trips, allocation-failure cleanup, specialization key ownership and invalid uncalled templates. Existing generic array, nominal, API and execution suites also pass. Native execution uses the resulting concrete array layouts; no dynamic array length is added to the representation.
