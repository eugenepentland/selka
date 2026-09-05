# T: separate project-verification driver

Status: implemented in `scripts/verify.py`, with the repository's explicit 11-step
`verify.json` manifest. This is a Python standard-library workflow tool, separate
from compiler type checking and VM execution. It requires Python 3 and POSIX process
groups; no package installation or service is needed.

```sh
python3 scripts/verify.py verify.json --report /tmp/mylang-verification.json
python3 scripts/verify.py verify.json --only memory-parity
python3 scripts/verify.py verify.json --only 'tests-*'
```

The command writes JSON to stdout and optional `--report`, with progress on stderr.
It exits 0 when every selected step passes, 1 for failed/blocked selected steps,
and 2 for manifest/selection/host report errors. It does not install tools, edit
source, accept snapshots, or interpret advisory warning counts as correctness.

## Declared workflow and selection

Manifest version 1 contains an ordered, nonempty `steps` list. Each step has a
unique ID and a kind: build, format, check, test, parity, mutation, spec, benchmark,
or advisory. Unknown fields, duplicate JSON keys/IDs, invalid types/budgets, and
unknown/forward dependencies are rejected before execution. `depends_on` names
must refer to earlier steps, making the declared order acyclic and reviewable.

Command steps contain explicit argument arrays in `commands`. They execute without
an implicit shell, with manifest-directory cwd, inherited environment, and closed
stdin. The manifest is executable project configuration; it may intentionally name
a shell or any other program. Executed commands and expected results are retained
in the JSON alongside manifest SHA-256, cwd, timestamps, and actual output.

`--only` selects step IDs using glob patterns. Every pattern must match. Dependency
closure is added automatically and recorded separately from requested steps. A
failed dependency blocks dependents without claiming they ran; independent selected
steps continue. Unselected steps explicitly say they were not run and make no
compilation/test-result claim. All steps remain listed in declaration order.

`selected_passed` means the selected checks met their declared expectations.
`full_manifest_passed` additionally requires every manifest step to be selected and
pass. Neither field claims that every repository test exists in the manifest, that
a subprocess's internal filters selected its full suite, or that the language
roadmap is complete. Selection is at workflow-step granularity. Subprocess output
is retained, including cache hits and the subprocess's own test-selection evidence.

## Evidence by kind

- Build/format/check/test/advisory steps expect exit 0 by default. Optional exact
  stdout and stderr-substring expectations make concrete assertions.
- Parity requires two or more actual commands, validates each expected result, then
  compares exit status and byte-identical stdout. Stderr remains diagnostic evidence,
  not parity output. The supplied fixture compares general/arena VM memory backends;
  it remains separate from [scalar native parity](native-execution.md), which now runs
  inside the compiler-test steps.
- Mutation steps require a nonzero expected exit and a diagnostic marker. The
  supplied immutable-assignment sentinel verifies that a deliberate invalid change
  is rejected for the intended reason. This is not mutation generation, a mutation
  score, or evidence that unrelated bugs would be caught.
- Spec steps read a declared file and require a nonempty marker. They record the
  file digest. Marker presence verifies the link target, not implementation conformance
  to the prose or complete documentation coverage.
- Benchmark steps repeat actual commands and record full-command elapsed seconds,
  including startup. Time has no pass/fail threshold; exit/output assertions still
  apply. The execution timeout is a liveness limit, not a performance acceptance gate.

No runtime instrumentation is introduced. Coverage and assertion coverage remain
explicitly unmeasured even when runtime output assertions pass.

## Execution limits and failures

Command timeout defaults to 60 seconds; steps can declare another finite positive
value. On timeout the POSIX process group is killed and waited for. Launch errors,
timeouts, unexpected exits/outputs, and missing diagnostic markers fail the step.
Interruptions also clean up the running group before propagating.

Captured stdout/stderr are held in temporary files while running. Each returned
stream is limited to 1 MiB by default (`max_output_bytes`); exceeding it marks the
step failed and output truncated. This limits report data, not temporary disk growth
before process exit or timeout. Lossless base64 of captured bytes supports exact comparisons without conflating
invalid UTF-8; SHA-256 records fingerprints and human text uses replacement decoding. The limits
are not a sandbox for executable manifest commands.

## Acceptance evidence

Eight standard-library tests cover filtered selection/dependencies, failure blocking,
independent progress, executed parity including distinct invalid UTF-8 byte outputs,
mutation diagnostics, timeout/output/launch failures, spec markers, repeated benchmark
observations, invalid/duplicate manifests, and actual CLI exit/report behavior.
`zig build test` runs these tests alongside the existing Zig/CLI suites.

The complete repository manifest passed all 11 steps. Debug and ReleaseFast Zig
suites passed from cache; each invocation executed all eight driver tests. The
filtered memory-parity run selected exactly build + memory-parity and correctly
reported selected success with full-manifest success false. Formatting checks,
source checking, expected runtime values, the mutation sentinel, specification
marker, and three timing samples passed. Hosted CI has not run.

Modules/schemas will need richer reference and specification identities; broader native execution needs additional parity fixtures. These future language tracks remain
pending. The manifest is an explicit starting verification set, not an exhaustive
claim about future features or all possible test inputs.
