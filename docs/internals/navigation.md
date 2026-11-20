# Source navigation (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## Summary and filters for large projects

The complete document grows with every local and every relationship: 36 MB for
a generated 50,000-line project, 145 MB at 200,000 lines and 364 MB at 500,000.
So `index-project`
without a flag prints `navigation-summary-v1` instead — the snapshot digest and
compiler identity, totals, and one row per loaded module with its path, its
exported count and its declaration counts by kind — plus the queries that
drill down, with your entry path filled in. It skips the relationship walk,
and its size follows the module count: 15 KB at 50,000 lines, 58 KB at
200,000 and 144 KB at 500,000.

`--full` is the complete `navigation-v1` document, byte for byte what the
command printed by default before; it is streamed rather than built in memory.
The repository's own `navigation-v1` consumers under `scripts/` and `tests/` pass it.
