# Independent scratch-alias qualification review

Read-only review by `/root/lookup`, 2026-10-03. No actionable artifact or
full-stream qualification defect was found. This extends source proof review
`6e12818aecae147fabc6ac9f2b08540f1f09c6ec`; it does not select the compiler or
claim a performance improvement.

`review.json` binds the frozen compiler source (871 files), unchanged selected
AST source (37 files), compiler `3d519afb…`, QBE `99ad919d…`, full owned and
control bin/lib prefixes, all five qualification helpers and their prospective
descriptor, and four actual RC/GC guest builds with manifests, receipts and
runtime archives. Both LLVM guests use O3/full LTO; only QBE commands receive
the explicit QBE path. Native GC stress is a process environment mode on GC
guests; Lox GC stress is a separate guest argument.

The verifier independently reconstructs the named-test and native tuple
coverage, compares complete status/stdout/stderr including Lox statistics, and
checks every live input against its saved compressed copy. Results are 336
fresh public checks (84 names, four modes), 1,168 bounded native comparisons,
96 AST-focused comparisons and eight RC native-stress checked refusals.
All 80 declared native-stress smoke omissions remain unrun. Public providers
are not exercised; every tested provider identity is empty. Public LLVM uses
`--release`, QBE uses `--mode ReleaseFast`, with 1e9-step/120s ceilings.

Independent ELF parsing verifies all 26 allocated LLVM RC sections plus
header, entry and program layout against the selected control. The only
nonallocated differences are recorded debug metadata. Full ELF byte equality
is not claimed. Actual GC guest outputs are qualified separately. Retained
frontend replay parsing verifies all 420 emitted unit bodies and metadata,
runtime C and warnings, and all 820 cached IL files; only the manifest store
path differs. No compiler invocation is needed for these checks.

The first optional library copy failed before the final freeze because the
control prefix has no library directory. The first Release build failed the
SPEC linkage gate and ended with status 143 before installing a qualified
compiler. Both are historical exclusions. Review tooling's initial schema
assumptions about module-only build maps and the GC produced-artifact snapshot
were corrected before the successful verification; the private attempt logs
are retained. Public LLVM RC stderr contains a captured compiler_rt archive
command, so build stderr is not described as universally empty.

Broad compiler acceptance runs in a separate private shadow tree. Its pending
or subsequently reported results are not inferred from this qualification
review; root controls performance timing and selection. Guardian feedback is
consolidated by root.

To recheck the saved receipts and original identities without building or
running guests, from this experiment directory run:

```sh
taskset -c 16 python3 -B verify.py
```

Original paths must remain available. `verification.json` is the successful
read-only result. Compressed inputs preserve exact complete streams and
frontend units, rather than truncated tails or hashes alone.
