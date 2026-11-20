# Change review (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

### Reading the page

The page, from `--html`, and the terminal summary follow the same order. A reviewer
decides in this order.

1. **Header.** The verdict, passes or refused, the range, and the title. The title is
   the first change note's title, else the first decision's title, else the range. A
   lead sentence counts the public declarations and says how many a decision explains.
   A strip of facts follows: public changes, decisions, tests at the head, test changes
   and functions edited.
2. **Needs your judgment.** The entries that need a decision, in this order: the gate's
   refusals; a side whose declarations did not load; new authority, when a public
   function gains a capability; existing tests that expect something different; removed
   tests; docstring examples whose output changed; possible patching, which is a
   heuristic; and generated files that changed. Each entry names its items. When the
   list is empty, the page says so.
3. **Why, in the author's words.** Each change note, with its title and summary, then
   each decision, with what it explains, why and what it rejected. A change with neither
   shows a warning.
4. **Public functions and types.** Grouped by module. Each declaration shows its kind,
   whether it was added, changed or removed, and the sentences that describe the change.
   A chip names the decision that explains it, or says "no decision". The old and new
   signatures are folded below.
5. **What behaves differently.** Docstring examples whose output changed, shown before
   and after. Existing tests whose expectations changed, as diffs. Removed tests. New
   tests, each name read as a sentence.
6. **Inside the code.** Each function whose body changed outside the tests, private
   ones included, with its lines and decision points before and after. The possible
   patching signals appear under each function. The edit is folded, capped at 80 lines
   per function and 600 per review. Helpers in test files are listed on one line.
7. **Also in this change.** Only when present: issue ids that comment lines add or
   remove, generated files with their line counts, and the test counts when `--test` ran.

The possible-patching signals are heuristics, and none of them refuses a change. There
are three kinds. A special case: a function compares one subject against two or more
literals that the base did not. A copy: a new block of at least four code lines is at
least 80% alike, with names and literals masked, to another block in the same function.
A flag: a new `bool` parameter that the body branches on.
