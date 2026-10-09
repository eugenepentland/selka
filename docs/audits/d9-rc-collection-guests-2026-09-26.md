# RC collection guest validation

The joined collection runtime and compiler slice at `e1a78502` executes 71
collection cases on each native backend through `--rc-runtime=stats`. The compiler
is Debug (SHA-256 `8eacebf14822b1f37e2a486ca26b74fe64b7ec111ad45bc96d37a2e37d8ef6c6`);
the guests are ReleaseFast. The added regression fixture is represented by its
source hash in the evidence because it was not yet committed when executed.

[The reproducible driver and JSON evidence](../../experiments/d9-rc-collection-probes-20260926/README.md)
record each source hash, case name, process output, and statistics record. Existing
case bodies and effect annotations are unchanged. The non-arena text-view cases
include the 600-round, 1 MiB receiver retention probe under a 512 MiB ceiling.

| Group | Cases per backend | Heap allocate = retire | Owner acquire | Owner release | Clone shell | Unique check |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Basic list/dictionary/text/bytes | 13 | 238 | 68 | 306 | 6 | 50 |
| Byte/text views | 13 | 43,491 | 27,762 | 71,253 | 10,002 | 19,802 |
| Python bytes, byte buffers, keyed sorting | 39 | 822 | 6,292 | 7,114 | 19 | 77,948 |
| RC publication regression | 6 | 527 | 174 | 701 | 4 | 273 |

QBE and LLVM produce identical counters in every row. All counters are
unsaturated; holds, count-limit events, and arena allocations are zero in these
heap-only probes. Each row satisfies `heap_allocate + owner_acquire ==
owner_release`, with every allocation retired before the statistics report.

The broader text-view probe exposed an ownership error in an identity
`str(text)` conversion. Managed lowering leaves the existing pointer unchanged,
but generic result publication had classified it as a fresh owner. Consuming the
input then retired an edge still present in the containing list. The compiler
agent's `1499cbd2` classifies identity casts as borrowed; the new
`test_identity_text_conversion_retains_its_input` case converts a split element,
clears the list, and reads the result. It failed with an RC invariant abort before
the fix and passes on both backends after it.

The regression fixture also covers allocated text sort keys, nested list
publication, dictionary setdefault/pop/default/snapshots, set pop, and nested
byte/text views returned from functions then read after allocation churn.
The compiler build passes Guardian's 88 checks. Parent integration owns the full
GC regression gate and final acceptance.

Remaining collection integration work follows the shared compiler/core slices:
held/pinned callback receiver scopes, arena escape, and generic aggregate
construction need their dedicated execution probes. Pinned sparse dictionary
ordinal reads preserve entry addresses by scanning for the requested live row;
a full ordinal traversal can therefore be quadratic while pinned. The runtime's
cursor API already provides allocation-free linear traversal, but compiler
iteration still needs a cursor binding to use it in that path. Collection
constructors and mutation helpers themselves now publish owned results, acquire
logical children, preserve output on refusal, and roll back fresh arena products;
the 22-scenario C harness covers those contracts and remains part of the focused
RC tests.

Backend evidence correction: the historical collection probe `llvm.json` used
`--qbe` after its backend selection and ran QBE. It remains archived, but is not
LLVM validation. The corrected runner now records actual LLVM O3/LTO commands
and results separately in `llvm-corrected.json`.
