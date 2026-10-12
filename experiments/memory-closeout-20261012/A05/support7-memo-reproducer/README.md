# Support7 warm memo build failure

Compiler source `bed11cf3bf3102ffec44487e431a1573fdf02ad5`, binary SHA256
`540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
The unchanged source passes the matrix release lane, but the four later modes
exit 1 with empty stdout/stderr and no emitted LLVM. The failures stay in
`matrix-failure.json`; no RC/leak or execution result is claimed for them.

Fresh-cache unoptimized build succeeds with a full report. An identical second
build using that cache exits 1 silently. The original shared-cache unoptimized
build also fails, while source checking on that cache succeeds. Exact commands
and reports are retained in `cache-controls.json`; original caches remain under
A05 `.tmp/memory-closeout/A05/support7-memo-repro/fresh-cache` and
`support7-full/batch-04/cache`. A08 owns diagnosis. No source rewrite or disabled
cache is used to count these failing lanes as qualification passes.
