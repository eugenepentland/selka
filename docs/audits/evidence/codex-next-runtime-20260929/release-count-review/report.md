# Independent release-zero and word-mode review

No actionable release/count/mode defect found in frozen source
`279501d17e6eb84b13fa311b7042434a70c2cc5d`. Compiler and QBE were copied to this
owned review tree before execution; all 890 tracked compiler/runtime/vendor
source files and both binary digests remained unchanged through verification.

The release calculation is unsigned 64-bit `old - 1`, kept private. Only
`old == 1` produces zero modulo 2^64. The final-unheld branch invokes the
existing generated helper before publishing a reduced count or clearing the
slot. Nonfinal and otherwise-held paths store the private result, then clear
the slot. No fallible publication, native helper, pin or arena logic changed.

The three direct mode branches have `w and` producers: child history masked
with 3, and the two TAKE tests masked with 4. Every long payload, mark and
other-count predicate remains normalized with a full-width comparison. All
19 branches in the independently extracted production fragments use word
operands. Counting emission still calls native generated glue at all 28
release sites of the fixture's `keep` function.

| Independently executed check | Result |
| --- | --- |
| Candidate release boundaries | 126/126 cases pass |
| Candidate publication dispatch/refusal boundaries | 216/216 cases pass |
| Original f4 emission, same corrected QBE | Same 342/342 cases pass |
| Actual generated C and frozen runtime, unchecked | 11/11 cases pass |
| Actual generated C and frozen runtime, checked | 11/11 cases pass |
| Actual repeated-alias publication, checked | 3/3 cases pass |

The production `keep` IL came from `mylang emit-qbe source.my`; extraction
records its exact byte ranges and raw bodies in `probes/extraction.json`.
The boundary oracle substitutes assertion-bearing helper stubs to check
dispatch and unmodified state on refusal. These synthetic cases include zero
count, MAX, high-only other counts, old values whose reduction is exactly
2^32/2^48/2^63, null/immortal/arena marks and word-mode bit patterns. Invalid
zero counts and reserved modes are compatibility boundaries only, not accepted
source ownership or history contracts.

The original f4 compiler emitted the same fixture independently. Both control
and candidate fragments were translated by corrected frozen QBE `df600...`,
isolating the release/mode lowering change from the separate selector repair.
The first 312-case runs remain under `probes/initial-312/`; the final 342-case
run adds precise high-only reduced results and remains separate.

The native oracle links unmodified generated C from the compiler with the
frozen runtime archive that the ordinary guest build actually selected. GNU
linker wrapping observes owner/hold helper entry before calling the real
helper: original count 1, opposite count 0 and original slot are intact, and
real list/backing retirement completes. The high-count native cases remain
live without a final-helper call. Zero-count children wrap in unchecked
generated glue; checked generated glue aborts both with SIGABRT as expected.
No core files are produced.

Actual publication tests preserve source/count/mark state on MAX refusal,
clone a pinned list without disturbing its pin journal, fully roll back a
pinned-copy memory-budget refusal, and reject a younger arena value stored
into an older root. The alias oracle publishes two repeated fields: ordinary
and exactly-at-capacity copies acquire two owners, while MAX-minus-one
refuses both fields atomically without changing history or either source.
Artificial high reference traffic is normalized before ordinary teardown.

Compiler SHA-256:
`a7c9e2648fd472bf04f82c84c137e5f0bd35679b41b37a5c0b633a3534b73aac`.
QBE SHA-256:
`df60056d2cdbef23eb6c5dada5249fdaf232bb6e75d4b4799c1626fc67b30819`.
Original f4 emitter SHA-256:
`67a130ed40e87eea7b139793d83fcc8dc6fb3683add460b1be95dc0a36c0732a`.

`receipt.json` pins all sources, binaries, artifact files, outcomes and
intermediate pre-execution fixture errors. No compiler/source edits, timing
claim, broad gate, Guardian invocation or independent LLVM execution is
included. Tooling's separate LLVM 54-case receipt remains its own evidence;
B2 owns the independent generic-selector review. Parent integration owns
durable archival and combined acceptance.
