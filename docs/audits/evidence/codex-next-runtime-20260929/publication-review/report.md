# Independent admitted-COPY publication review

No actionable correctness defect found within the reviewed publication boundary
of frozen source `ed48ecc8a3c65794c2513bae594ae07cfb2774d0`, based on composed
source `7f5068a54946bcbe0cf1f7e20abf844f120046cd`. The owned review tree has no
production edits. All 895 tracked compiler/runtime/vendor files and three
private tools remained byte-identical before and after the review.

The counted COPY block is dominated by child-history, nonnull, pin/arena,
TAKE-clear and immortal-clear admission. Its owner address and loaded unsigned
64-bit owner count dominate the private `old + 1` and full-width zero test.
Only MAX wraps to zero. The overflow edge reaches the unchanged runtime slow
path before any count, history or output store; the admitted edge stores the
new count before committing history or the output pointer. The machine code
uses `addq`/`jz`, then the count store, followed by mark/output stores.

After acquisition, the reachable blocks have no loads, calls, allocations or
fallible edges. They inspect the already loaded mark, optionally store SHARED,
publish the pointer, and test the known word TAKE flag. Null, immortal and TAKE
paths bypass count acquisition; shared COPY still acquires one owner. Pinned,
arena and child-history paths retain the transaction. The existing compiler
contract supplies private, disjoint publication storage and valid frame regions;
the runtime's public overlap/refusal checks were not changed.

| Independently executed proof | Result |
| --- | --- |
| Candidate list emitted release/publication | 126 +648 cases pass |
| Exact composed7f control emission, same candidate QBE | Same 774/774 cases pass |
| Candidate dictionary emitted release/publication | Same 774/774 cases pass |
| Actual generated C and selected frozen runtime, unchecked | 20/20 cases pass |
| Actual generated C and selected frozen runtime, checked glue | 20/20 cases pass |
| Actual repeated-alias generated publication | 6/6 cases pass |
| CFG acquisition dominance/no later fallible edge | Both list/dictionary sites pass |
| Publication branch operand types | 18/18 word predicates |
| Counting emission | 1/1 publication calls generated glue; zero inline acquisitions |

The independent synthetic oracle has 12 mode patterns, nine owner counts and
six payload states. Counts include zero, one, 2^32−1, 2^32, 2^48−1, 2^48, 2^63,
MAX−1 and MAX. It covers exact high-only acquisition results, exactly-at-capacity
success, overflow refusal, shared/unshared COPY, TAKE, null, immortal, pinned,
arena and child history. The forced slow helper asserts unchanged counts,
marks, source and empty destination before returning refusal. Reserved modes
are compatibility cases, not accepted guest history contracts. Zero owners
can be valid with a lifetime hold; zero-count release remains an invalid-token
compatibility test only.

The actual native probes retain original count1 and slot at final helper entry,
check exact high-only count results, MAX refusal, shared/unshared COPY at MAX−1,
TAKE at MAX, pinned cloning and memory-budget rollback, and younger-arena
refusal. A real hold acquisition followed by owner release produces a valid
O0/H1 source; COPY restores O1/H1 and ordinary owner/hold teardown retires it.
Checked zero-release children abort as expected; unchecked zero-release
children wrap as before. Actual alias publication acquires two owners at
ordinary/high counts and MAX−2, and refuses MAX−1/MAX atomically without
changing either source field, output, count, mark or heap bytes.

`probes/extraction.json`, `control-extraction.json` and
`dictionary-extraction.json` record byte-exact bodies and source ranges from
independent production compiler emissions. `probes/dominance-proof.json` saves
the CFG proof. Original 702-case/19-native runs remain under
`probes/initial-702/`; the final 774-case/20-native runs add valid held-only
ownership and dictionary execution. The completed first execution was not
rerun merely for the driver's NUL-delimited archive-selection error; native
execution continued after correcting that review-driver parser. Its original
script and the error explanation remain under `initial/`.

Candidate compiler SHA-256:
`6a3c138f666d7137088d09d8cb60bd19f3f2bd6ff0f0497b4b61a73e7f054153`.
Candidate QBE SHA-256:
`0a97f87ec92ecaea379f7fa01da0ac68fec9e92663434a9eb28b620ca895bd23`.
Exact composed7f control compiler SHA-256:
`62147872cb192d103106bdf37616071a287b6e6fe19395461fe152e0d1fb1a42`.

The native archive was selected by a fresh owned guest build from the copied
candidate installation. Checked native probes compile the actual generated
glue with its invariant macro; counting fallback is an emission proof, not a
claim of executing the statistics runtime. Tooling's separate LLVM414,
backend140, generated-C13 and fresh96 guest receipts remain its evidence.
This review adds no own LLVM run, broad gate, timing or Guardian invocation.
Parent integration owns archival and quantitative acceptance.
