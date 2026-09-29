## Task: `route`

Write a shortest-path program. Arguments: a graph file, a start node name and a goal
node name.

- Each non-blank line of the graph file is `FROM TO WEIGHT`, fields separated by one or
  more spaces or tabs (leading/trailing whitespace allowed). Names are any non-blank
  tokens; WEIGHT is a non-negative integer (decimal digits only, below 10^9). Each line
  is an **undirected** edge; the same pair may appear several times. Lines whose first
  non-blank character is `#` are comments.
- A line that does not have exactly three fields, or whose weight is not decimal
  digits, is an error: print `error: line L: bad edge` (1-based line number) to standard
  error and exit with status 2.
- Print the minimum total weight and one shortest path:
  ```
  cost 8
  path A -> C -> B -> D
  ```
  The test graphs have a unique shortest path. If start equals goal, the cost is 0 and
  the path is the single node.
- If either node does not appear in the graph, or the goal is unreachable, print
  `unreachable` to standard output and exit with status 1.
- If the file cannot be read, print `error: cannot read <path>` to standard error and
  exit with status 2. With the wrong number of arguments, print
  `usage: route GRAPH FROM TO` to standard error and exit with status 2.
- A graph with 50,000 nodes and 200,000 edges must be answered in well under 10 seconds.
- Include unit tests for parsing and for the shortest-path search.
