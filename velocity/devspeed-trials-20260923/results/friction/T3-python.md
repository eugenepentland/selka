# FRICTION.md — T3-python (`route`)

Overall this task was smooth. Python's standard library (`heapq`, `re`, `sys`,
`tempfile`, `unittest`) covered every need directly — no missing library, no
compiler error, no runtime crash, no tool that fought me. The only friction
was in reading TASK.md itself, and it cost minutes, not attempts.

## Points of friction

1. **Rule-ordering ambiguity for `start == goal`.** TASK.md gives two rules
   in sequence: "If start equals goal, the cost is 0 and the path is the
   single node," followed later by "If either node does not appear in the
   graph, ... print `unreachable`." It never says which check runs first
   when `start == goal` names a node that never appears in the graph file
   at all. I read the two bullets a few times, then decided the
   membership check must dominate (a node that never appears "in the
   graph" can't have a cost-0 self path either), and implemented
   `shortest_path` to check membership before the equality shortcut. No
   error message was involved — this was a documentation read, not a
   tool failure — but it's the one place I second-guessed myself. Maybe
   3 minutes, no retries since there was nothing to run yet.

2. **Unclear status of the "below 10^9" weight bound.** The WEIGHT field
   is described as "a non-negative integer (decimal digits only, below
   10^9)," but the error rule two lines later only says a line is bad "if
   ... the weight is not decimal digits" — it never says what to do if a
   weight parses fine but is `>= 10^9`. I treated the bound as a
   guarantee about the test inputs rather than something to validate
   (Python's arbitrary-precision `int` made this a non-issue either way),
   but I'd have appreciated the spec saying explicitly "this can never
   happen in test input" vs. "reject it as a bad edge."

That's the whole list. Nothing else — argument parsing, file I/O, exit-code
conventions, and the Dijkstra implementation all worked exactly as expected
on the first pass, and the 50k-node/200k-edge timing test (`prog` returned
in 0.37s) needed no tuning.

## Ranked changes that would have saved the most time

1. **State explicit rule precedence when two conditions can both apply.**
   In TASK.md, say outright whether the `start == goal` shortcut is
   checked before or after the "node does not appear in the graph" check.
   This is a one-clause fix and would have removed the only real judgment
   call in the whole task.
2. **Say whether documented value bounds (like "below 10^9") are
   guarantees about the input or validation requirements on the
   program.** A single word — "guaranteed" vs. "reject values at or
   above this" — removes the ambiguity for every such bound in a spec.
3. **Nothing tooling-related to report, but if a future trial in this
   series wants comparable friction data across language runs, it should
   note explicitly that this run uses only the standard library** — that
   constraint was easy to honor here but is worth confirming didn't get
   silently relaxed elsewhere, since the plain-stdlib affordances
   (`heapq`, `unittest`, `re`) doing all the work is exactly why this run
   had so little friction to report.
