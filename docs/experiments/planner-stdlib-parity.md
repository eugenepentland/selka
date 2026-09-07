# Planner standard-library preparation — 2026-09-07

Status: baseline migration in progress; **not a timed application trial and not a
scored-cohort readiness receipt**. This audit follows the standard-library-first
rule in [the comparison plan](application-comparison.md). Original calibration
snapshots, task observations and timings remain unchanged.

## Reviewed sources and scope

The workload remains [workflow-planner-v1](../../experiments/application_comparison/contracts/workflow-planner-v1.md):
1 MiB UTF-8 JSON, 64 manifests, 128 jobs per manifest, 128 dependency references
per job, ASCII identifiers of 1–32 bytes, complete validation precedence,
lexicographic topological order, synchronous layers and critical-path timing.
No limit was reduced to fit a library API.

Actual comparator implementations reviewed:

- [Python planner](../../experiments/application_comparison/baselines/planner/python/planner.py)
  imports `collections.Counter`, `dataclasses.dataclass`, `heapq`, `json`, `math`,
  `re`, and `sys`; it also uses built-in dict/set/list/tuple/sorted/max.
- [Zig planner](../../experiments/application_comparison/baselines/planner/zig/src/main.zig)
  uses `std.json`, `std.ArrayList`, `std.mem` comparison/sort, `std.fmt` integer and
  floating conversion, `std.unicode`, `std.math`, arena allocation, standard I/O
  and `std.testing` in tests.
- Actual local versions are Python 3.14.4 (`/usr/lib/python3.14`) and Zig
  `0.17.0-dev.1683+5ceec001b` (the pinned toolchain's `lib/std`). Python's
  `graphlib.TopologicalSorter` is available even though this baseline does not
  import it; generic dependency readiness remains a relevant parity capability.
- [The newer pin-role application](../../experiments/ergonomics/pin-roles/main.my)
  already demonstrates `std_text` input and `std_json` tape parsing. It informed
  the migration pattern, without importing EDA domain behavior into the planner.

## Capability evidence and remaining work

| Required behavior | Python / Zig evidence | `.my` migration or boundary |
| --- | --- | --- |
| Bounded standard input/output | `sys.stdin.buffer.read`, `json.dump`; `std.Io.File` read/write | `std_text::read`, `emit`, `number` over the audited byte bridge; app request remains 1 MiB |
| Strict JSON, decoded strings and duplicate keys | `json.loads` hooks; `std.json.parseFromSlice` | `std_json::parse` once per request; old local parser removed |
| Full transport number validation | Python integer/float hooks and `math.isfinite`; Zig `std.fmt.parseInt/parseFloat` | Standard JSON runtime distinguishes integer/fraction, checks signed64 range and finite binary64; does not use limited `std_format::parse_f64` |
| Structural JSON access | dict/list; `std.json.Value` | `std_json::get/field/equal/compare`; immutable preorder nodes plus decoded UTF-8 |
| Output representation | `json.dump`; `std.json.Stringify.valueAlloc` | General `std_json_builder` exists; this schema-specific renderer retains fixed punctuation and ASCII-only identifier quoting, using `std_text` number/output primitives |
| Scratch lists | list; `std.ArrayList`/arena | `std_collections::filled<i64>` creates bounded owned scratch; 16,384 references fit the contract |
| Lexicographic sorting with document context | `sorted`; `std.mem.sort` | Contextual standard sorting is being prepared separately; migration must retain O(n log n) behavior for 16,384 unknown names |
| Counters and membership | `Counter`, set/dict; Zig loops | Bounded byte hash APIs cover 32-byte application identifiers; reusable counter API is being prepared separately. Node indices are not string equality keys |
| Ready queue and dependency ordering | `heapq`; generic Python `graphlib` available | Standard priority/readiness APIs are being prepared separately; planner policy (validation precedence, lexical tie-break, layers, times) remains application code |
| Identifier recognition | Python's fixed `re` pattern; Zig byte predicates | Explicit bounded ASCII application predicate. General regex equivalence is not claimed |
| Data model and tests | dataclass/tuple; Zig structs and `std.testing` | Language records/buffers plus compiler and public byte-host checks; coordinator testing is separate infrastructure |

The reusable JSON implementation lives in
[`src/json_document.zig`](../../src/json_document.zig), reached through
[`std_json`](../../src/stdlib/std_json.my). It validates UTF-8, uses depth 64,
rejects decoded duplicate keys, preserves integer/fraction distinctions, and uses
the pinned parser's full floating conversion for finite-number validation. It
accepts `1e-9999` and `0e9999`; presence of a bounded formatting module therefore
does not impose that module's limits on JSON transport. Parser/runtime work is
standard-library preparation, not a permitted application host-helper escape.

## Migration and acceptance

The [prepared baseline](../../experiments/application_comparison/baselines/planner/my/README.md)
replaces local syntax/Unicode/number parsing and decimal formatting with standard
APIs. `schema.my` expresses application shape rules over parsed nodes. The
application retains ownership of graph policy and report schema. General
collections construct scratch buffers; allocation error behavior remains explicit.

Checks on the installed raw-byte host after the JSON/buffer migration:

- All 10 original independent public CLI test groups passed (8.094 seconds).
- All 12 expanded groups passed (63.443 seconds), including exact 1 MiB input,
  whole-request validation before schema rejection, escaped duplicate keys,
  paired/unpaired surrogates, finite extreme decimals, signed64 bounds and all
  24 source-order permutations of a four-job graph.
- The preserved full-bound resource reproducer passed the dense 128×128 cycle
  (128 blocked identifiers, 939 response bytes, 22.736 seconds) and 16,384
  distinct unknown references (147,508 response bytes, 55.083 seconds).

These are observed check durations under shared-host contention, **not matched
application-development times or before/after performance estimates**. They do
not establish that the complete 64-manifest worst case fits coordinator quotas.
Tests use independent construction expectations and newly explicit public
boundaries, not hidden scored tasks. No application task was timed.

The host SHA-256 for those checks is
`cf7e946b17c94cafacdf62bb9bc353ef16d3c5928d197492e8f47202701dd2d3`;
the installed language CLI SHA-256 is
`c0d942a324acfdd3fc7ea1b8eced3aad3908fbeb5432a6218ff0ef56cb4e5631`.
Any new standard modules need refreshed installed binaries and a separate final
integrated acceptance identity before cohort freeze.

## Cost accounting and launch blockers

This work belongs to **baseline preparation/migration**. Reusable library changes
belong to **library/compiler preparation**. Total agent wall time, turns, tokens,
compute cost and human effort were not captured by a trial ledger and remain
unknown; test-process durations above must not substitute for those costs.

Before timing, complete contextual sorting and other required generic APIs,
independently review the dependency matrix and retained renderer choices, rerun
common three-language conformance, verify maximum workload quotas, and freeze
compiler/library/bridge/source hashes. Review whether regex or richer graph
requirements in future tasks expand the capability inventory before task authoring.
Passing this migration's checks alone does not authorize a scored cohort.
