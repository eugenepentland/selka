# Body checking wave integration — 2026-10-11

This integration extends the installed schema 10 body checker with scalar
constant evaluation, dynamic and constant range strides, fixed-array and enum
table writes, and sequence iteration. It combines the qualified numeric,
structural and iteration implementations on native correction base
`7d2310df731c6fc614fe1c413d0ef5aad3ac9ae6`.

The integration preserves the complete checked graph comparison against the
native checker. There is no per-body native fallback. The qualified bootstrap
seed, producer work limits, recursion limits, and runtime semantics are unchanged.

## Cross-feature corrections

Ascending range counters retain the existing nonnegative proof needed by fixed
array indexing. Registration requires a nonnegative start, a known positive
stride and an unmodified loop binding; unsigned strides above the signed range
remain positive. Dynamic, descending and rebound controls retain native behavior.

Constant function signatures retain array, fixed-array, table and capability
annotations through the existing catalog. Shadowed builtin names remain source
names. This improves diagnostic parity without admitting aggregate constants or
general constant expressions as generic length arguments.

The original 136 constant fixtures remain selected. Twenty-two cross-feature
controls add nine successes and thirteen diagnostics, including range indexing,
constant comparison chains, dead dependencies, and retained annotations. The
final inventory is 158 fixtures: 79 successes and 79 diagnostics. Live fixtures
are canonically formatted and their selection hashes updated. Original donor
proof and the pre-format sources remain archived separately.

The outer test runner grants the constant evaluator boundary suite the same
500-million-step/1-GiB allowance already used by the profile boundary suite.
This lets the test reach the actual evaluator limit; the evaluator's own
65,536-work and 256-depth limits are unchanged.

## Verification

All results below use the final combined source and genuine installed packages.

| Check | Result |
| --- | --- |
| Qualified-seed source check | Passed |
| Live source formatting | 1,254 checked, 209 deliberate exclusions, zero failures |
| Ten focused producer suites | 66 tests normally and 66 with release facts/leak checks |
| Existing body harness self-tests | 97 passed |
| Constant admission | 1,422 operations normally and 1,422 with release facts/leak checks |
| Structural admission | 222 operations |
| Sequence iteration admission | 228 operations |
| Chained comparison admission | 219 operations |
| Authentic structural hostile replies | All 13 rejected |
| Main body qualification | 461 workflows and 922 comparisons in each mode |
| Warm deployment / live session checks | 30 / 4 in each mode |
| Forged body replies | All 92 rejected in each mode |
| New closure accounting self-tests | 6 passed |
| Build input inventory and coverage checks | Passed |
| Whole-tree Guardian | All 88 checks passed |

The dedicated source matrices total 3,513 operations with zero failures or
skips. Main qualification also retains transport and publication checks. These
dedicated runs do not include the coordinator edit check; the full repository
gate remains responsible for it.

`test-selfhost-body-closure` is now required by `zig build test`. It runs both
constant modes, the release structural/iteration/chain matrices, and the
authentic hostile mutations. Its accounting rejects missing, duplicate or extra
operations, changed source/deployment identities, changed transcripts, old
schemas, and native-only substitutions. The accounting tests also check these
failure paths; the validator separately accepted the actual installed reports.

## Artifact identities and evidence

- Native compiler: `ebf066de525f1940504e4df600a33c9f1e7e0d5be746a94a665c1d5598a52cea`.
- Qualified seed: `c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`.
- Body package key: `324a827e54955e244c413134b8f1858b2915adb1b57d6d82b68451d4f6dba67b`.
- Body executable: `22b464011f652eef67391ca439f77350d631679fa115675d4b8ca3625aa0d4c7`.

The [evidence receipt](evidence/selka-body-wave-integration-20261011/receipt.json)
binds the final source snapshot, deployment manifests, package receipt, scripts,
complete reports, authentic frames, and failed preliminary attempts. Executable
files are represented by hashes, not copied into the evidence archive.

The earlier full gate on `2a1f92edc1c962bc03d628bb132e0d93aa475187`
terminated unsuccessfully: 127/142 build steps, three failed steps. Its terminal
log and receipt are preserved. The known fixture/format/reservation corrections
are integrated; the Core compilation was separately terminated by earlyoom.
A new full gate on this integration is required before overall acceptance.

This closes a body-checking slice. Whole-language body coverage, common semantic
ownership, Core/LLVM and driver ownership, stage-to-stage bootstrap, and the
1.5× performance requirement remain open. No new performance claim is made.
