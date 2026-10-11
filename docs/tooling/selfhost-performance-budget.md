# Strict performance budget

`selfhost/tests/measure_performance_ratio.py` compares every workload and workflow separately against the frozen Zig host. Both the median and nearest-rank p95 must be at most 1.5 times the baseline. One failing row fails the result; fast rows cannot offset a slower check, compilation, test or runtime. Raw samples and command receipts remain in the JSON.

The initial corpus covers scalar loops, managed Unicode text/bytes loops and list construction/mutation/iteration/snapshot copies records with defaults, nested list mutation and returned snapshots, enum constructors/defaults/matches and checked failure propagation/consumption, with imports, two executed guest tests and generated release executables. It is an intermediate seven-package subset, not evidence that the entire language compiler is self-hosted. Unsupported selected forms fail visibly; the tool never removes them from its denominator. Broader language coverage must be added as ownership expands.

Run with qualified ReleaseFast hosts after correctness gates and through the approved FIFO launcher holding the gate and all three build reservations. The tool requires CPUs 2,3,10,11 and the inherited gate FD30. Specify each candidate boundary explicitly, for example `--candidate-mode BODY_CHECK=component`; other boundaries are forced to reference. Caller mode variables cannot alter provenance. The full sweep contains 36 rows across six workloads. Candidate body schema defaults to 5; baseline schema defaults to the frozen B2 schema 2. Explicit `--candidate-body-schema` and `--baseline-body-schema` retain compatibility with other qualified deployments.

Every workload first executes release guest tests with fact and leak verification. Timings disable those checks consistently for both hosts. Both hosts' native units are prewarmed before either is timed. Fresh compilation means a fresh private application cache, with shared native units already warm; it does not claim a cold filesystem, toolchain or machine. Warm compilation must compile zero new units. Forced cold test invocations execute both tests; warm tests must reuse exactly two validated receipts. Runtime rows time the generated release binary directly, including process startup, and verify exact exit status and output.

B2 retained evidence shows approximately 4.6–5.1 times native latency for the selected body component in warm/check/edit workflows. Hardware SHA-256 is already active. The narrow one-shot helper removes two FFI transitions for memory hashing without changing streamed artifact reauthentication, authenticated bytes, or shadow comparisons. Its effect requires isolated measurements; it is not presented as meeting the budget.

The [B3 list audit](../audits/selka-body-lists-2026-10-11.md) retains two strict
18-row measurements. Both fail all 15 compiler/test rows and pass only the
three short generated-runtime rows. A qualified whole-unit release producer
roughly halves the compiler/test medians but remains above budget. This result
must not be used as full-language or bootstrap acceptance.

The [B4 record audit](../audits/selka-body-records-2026-10-11.md) uses the same
qualified B4 ReleaseFast host for native reference and selected body checking.
Its 24-row sweep passes only the four short runtime rows; all 20 compiler/test
rows fail (roughly 4.4–7.2 times native median). Complete raw samples, cache
receipts and isolated admission records are retained. Correctness qualification
does not waive these performance failures.

The two B5 workloads each use two modules, exactly two guest tests and a generated main that returns 7. Variant work constructs defaulted fielded cases, matches them, and preserves record/list snapshots across copies and rebinding. Failure work exercises success wrapping, `try`, `fail`, repeated loop consumption and nested error-case matches. Every row remains mandatory even before B5 component qualification; unsupported candidate forms fail rather than disappearing from the sweep. Native controls do not establish component qualification or a passing performance ratio.
