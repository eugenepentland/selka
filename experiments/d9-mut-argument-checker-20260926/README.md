# Indexed mutation argument checker correction

The exact `clone_during(mut original[0], original)` source in `exact.my` aborted
in Debug checking before backend selection. Its transparent mutation marker
reuses the checked target's typed data. Accounting from that reused dictionary
index incorrectly consumed two temporaries after the target had already consumed
its operands and left one result. The marker now consumes that one result.
Syntax-only literal accounting is grouped into a switch with unchanged behavior.

The permanent unit test checks the exact source and preserves missing-marker and
nonassignable-target diagnostics. The language regression checks that the pinned
copy remains independent. This change does not modify code generation or runtime
ownership policy.

Validation on base `7998e84c` plus this checker change:

- New checker filter: 13/13 (two named tests plus 11 root blocks).
- Existing M4 mutation-marker filter: 19/19 (eight named plus 11 root blocks).
- Debug install: 12/12 build steps, Guardian88; whole-tree commit gate also runs.
- Three language fixtures: nine assertions in each GC/RC and actual QBE/LLVM
  combination, 36 total. `--force` prevents cached test verdicts. One invocation
  reported `SourceChanged`; the retained retry runs all four affected assertions
  successfully. Both original and retry receipts are archived.
- The exact original program prints `[13]`, `13`, `7` in all four combinations.
  Both RC runs allocate/retire22, acquire/release7/29 and hold/release18/18.
- Zig and guest formatting checks and `git diff --check` pass.

The initial unit draft expected a different missing-marker suggestion string;
the test was corrected to preserve the existing `(mut values[0])` suggestion.
The initial production draft exceeded Guardian's cognitive-complexity limit by
one. Grouping existing syntax-only cases into one switch resolved it without a
waiver. Failed receipts remain archived. Full combined gates belong to the parent
integration run; these focused results are not a WP-4 acceptance claim.

## Separate admitted source exposes code-generation defects

`change.my` is preserved for the independent follow-up. It writes through the
indexed mutation argument and then reads the containing read-only argument.
The documented snapshot contract requires `7`, `13`. Both actual backends give
GC `13`, `13` and RC `7`, `7`. RC counts balance (allocate/retire16,
acquire/release4/20, hold/release8/8), so balance alone does not establish semantic
correctness. The original broad guest draft included this expectation and failed;
its receipt remains `guests-initial-extra-case.json.gz`. The expectation has not
been weakened or added to the passing regression. The core agent owns a separate
runtime/compiler correction; the frontend fix merely makes this source checkable.

`identity.json` names the Debug compiler; compressed receipts preserve commands,
results and stderr. LLVM commands use `--release` without a QBE override.
