# Restore the documented manifest-count boundary

`app/` is the workflow dependency planner: a byte-I/O program that reads one
JSON request on stdin and writes one JSON response on stdout (`main.my`,
`planner.my`, `schema.my`, `json.my`, `output.my`).

## Reported behavior

The documented size boundary is off by one. A request may carry **at most 64**
manifests in `cases`, and a manifest may carry **at most 128** jobs; a request
exactly at the boundary must be accepted and one beyond it must be rejected as
`invalid-request`. Requests at the boundary are currently rejected, or requests
past it are accepted, depending on which side moved.

## What is required

- Exactly 64 manifests and exactly 128 jobs per manifest are accepted.
- 65 manifests or 129 jobs in a manifest produce the whole-request
  `invalid-request` error, with no partial results.
- All other schema and validation behavior keeps its current rules.
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
