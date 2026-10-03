# Independent numeric tag-store review

The frozen numeric-only trial passes independent proof and saved-evidence review
with no actionable semantic defect. Descriptor `0d4d12ca...` contains 869 core
files: six changed from `3b33df52`, with 863 identical. All 37 selected AST source
files are unchanged. The compiler is `6f021b7c...`, with explicit QBE `99ad919d...`.
The trial remains unselected; this review makes no performance claim.

The existing RC constructor fully zeroes fresh ordinary variant storage before
writing its tag. For the admitted Linux AMD64 layout, an eight-byte tag store
writes the same four tag bytes and four already-zero padding bytes. The payload
starts at byte eight. The predicate bounds cases and fields to eight, storage to
16..32 bytes with alignment eight, and accepts only a plain active builtin i64
or the compiler's float identity. Numeric payload reads, writes and bit patterns,
the internal journal, source/address/region evaluation, publication, error trace
and cleanup retain their exact code and order. Unsupported layouts, user domains,
callbacks, active owners, unique resources, bool and niche cases retain old
stores. GC, borrowed-body and legacy-sharing routes bypass the RC hook.

The independently checked six saved SSA bodies differ only at nine tag-store
widths, each after zeroing the same pointer. Their QBE instruction and call
counts remain identical; LLVM `vm::run` stays at 5586 instructions and 486 calls.
The host byte-pattern test models emitted stores with adjacent sentinels across
96 tag/size/pattern combinations. It does not execute malformed internal inputs.

Saved final qualification binds four stable RC/GC guests, 12 constructor builds
and eight exact constructor pairs, including identical RC-counting stderr on both
backends. The 336 AST and 28 constructor public checks are fresh. The bounded
native matrix has 1168 exact pairs, the AST-focused matrix has 96, and eight RC
native-stress checks produce the expected refusal. All 80 unrun native-stress
smoke cells are preserved as omissions. Native GC stress uses the environment;
the Lox collector stress switch is a distinct guest argument. Public LLVM uses
`--release`, QBE uses Debug, and both public modes have step accounting; O3/full
LTO describes the release guest builds. Provider-dependent entries are omitted.

The first QBE gate failed 18 expected-path/tool cases. Its repair refreshed 398
tests while 117 prior successful roots were reused; the subsequent owned-copy
gate was cached. The attempted suspension found that gate already finished.
Complete bin/lib maps begin after that event, so there is no retrospective
pre-gate full-library stability claim. Final stable builds and each qualification
phase do bind complete 16-file candidate and two-file selected prefixes before
and after, with all bytes unchanged. Provisional guest builds are retained as
earlier-window evidence; qualification uses only the later stable artifacts.

The author also passed 25 focused checks, 2493 fresh checks in eight bounded
shards, and an explicit 88-check Guardian gate. Raw logs preserve the known
misleading `failed command` footer where the outer process actually returned
zero. `review.json` maps the original and copied payload identities.

Run `taskset -c 16 python3 -B verify.py` here to recheck source, artifact, prefix,
coverage, full output/error/stats, counting and static-width bindings. It uses
read-only file operations and `git archive`; no compiler, guest, suite or
performance command is executed. Guardian feedback is consolidated by root.
