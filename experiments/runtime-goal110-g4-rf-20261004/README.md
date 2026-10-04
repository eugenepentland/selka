# Integrated ReleaseFast milestone G4

The fresh worktree is pinned to production6cf7bdce11bc205862bf75b9d9ce72e46caad0a2,
including accepted bounded equality, parser outline, aligned scanner, short join,
sorting rotation, presized readiness, append range and unique capture changes.
The official compiler builder uses ReleaseFast, private empty caches and disk
TMPDIR. The24 guests use the normal frozen reference policy: original references
are hash-verified and reused, LLVM emits actual optimization3/fullLTO, and QBE is
tracked separately. MyLang guests are newly built; reference files are copied
only after identity verification. Compiler caches start empty.

Independent normal sessions A and B run join, bytes, search, equality, sorting
and nested mutation at both frozen sizes, all six arms,15 rounds/3 warmups on
CPU2. Each completes1080 samples and720 fresh qualifications with identical
source/compiler/assets/guest identity before and after. LLVM is the six-arm
median minimum on10 of12 rows in each session. Small equality remains about
1.39x and small sorting about1.38–1.39x. The coordinator owns the acceptance
intervals, correctness receipt and dashboard; this archive adds no bootstrap
or eighty-row completion claim.

Fresh official RF guests pass200 text records (192 independent oracle values,
six accounting/budget refusals, two identities) and516 nearby/larger holdouts.
The text checker validates successful status, checksum, two-field clock shape
and empty stderr; refusal checks validate nonzero status and expected markers.
It does not retain complete process stdout/stderr streams. Holdouts discard all
elapsed values. Final-source focused Debug tests pass42/0/0, including11 exact
ordinary/optimized native append outcomes with full trap streams, unique capture
held-input/budget semantics, readiness/fallback/generation and invariant joins.
The unit graph copies tools to zig-out/focus and preserves the official RF
compiler and installed SDK. An initial unsupported --global-cache-dir attempt
is retained; cache environment variables fix the invocation. The successful
Guardian test runner still prints misleading failed-command text with exit0.

Five earlier448 optimized portable C suites pass ASan+UBSan at-O3, including684
mixed-width joins,31104 search outcomes and53 RC collection cases. These are
explicit source-matched reuse. All114 tracked src C/header and tests/native
C/header files plus the suite driver match448 Git bytes at final6cf, and the
original native receipt, log and GCC15 compiler hashes match. They are separate
from the fresh RF200 records,516 holdouts and final-source Debug42 tests.

Actual RF short join is1605 bytes with zero calls in both backends; scanner
entries are64-byte aligned. This is code-shape evidence, without a causal layout
claim. evidence.json binds the raw reports/logs, official source/build receipts,
all24 guest identities, frozen references, semantic/native reuse checks,
before/after artifact checks, exact structured commands and helper sources.
Compiler build Guardian88 checks are diff-scoped; the archive/commit gate runs
all88 whole-tree checks. No full repository test gate is claimed.
