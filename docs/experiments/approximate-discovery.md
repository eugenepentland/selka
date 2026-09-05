# T: bounded approximate duplicate discovery

Status: implemented as opt-in `discover-duplicates --approximate`. Exact discovery
remains `exact-v28`; approximate scoring/reporting is separately versioned `near-v2`.
Reports are advisory, never rewrite code, and do not change source validity.

```sh
zig build run -- discover-duplicates examples/duplicates.my --approximate --timings
zig build run -- discover-duplicates examples/duplicates.my --approximate --max-work=1000000
```

## Comparison contract

Exact canonicalization runs first over checked functions. Each unique exact group
contributes its first source-order representative to approximate search. Exact
membership remains available in the report; near reports do not enumerate every
pair of identical copies. The existing min-nodes and population options apply.

Pairs must have identical canonical headers: return type/provenance, parameter and
local layout/types/mutability, reference metadata, effects and bounds, domain owner,
privacy, and conversion status. This deliberately excludes signature/layout changes
from this version. Body comparison keeps all canonical lines, including types,
obligations, move flags, literal values, operators, control flow, local slots,
permissions, and resolved callees. Differences in these body facts are edits, not
ignored data or claims that the functions are interchangeable.

The metric is unit-cost Levenshtein distance over complete canonical body lines:
insert, delete, or substitute one line. The default threshold is at least 90% line
similarity, meaning distance <= floor(10% of the longer body line count). Embedders
can select 1..99 percent. This percentage measures representation overlap, not
probability of shared intent, defect confidence, or semantic equivalence. Repeated
metadata lines contribute to it. There is no arithmetic normalization or execution.

Traceback uses deterministic equality/substitution/deletion/insertion precedence.
Reports show both source locations and up to eight canonical edits in body order;
remaining edits are explicitly omitted with an instruction to inspect both bodies.
The canonical lines describe changes, not a source patch. Bound-name normalization
and direct self-recursion normalization are inherited from exact discovery.

## Work and output limits

Search builds a stable header index, then visits only compatible unique-group pairs
in first-declaration order. The default work budget is 1,000,000 and the output limit
is 100 pairs. `--max-work=N` requires `--approximate` and a positive value. Embedders
can also set the pair limit. Index initialization, merge-sort entries/copies, header
comparison bytes, compatible pair visits, matrix cells, and a conservative bound on
compared body-line bytes are charged. Exhaustion during index construction reports
an incomplete search with no near pairs; exact findings remain available.

Stable merge sorting uses O(n log n) header comparisons and O(n) temporary index
storage. Adjacent equal headers form source-ordered chains; discovery follows those
chains while retaining global first-declaration pair order. Header equality is full
byte equality, with no probabilistic filter. Length difference still filters
impossible matches before matrix allocation. Pairwise matrices use temporary storage
and are freed after each comparison.

The budget bounds indexing and comparison, not frontend checking, canonicalization,
line splitting, rendering, or wall-clock time. Matrix memory is proportional to the
charged cell count. Compatible pairs within a common header bucket and their edit
matrices can still be quadratic. This is not a global nearest-neighbor ranking or
a whole-compiler scaling guarantee. Exact discovery finishes independently of this
budget. The near-v2 version records changed work accounting and budget-limited search
behavior; header eligibility, line similarity, and edit explanations are unchanged.

Work or pair exhaustion stops search and emits `truncated=true` plus an explicit
incomplete-search message. An absent candidate is never a proof of no duplication,
especially with truncated work, thresholds, or the header restriction. No candidate
is promoted to an error. Source/usage/host failures keep their existing exit codes.

## Reviewed evidence

| Case | Finding | Review outcome |
| --- | --- | --- |
| Existing `examples/duplicates.my` | One exact sum/legacy group; one near pair with inclusive sum showing `lt` -> `le` | Intentional policy difference. Useful explanation to review; retain independent policy unless the caller contract is deliberately changed. |
| Literal drift fixture | One canonical edit `1` -> `3`; duplicate copies represented once | Deliberate fixture difference, not evidence of a shipped defect. |
| Operator and resolved-callee fixtures | Names/operators printed as edits | Similar structure cannot justify replacing one behavior with the other. |
| Inserted discard at 70% embedding threshold | Insertion and block-child change appear in alignment | Demonstrates edit support; does not recommend discarding or merging either function. |
| Different signatures/effect bounds/nominal types and unrelated control flow | No near candidates | Required header filter and similarity threshold apply. This does not prove domain independence. |
| Work/pair limits | Exact findings retained; approximate incompleteness reported | Bounded analysis remains inspectable instead of silently reporting exhaustive absence. |

Unit tests also verify deterministic rendering, no lowering during discovery, and
every allocation failure through comparison/output/rendering. Actual CLI tests
verify advisory exit status, changed-value explanations, budget reporting, and
invalid-option rejection. These are review fixtures, not production usefulness or
performance statistics. Wider ordinary-program review remains ongoing tooling work.

## Header-index scaling acceptance

`zig build test` runs `tests/duplicate_scaling.py` against the actual compiler. It
generates 128, 512, and 1,024 functions with distinct nominal parameter types except
for a compatible first/last pair. Every run must find exactly that pair without
truncation under four million work units and repeat the same report byte for byte.
Observed work is 150,889 / 621,084 / 1,361,230 units respectively. These are generated
stress fixtures, not ordinary-program usefulness evidence. The default one-million
budget can still truncate the largest case; increasing it is explicit.

A separate unit fixture with 1,024 canonical inputs finds the first/last compatible
pair below 250,000 units. Interleaved buckets verify global pair order and output
limits. Existing allocation-failure sweeps now include index allocations. Broader
ordinary-program review and scaling within large compatible buckets remain pending.
