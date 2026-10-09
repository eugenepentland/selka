# File-based stdin/stdout contract tests

`scripts/test_contract.py` runs one fresh process per selected case. It sends the
input file's exact bytes to stdin and compares the actual stdout to an expected
file. This covers the application boundary, including parsing and serialization;
it does not call typed guest functions or derive an oracle from the implementation.

From the repository root, with an already built application bridge:

```sh
python3 scripts/test_contract.py \
  --fixtures examples/contract-echo/fixtures/cases.json \
  -- zig-out/bin/selka-io --project examples/contract-echo
```

The same runner accepts any executable argument array after `--`; no shell
expansion is performed. Relative command/project arguments resolve against
`--cwd` (default: invocation directory). Fixture paths resolve against the
manifest directory. Each invocation prints one summary with passed, selected,
and total counts and an absolute path to the retained JSON report. At most five
short failure summaries go to stderr. Full captured output and comparisons are
in the report. An omitted `--report` creates a unique report in the system temp
directory; supply a new `--report path.json` for durable project storage. Existing
report files are rejected before execution and are never overwritten.

## Fixture format

```json
{
  "version": 1,
  "cases": [
    {
      "id": "normal-request",
      "input": "request.json",
      "expected": "response.json",
      "compare": "json",
      "expect_exit": 0
    },
    {
      "id": "malformed-request",
      "input": "malformed.bin",
      "expected": "empty.bin",
      "compare": "bytes",
      "expect_exit": 1,
      "expected_stderr": "diagnostic.txt"
    }
  ]
}
```

`compare` defaults to `json`, and `expect_exit` defaults to zero. JSON comparison
requires one strict UTF-8 JSON value; object order and whitespace are irrelevant,
array order and length matter, booleans are distinct from numbers, and duplicate
object keys and NaN/Infinity literals are rejected. Nesting is limited to 128
levels; unsupported numeric exponents produce a retained error report. Decimal numbers are parsed
exactly, so distinct large or high-precision numbers cannot pass through float
rounding. Numerically equal JSON numbers (such as `1` and `1.0`) compare equal.
Input is never parsed or rewritten by the runner. Use `bytes` for exact output,
including malformed JSON, non-UTF-8 bytes, empty output, and newline-sensitive
protocols. `expected_stderr`, when supplied, always compares exact bytes;
otherwise stderr is retained without asserting its contents. Expected exits are
explicit statuses from 0 through 255; timeout/output-limit termination never
counts as an expected failure.

All cases and fixture files are validated before launching any child, including
unselected cases. Empty suites, duplicate IDs, unknown fields, missing files,
and selectors matching nothing are errors. Use repeated `--case 'pattern*'`
options to select case IDs. Every selector must match. Reports retain both total
and selected counts; running a subset does not claim the full suite passed.

`--timeout 30` bounds each case in seconds. `--max-output-bytes 1048576` bounds
each captured output stream independently. Exceeding either stream cap kills
the process group and fails the case; the report explicitly marks the retained
output as a prefix. Stdin uses a temporary file to avoid input/output pipe
backpressure deadlocks. Process groups are cleaned up on completion, timeout,
and exceptions, including surviving descendants. This is a POSIX runner, not a
sandbox for hostile executables. Fixture files are trusted local test assets;
the output cap does not bound fixture file size.

Exit status is 0 for all selected cases passed, 1 for case failures, and 2 for
configuration, launch, or report-writing errors. Reports contain exact input,
expected output, actual output and stderr as base64 plus readable text and
SHA-256 values. With output truncation, hashes describe retained prefixes.

Run the runner's regression checks, including actual guest byte/JSON echo:

```sh
python3 tests/contract_runner.py --runner zig-out/bin/selka-io
```

These are implementation checks, not development-speed evaluations. The runner
does not build programs, generate expected behavior, perform schema fuzzing, or
claim coverage beyond the explicitly selected fixtures.
