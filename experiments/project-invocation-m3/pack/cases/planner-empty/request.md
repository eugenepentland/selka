# Restore the empty-manifest result

`app/` is the workflow dependency planner: a byte-I/O program that reads one
JSON request on stdin and writes one JSON response on stdout (`main.my`,
`planner.my`, `schema.my`, `json.my`, `output.my`).

## Reported behavior

A manifest with no jobs no longer produces the contractual empty plan. The
request

```json
{"cases":[{"version":1,"jobs":[]}]}
```

must produce a result with an empty order, no layers, no timings and makespan
zero, in the same shape as every other successful result. It currently produces
a different result, so a caller that plans an empty dependency set reads the
wrong response.

## What is required

- An empty job list returns the empty successful plan with `makespan` 0, matching
  the documented result shape exactly (field names, types and empty arrays).
- Invalid envelopes, invalid manifests and non-empty plans keep their current
  behavior.
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
