# Independent final Phase B gate script review

The original verifier's three-size performance loop accepted unrelated tag,
size, compiler and runtime metadata when the rows themselves passed acceptance.
The preserved executed repro uses approved A5 counter rows only as an admission
oracle, with deliberate metadata substitutions; it makes no candidate measurement
claim. `initial/verify-phase-b.py` has SHA
`0004b65388ec51201bd6434299345593595a2a6033b48f376bcd86fbb8296e57`.
Other initially copied scripts already include the first binary-manifest update.

Root corrected the verifier to require tag/size and exact build identity on all
three results. The executed corrected performance-loop probes reject wrong tag,
size, compiler hash, runtime and compiler path; the exact-identity positive admits
all 86 rows at each of dev/smoke/full. Corrected verifier SHA:
`f94277d12526e8761afb2eee0321d83d96d5d3cbc8a6cfe43d57c6d470ad5bfe`.

Source review also confirms:

- Candidate manifests capture all 58 ELF digests immediately after corpus build,
  before dev/smoke measurements; final verification checks exact GC keyset and
  unchanged bytes, compiler/QBE/source/build identity.
- The auxiliary full-size runner refuses an existing full result, requires smoke
  success, checks source/compiler/binaries before and after measurement, and
  records exact command, CPU environment, script, log and result hashes. Prepare
  pins its hash and the final verifier requires its receipt. It asserts readiness;
  launch it after canonical smoke success.
- Canonical 27 statuses retain full Zig/native gates, nine guest modes, four Lox
  tests/driver combinations. Supplements retain fuzz100, four Lox project builds,
  doc coverage, all 29 distinct corpus module-byte programs and four runtime
  matrices. The full `test` target wires module compile/build/check/test oracles
  over `tests/lang`, plus named memory-budget tests.
- GC and explicitly CPU-pinned fresh A5 control identities/cache/binary digests
  remain checked. Dev/full limits and all caps remain enforced; smoke uses the
  approved differential correctness/no-new-cap criterion with every movement
  reported.

No further actionable gap was found in this scope. Python AST and Bash syntax
checks passed on the exact copied final scripts. `receipt.json` and the verified
archive preserve all script revisions/hashes, loop probes, original false-green
receipt, corrected six-case receipt, and pinned oracle inputs.

This review wrote only its owned worktree/scratch. Analysis ran no native code, hardware
sampling or compiler/backend gate. The evidence commit then exercised its
pre-commit Guardian hook: all 88 whole-tree checks passed. Feedback is centralized
by root; root owns the final integration verdict.
