# Planner standard-library preparation — 2026-09-07

Status: baseline migration implemented; **not a timed application trial and not a
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

| Required behavior | Python / Zig evidence | `.selka` migration or boundary |
| --- | --- | --- |
| Bounded standard input/output | `sys.stdin.buffer.read`, `json.dump`; `std.Io.File` read/write | `std_text::read`, `emit`, `number` over the audited byte bridge; app request remains 1 MiB |
| Strict JSON, decoded strings and duplicate keys | `json.loads` hooks; `std.json.parseFromSlice` | `std_json::parse` once per request; old local parser removed |
| Full transport number validation | Python integer/float hooks and `math.isfinite`; Zig `std.fmt.parseInt/parseFloat` | Standard JSON runtime distinguishes integer/fraction, checks signed64 range and finite binary64; does not use limited `std_format::parse_f64` |
| Structural JSON access | dict/list; `std.json.Value` | `std_json::get/field/equal/compare`; immutable preorder nodes plus decoded UTF-8 |
| Output representation | `json.dump`; `std.json.Stringify.valueAlloc` | General `std_json_builder` exists; this schema-specific renderer retains fixed punctuation and ASCII-only identifier quoting, using `std_text` number/output primitives |
| Scratch lists | list; `std.ArrayList`/arena | `std_collections::filled<i64>` creates bounded owned scratch; 16,384 references fit the contract |
| Lexicographic sorting with document context | `sorted`; `std.mem.sort` | `std_order::sort/lower_bound` over decoded-range descriptors; removed local sorting/binary-search algorithms; sort retains O(n log n) behavior for 16,384 names |
| Counters and membership | `Counter`, set/dict; Zig loops | Bounded byte hash APIs cover 32-byte application identifiers; reusable counter API is being prepared separately. Node indices are not string equality keys |
| Ready queue and dependency ordering | `heapq`; generic Python `graphlib` available | `std_graph::prepare/ready/take_ready/complete` now supplies readiness and cycle-state propagation; `std_order` supplies an available priority queue. Application scans ready sorted IDs to implement its lexical policy |
| Identifier recognition | Python's fixed `re` pattern; Zig byte predicates | `std_ascii::matches` supplies bounded head/tail character-class recognition for the exact required pattern. General regex equivalence is not claimed |
| Data model and tests | dataclass/tuple; Zig structs and `std.testing` | Language records/buffers plus compiler and public byte-host checks; coordinator testing is separate infrastructure |

The reusable JSON implementation lives in
[`src/json_document.zig`](../../src/json_document.zig), reached through
[`std_json`](../../src/stdlib/std_json.selka). It validates UTF-8, uses depth 64,
rejects decoded duplicate keys, preserves integer/fraction distinctions, and uses
the pinned parser's full floating conversion for finite-number validation. It
accepts `1e-9999` and `0e9999`; presence of a bounded formatting module therefore
does not impose that module's limits on JSON transport. Parser/runtime work is
standard-library preparation, not a permitted application host-helper escape.

## Migration and acceptance

The [prepared baseline](../../experiments/application_comparison/baselines/planner/my/README.md)
replaces local syntax/Unicode/number parsing and decimal formatting with standard
APIs. `schema.selka` expresses application shape rules over parsed nodes. The
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

Before timing, independently review contextual sorting and other required generic APIs,
review the dependency matrix and retained renderer choices, rerun
common three-language conformance, verify maximum workload quotas, and freeze
compiler/library/bridge/source hashes. Review whether regex or richer graph
requirements in future tasks expand the capability inventory before task authoring.
Passing this migration's checks alone does not authorize a scored cohort.

## Final source-level library integration check

The follow-up migration uses `std_order::Item` descriptors for IDs and sorting
scratch, with the JSON node as payload and its decoded range as key. Generic
sort/lower-bound implementations replace application algorithms. Three separate
`std_graph` passes implement validation, lexical order and synchronous layers;
application timing/precedence policy is unchanged. The identifier pattern is now
two `std_ascii::Class` values and a `matches` call. The language currently cannot
pass borrowed document context through an indirect comparator callback, so the
library uses explicit descriptors instead of a private compiler exception.

The graph has eight owned scratch buffers: IDs and sorting descriptors (128,
128 and 16,384), three 128-word timing/dependency arrays, a state array sized to
the actual job count and an edge array sized to actual references (at most
16,384). Edges are resolved only after unknown-dependency validation, and remain
unchanged during each graph pass. General integer counters and hash maps are
available library choices; this baseline retains the sort-and-scan validation
strategy also used by the Zig baseline, without reimplementing a counter or heap.

[Retained source-level check evidence](../../experiments/validation/planner-parity-20260907/receipt.json)
records the ReleaseFast host and new-module hashes. All 12 CLI groups passed
(1.566 seconds); dense-cycle and maximum-distinct-unknown checks passed (3.478 and
5.958 seconds). New modules were temporarily loaded from the library worktree as
source, not embedded in that host; those temporary files are not committed into
the application. Hashes are observed after the checks rather than a claim of a
sealed module snapshot during concurrent library work. Repeat common conformance
against the final embedded libraries before freezing a cohort. Optimization and
representation changed between preparation stages: these durations must not be
used as a causal performance comparison.
