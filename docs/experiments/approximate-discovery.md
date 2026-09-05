# T: bounded approximate duplicate discovery

Status: implemented as opt-in `discover-duplicates --approximate`. Exact discovery
remains `exact-v26`; approximate scoring/reporting is separately versioned `near-v1`.
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

Search visits unique-group pairs in first-declaration order. The default work budget
is 1,000,000 and the output limit is 100 pairs. `--max-work=N` requires `--approximate`
and a positive value. Embedders can also set the pair limit. Header comparison bytes,
pair enumeration, matrix cells, and a conservative bound on compared body-line bytes
are charged. Length difference filters impossible matches before matrix allocation.
Pairwise matrices use temporary storage and are freed after each comparison.

The budget bounds this comparison stage, not frontend checking, canonicalization,
line splitting, rendering, or wall-clock time. Matrix memory is proportional to the
charged cell count. Pair enumeration and edit distance are potentially quadratic;
this is a bounded first implementation, not a scalability claim or ranked global
nearest-neighbor search. Exact discovery finishes independently of this budget.

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
