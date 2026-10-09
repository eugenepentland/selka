# Selected cost visibility refresh

This is a fresh, source-bound selection for phase 6, not the old FP2 full-corpus
qualification or its unfinished timing budget. The final immutable compiler is
`aca89445a3f2d4f2dddbf68b6441c3473374cd37b2e6cde68929e0690def737f`;
`../candidate-final.json` binds its 612-file source inventory. Candidate 1 and
its receipts remain preserved separately. All command receipts
record exact inputs, stdout/stderr hashes, affinity, elapsed observations and
concurrent heavy-process context. No uncontended elapsed-time or speedup claim
is made.

## Typed census selection

Each selected executable entry is dumped once. Counts cover its loaded graph's
checked body instances, including concrete generic specializations. This is a
selection by entry graph, not every source file in the historical Lox/EDA/stdlib
corpora. Bodies from imported modules are included. The immutable migrated
Lox/EDA snapshot sources were read without modification; receipts hash the
entry, source files and project configuration. The private stdlib entry imports
strings and json and calls selected APIs. The language entry is the explicit
list/text/bytes workload described below.

| Selection | Checked bodies | Selected entry |
| --- | ---: | --- |
| Lox | 382 | frozen migrated ports/mylang/main.my |
| EDA | 1213 | frozen migrated mylang/src/main.my |
| stdlib | 110 | operations/stdlib.my, importing strings/json |
| language | 3 | operations/main.my |

All four final dumps and walkers succeeded. Per-operation rows at depth
0/1/2+ and per-event function/dump-line attribution are in
`final-census/*-counts.json`; the compact view is
`final-census/summary.json`. Selected visible examples are:

| Operation | Lox | EDA | stdlib | language |
| --- | --- | --- | --- | --- |
| list membership | 0/0/0 | 0/2/2 | 0/0/0 | 1/0/0 |
| list equality | 0/0/0 | 0/0/0 | 0/0/0 | 1/0/0 |
| bytes slice | 1/0/0 | 43/13/0 | 1/0/0 | 1/0/0 |
| bytes view | 3/1/0 | 6/1/1 | 0/0/0 | 1/0/0 |
| string addition inside loops | 0/0/0 | 0/62/4 | 0/2/0 | 0/1/0 |

Depth is typed loop nesting, including generated loops. The new role-labeled
range_loop is traversed with start/end/setup outside the loop and
condition/body/step inside it; its schema is checked explicitly. A hand-labeled
walker test proves depth counts 3/2/1 for endpoint/setup, loop plan and nested
loop operations. Four walker tests pass, including malformed/schema-changing
dumps failing closed and opaque/unknown observations staying explicit.

Omissions are not zero estimates. Plain list slices and repetition lowered into
anonymous loops, nonpacked list construction, unused generic templates, fused
slices/views and operands hidden by opaque nodes remain uncounted. Nominal
comparison is classified as record only with a visible constructor certifying
that representation; other nominal equality is unknown. Lox has 48 unknown
nominal comparisons and 344 opaque nodes; EDA has 83 unknown nominal comparisons
and 554 opaque nodes; stdlib has 20 opaque unit nodes. These omissions prevent
claims of absence, complete source counts or direct numerical comparison with
the historical all-source FP2 tables.

`tools/count_typed.py` was narrowly adapted from the preserved historical
frontend-fp2-20261008 walker. No historical branch was merged. The old corpus
collector's automatic library main stubs and old import routing were not reused;
the current developer loader resolves the selected entries directly.

## Static sites, counters and Juice

`operations/main.my` processes 32 input records four times. It builds a list and
text, sums records, performs equality/membership and byte slice/view operations.
Its fixed oracle is exit 0, stdout `2144\n`, empty stderr and 128 completed
input records. The manifest fixes that result and
`core-count-p1-c26c95de7` counter semantics.

The completed source-bound Juice record is
`juice-evidence/final/record.json`. All three ordinary samples and the
separate counted executable match the oracle. Raw perf records, sample streams,
counted streams and counters are preserved beside it. Generated build binaries
and local cache stay in the ignored `juice-cache/`; executable hashes and build
recipes remain in the record. `static-cost.json` is the saved `cost-v1` report
from the same source-bound build.

| Observation | Final candidate |
| --- | ---: |
| ordinary whole-scenario user instructions | 206326 / 206326 / 206325 |
| median instructions per completed input record | 1611.921875 |
| static may-allocate sites in checksum | 6, including 2 unresolved |
| managed allocations during four checksum calls | 24 |
| total managed allocations, including outside emitted functions | 27 |
| list push executions / element bytes written | 128 / 1024 |
| text append executions / bytes appended | 128 / 128 |
| text growth executions / bytes moved | 8 / 124 |
| peak managed allocation-class bytes / live bytes at exit | 640 / 0 |

Six static sites do not mean six allocations per call or six heap executions.
A site may run repeatedly, take a nonallocating branch or allocate scratch
outside the managed-block counters. Managed allocation sizes describe allocation
classes/usable sizes, not requested bytes. Three managed blocks are charged to
`<outside>`; startup is included in this complete-scenario instruction count.
Counting execution inhibits some optimization and its elapsed time is not an
ordinary-program timing. Check counts describe emitted Core checks, including
ones LLVM could later eliminate, and exclude checks inside runtime helpers.

The release static report records 11 kept check sites, seven proof events,
one in-place update and one tested update. It records three loops with unknown
LLVM outcome and no positive vectorization evidence (`null`), which is not a
proof that all loops are scalar. Perf recording has no sampled function/line
attribution in this capture; semantic site attribution is separate.

This is one qualified capture, not a before/after performance comparison. No
larger-scenario transfer validation was run, and the very small workload includes
fixed startup/argument/output cost; its instruction-per-record number is not a
claim about Lox or EDA throughput. No copy annotations, spelling changes or new
operators are justified by these observations alone.

## Useful workflow

The new user guide `docs/tooling/cost-workflow.md` explains how to select equivalent
completed work, inspect a static function, run counters, preserve identity when
joining function-name reports and use Juice for an actual comparison. It links
the existing precise cost/counter contracts and this evidence. All four census selections and the complete cost/counter/Juice capture were
recollected on the final immutable compiler. Counts, opaque/unknown observations,
static cost and semantic runtime counters match candidate 1; the two captures
are independent functional qualifications, not a performance comparison.
A subsequent production compiler change would require another qualification.
