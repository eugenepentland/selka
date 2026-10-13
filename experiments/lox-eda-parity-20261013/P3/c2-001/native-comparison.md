Read-only comparison of the pinned, uninstrumented C2 and V2 binaries, using
`objdump --no-show-raw-insn --disassemble=my.sexpr_parser::next_token` and `nm -S`.
Exact commands/counts are in native-comparison.json; full assembly is retained.

| Static next_token measure | C2 | V2 |
| --- | ---: | ---: |
| Symbol bytes | 6,347 | 6,437 |
| Instructions | 1,467 | 1,550 |
| Jump instructions | 284 | 320 |
| Call instructions, including cold/error paths | 62 | 91 |
| Explicit local stack reservation | 72 bytes | 88 bytes |
| Instructions referencing rsp | 121 | 64 |

C2 has no calls to ordinary sexpr tokenizer helpers in this function: the
per-byte source calls are inlined. V2 contains calls to advance and
si_suffix_len. Some are in the cold fallback; the ordinary numeric suffix path
also now calls si_suffix_len/advance. Thus the instrumented call-count reduction
does not directly represent fewer native call instructions on the hot path.

Inference: the new per-run counter guards and duplicated fallback control flow
likely add enough control cost and change inlining decisions to outweigh the
scalar cursor updates. The larger local stack reservation is consistent with
different register/temporary requirements, but rsp references decrease, so this
comparison does not establish increased spilling. Static instruction/call counts
include unreachable error paths and do not identify the exact dynamic cause of
the regression. Native profiling would be needed to separate those costs; no
further scanner prototype or native campaign is requested for this batch.

The measured decision is independent of that inference: both nine-pair C2
diagnostics regress, with candidate/baseline 95% paired bootstrap intervals
above 1.0. Reject V2 and preserve source-002 unchanged.
