# Independent EDA inspector in `.my`

This unscored construction implements `contracts/eda-inspector-v1.md` using the
installed raw-byte VM host. The application was written from the contracts,
language specification, documentation, and ordinary language examples. No
coordinator oracle, hidden cases, or other application baseline was consulted.

From the language checkout:

```sh
zig-out/bin/mylang-io --project experiments/application_comparison/baselines/eda/my < request.json
python3 experiments/application_comparison/baselines/eda/my/test_cli.py
python3 experiments/application_comparison/baselines/eda/my/test_cli.py --stress
```

The current baseline was migrated in untimed preparation on 2026-09-07. See
[the parity audit](../../../../../docs/experiments/eda-stdlib-parity.md). Its original
independent construction provenance and dated calibration receipts remain historical;
the migrated version has subsequently been checked against the public construction oracle.

`std_text::read` acquires at most 1 MiB of raw input, and `std_json::parse` performs
strict JSON/UTF-8 transport decoding through the shared language runtime. The
application owns envelope and board schemas, validation precedence, reference
resolution, geometry, connectivity, report structure, and exact SVG layout.
`io.my` still declares only input length, raw byte lookup, and output byte append.
The Python test driver is evaluator tooling, never an application dependency.

## Implementation

The JSON document is an owned standard-library numeric tape with decoded UTF-8
bytes and six-word nodes. Queries use `std_json::get/field/equal/compare/textis`;
no local JSON parser, numeric lexer, duplicate-key hash table, or Unicode decoder
remains. Schema-validated ASCII identifiers can be emitted directly in JSON and
SVG attributes. General decimal emission uses `std_text::number`, including its
signed-minimum-safe implementation. Fixed output text uses `std_text::emit`.

Board processing uses a 17,536-word scratch workspace. Components, nets, references,
and pins are sorted through `std_order::sort` using precomputed application keys
and a reusable 16,384-item scratch buffer. `std_ascii::matches` checks the explicit
identifier grammar. Binary searches resolve components
and connected pins. Normalized rectangles are cached before the pair scan. Exact
signed 64-bit geometry remains application logic; the common contract bounds keep
squared gaps in range. Findings stream in code/subject order, and net spans use
doubled centers with upward rounding. The raw-byte VM host buffers output and
publishes it only after zero return; parsing completes before report emission.

The following section records the **original construction**, before this migration.
Its old parser representation, timings, and executable hashes do not describe the
current source. New validation is recorded separately in the parity audit.

## Independent validation and feasibility

The normal test driver covers empty reports and exact SVG, malformed envelopes,
duplicate escaped keys, UTF-8 errors and surrogate pairs, integer boundaries,
float overflow midpoint neighbors, depth 64/65, strict schema and phase ordering,
duplicate IDs, unknown/reused references, overlap at zero clearance, edge contact,
Pythagorean clearance equality, outside placement, millimeter conversion, odd
half-spans, escaped identifiers, and sorted connectivity/design reports.

Additional independently constructed tests passed on 2026-09-07:

- Exactly 1,048,576 input bytes, mostly whitespace: valid empty request.
- 50,000 unique unknown object keys in 538,903 bytes: `invalid-board`.
- Repeated 100,000-byte keys: whole-request duplicate-key rejection.
- 16,384 references to the same pin: one sorted `reused-pin` reference.
- 64 boards, each with 128 overlapping components, 32-byte component IDs, and four
  unconnected pins: **841,355 input bytes; 57,692,813 output bytes** (over 55 MiB),
  8,640 findings per board, exit zero, empty stderr, about **67.319 seconds**.
  Output was parsed and its 64 result/finding counts checked by the independent
  CLI driver. `--stress` reconstructs this fixture and also checks endpoint
  findings. Timings are observations from this machine, not trial scores.

Two earlier full-output attempts exhausted the unchanged two-billion-step VM
budget after approximately 71.095 and 70.196 seconds, with no published output.
The first repeatedly decoded already-validated identifiers during serialization;
the second still repeatedly resolved geometry fields within every component pair.
Direct validated identifier emission and cached normalized rectangles made the
third attempt pass. No compiler/host modifications, raised quotas, reduced case
counts, or reduced contract were used. The successful large case remains close
to the construction host's resource envelope; it is not evidence that every
adversarial arrangement runs within a future trial's wall/CPU/memory limits.

The documented host bounds remain 2 MiB raw transport input, 128 MiB buffered
output, 300 million host calls/work units, and two billion VM steps. The guest
rejects input over the application contract's 1 MiB limit. Its token allocation
reserves six words per input byte plus sentinels and the bounded hash table;
there are no native parsing/geometry/serialization helpers. No Guardian gate was
run, no language checkout build was needed, and no gate-feedback entry applies.
