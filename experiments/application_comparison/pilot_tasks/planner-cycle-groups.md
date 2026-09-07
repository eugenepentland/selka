# Explain which jobs form cycles

Extend only the cycle error result with `cycles`, an array of cyclic strongly
connected groups. Include groups of two or more mutually reachable jobs and
singleton groups with a self-dependency. Do not include merely downstream blocked
jobs in a cycle group. Every cyclic job appears in exactly one group.

Sort IDs inside each group in ASCII order; sort groups lexicographically by their
ID arrays. Keep the existing sorted `blocked` array, including downstream jobs.
The full result is `{"error":"cycle","blocked":[...],"cycles":[[...],...]}`.
Other errors, their precedence, successful plan results and input schema are unchanged.

Cover independent cycles, connected cycles that merge into one strongly connected
group, self-loops, upstream removable jobs and downstream blockage. Do not return
an arbitrary DFS back-edge path as though it were the complete cyclic component.
