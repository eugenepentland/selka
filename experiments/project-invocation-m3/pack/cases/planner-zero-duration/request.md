# Restore timing for zero-duration jobs

`app/` is the workflow dependency planner: a byte-I/O program that reads one
JSON request on stdin and writes one JSON response on stdout (`main.my`,
`planner.my`, `schema.my`, `json.my`, `output.my`).

## Reported behavior

Jobs whose duration is zero are no longer timed correctly. A zero-duration job
occupies no time, so it starts and finishes at the instant its prerequisites are
done, and a chain of zero-duration jobs finishes in zero time. The reported
`start`/`finish` values for such jobs are currently wrong, which also moves the
`makespan`.

## What is required

- A job with duration 0 has `finish == start`, and its successors begin at that
  same instant.
- Positive durations, layer computation and the contractual ordering keep their
  current behavior.
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
