# Superseded compact sret v1

V1 is blocked and was never timed or adopted. Coordinator review identified missing field alignment and final padding: a bool result followed by scalar int final incorrectly placed the integer at byte1. Integer-only controls and full conformance did not reveal the UB. Compiler patch, installation identity, native excerpts, commands, errors and successful controls are preserved. Alignment-aware v2 is separate in ../compact-sret-002.

V1 proved nominal transport holes: evaluator280→48B, get_variable216→24B; evaluate explicitframe1208→488B but code8636→11641B. These are pre-fix measurements of emitted size, not runtime timings.

103 verified tests and VM246/tree241 normal+stress passed. Existing Core subset3/5 passed; failures were old physical ABI and transport memcpy-count assertions. All failures and intermediate Guardian/fixture/compile attempts are retained in logs and failure subtrees. Explicit LLVM verifier attempt failed because pinned Zig rejects `-x ir`; native builds had compiled the LLVM. V2 uses `.ll` extension inference and succeeds.

No production or guest source adoption occurred from v1. Base source fbeba4eed7b549a3feef14c8b8dd620e41494139 plus compiler.patch reproduces it; baseline/common installation and candidate installation hashes are in identity.json. Native artifacts remain in the private compact-sret-001 scratch.
