# Restore earliest-finish propagation along dependency chains

`app/` is the workflow dependency planner: a byte-I/O program that reads one
JSON request on stdin and writes one JSON response on stdout (`main.my`,
`planner.my`, `schema.my`, `json.my`, `output.my`).

## Reported behavior

Long dependency chains no longer push their successors later. When job `b`
depends on `a`, `b` must start when `a` finishes; with several links the final
`finish` values and the `makespan` must accumulate the whole chain. Chains
currently report an early make span, so a caller reading the schedule sees work
finishing before its prerequisites do.

## What is required

- Each job starts at the latest finish among its dependencies and finishes at
  `start + duration`, along chains of any length.
- Independent jobs, ordering and layer computation keep their current behavior.
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
