# The language: how it works

Implementation detail moved out of the user guide, [python-syntax.md](../python-syntax.md). Each heading is the guide's heading.

## Prelude builtins

`sorted` and `sort(mut values)` use a stable merge that keeps the runs a list already has, with one work buffer of at most half the list, so ordered and reverse-ordered lists sort in linear time and every list in `O(n log n)`.

Keyed sorting uses key storage and scratch space. Because keys are computed in list order, a key function that traps on several elements reports the first of them in list order; the module's earlier recursive merge asked for keys in a different order.
