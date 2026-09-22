# Restore lexical ordering of simultaneously ready jobs

`app/` is the workflow dependency planner: a byte-I/O program that reads one
JSON request on stdin and writes one JSON response on stdout (`main.my`,
`planner.my`, `schema.my`, `json.my`, `output.my`).

## Reported behavior

When several jobs are ready at the same time, the plan no longer chooses them in
ASCII order. `order` must pick the ASCII-smallest currently ready job after each
individual removal, and each `layers` round must list all currently ready jobs
sorted by ID. Requests whose jobs are declared in a different order currently
produce a different plan, so the result depends on input order.

## What is required

- `order` is the contractual topological order: the ASCII-smallest ready job at
  each removal step.
- `layers` rounds contain the ready jobs sorted by ID, and the layer boundaries
  do not change.
- The result does not depend on the order jobs appear in the request; error
  reporting keeps its current behavior.
- The same behavior is required for every input, not only the examples in the
  public fixtures.

## How to check your work

The active project is described by `app/project.json`. `MYLANG_M3_PROJECT`
points at that description; it names the project's entry and verification
manifest with paths relative to the description's directory. The application
runs through the frozen byte-I/O host, and its own contract suite runs through
`bin/planner-checks`.

{{COMMAND}}

## Constraints

- Work only inside this working copy.
- Do not edit `app/test_cli.py`, `app/verify.json` or the public fixtures; the
  project's checks are the contract, not part of the repair.
- Do not spawn subagents.
- The session deadline is {{DEADLINE}} seconds. When you are done, leave the
  repaired sources in `app/` and run the project's verification once more so its
  final result is on the record.
