# Generic call inference (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## Generic call inference

Recursive and mutually recursive calls infer from signatures without expanding bodies during abstract checking.

The back end receives the concretely specialized checked program; inference adds no runtime work.

## Helpers a generic function calls

The abstract check of a generic function walks the generic functions only.
