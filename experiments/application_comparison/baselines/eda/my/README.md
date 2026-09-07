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

`main.my` owns UTF-8 and JSON parsing, scalar-value validation of decoded strings,
escape normalization, duplicate object keys, signed-64 integer limits, finite
binary64-number range validation, depth limits, envelope and board schemas,
validation precedence, reference resolution, geometry, connectivity, deterministic
JSON serialization, and the exact SVG export. `io.my` declares only input length,
raw input byte lookup, and output byte append. The Python standard-library test
script is a CLI fixture/assertion driver and is not an application dependency.

## Implementation

The guest uses a preorder JSON tree in an owned numeric buffer, accessed through
mutable slices. Each node occupies six words: kind, source start/end, subtree end,
child count, and integer value. Object-key nodes reuse the last two words for
hash-chain links and a parent-tagged recognized-field code. Equality and hashing
operate on decoded scalar values, so differently escaped duplicate keys collide
correctly. The hash table uses at most 262,147 buckets; collisions retain exact
comparison. Hashing avoids a quadratic scan over ordinary large unknown objects,
though adversarial hash collisions still have a finite quadratic worst case.

Board processing uses a separate 17,536-word workspace. Component and net indices,
references, and pins are sorted by guest heapsort. Binary searches resolve
components and connected pins. Normalized component rectangles are cached once
before the pair scan. All distance and squared-gap arithmetic is signed 64-bit;
the contract's micrometer conversion and coordinate bounds keep the sum of two
squared gaps within that range. Findings stream in the required code/subject
order. Net spans use doubled centers and round the half-span upward.

Decimal floating input is grammar-checked without using a host numeric parser.
Its normalized magnitude is compared against the exact binary64 overflow midpoint
`2^1024 - 2^970`, including all digits at the boundary. Underflow to finite zero
is allowed. Floats remain schema-invalid wherever integers are required. Unpaired
UTF-16 surrogate escapes reject the entire transport; valid pairs are decoded.

Successful output is emitted directly through byte calls. The VM host buffers
these bytes and publishes them only after a zero return. The application parses
and validates the entire transport before emitting any case result.

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
