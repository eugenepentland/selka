# Python workflow planner

Independent standard-library implementation of `workflow-planner-v1.md`. Requires
Python 3.10 or newer. No package installation or build step is required.

From this directory:

```sh
python3 planner.py < request.json
python3 -m unittest -v
```

The CLI reads a single bounded UTF-8 JSON request from stdin and emits one JSON
response to stdout. Defined input errors return exit status zero. Parsing rejects
duplicate object keys, nonfinite numbers, and integers outside signed 64-bit range
before any manifest is evaluated. A string-aware scan enforces the maximum JSON
container nesting depth of 64 before invoking the JSON decoder. Every decoded
string and object key is checked for Unicode scalar values: paired surrogate
escapes are accepted, and unpaired surrogate escapes reject the whole request.
Schema and graph validation follow the contract's
phase precedence. A min-heap drives deterministic topological ordering; dependency
depths produce synchronous layers, and prerequisite finish times determine timing.

Tests were written independently from the contract without importing or inspecting
the coordinator oracle, its tests, other implementations, or hidden cases. They
exercise strict transport, validation precedence, deterministic reporting, cycle
descendants, parallel timing, and the maximum permitted chain.

This implementation deliberately covers the small v1 planner only: there is no
resource-constrained scheduling, persistence, network access, or subprocess helper.
