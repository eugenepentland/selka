# Wave 9 native compiler artifact qualification

This is an acceptance plan, not measured evidence. Baseline `8bb95ab0c`
already contains Wave 8 shared ordinary test-success receipts. This wave
qualifies opt-in immutable frontend artifacts and linked programs across
compatible project roots. Native unit/runtime object sharing alone does not
satisfy this plan. No deferred performance measurements are resumed.

Permanent tests live in `src/core/compiler_shared_cache_test.zig` and join the
existing `test-core` root. Fixtures create two actual
project directories with equal logical source names, explicit in-root
`mylang.json`, separate private `--cache-dir` locations and one configured shared
compiler store. The receiving private cache is absent or deleted before each
transport assertion; commands and native executables run in their respective
A/B working directories. Mutable inventories, replay indexes and invalidation
baselines remain private.

The opt-in configuration is `MYLANG_COMPILER_SHARED_CACHE=DIR`, independent of
Wave 8's test-receipt store. Immutable blobs live under
`DIR/compiler-artifacts-v1/{syntax,typed,program}`. Syntax and ordinary typed
bodies may restore while declarations and project policy resolve fresh;
successful verdicts and summary inventories remain private. The program key
requires identical ordered native object bytes and compatible linker settings.
No source path or string literal is rewritten.

Qualification requires actual syntax/check counters and
`cache-report-v1.program_shared=true`, with `compiled=0`, `processes=0` and
positive `units`. The frontend still checks/lowers/emits before shared program
lookup. A local replay or a native object hit cannot masquerade as shared
frontend/program work.

The acceptance matrix covers:

- Cold A, then B with an empty private cache: syntax and supported checked-body
  artifacts actually restore. An emitted-LLVM invocation may bypass program
  replay to expose frontend work independently.
- Cold A linked program, then B with an empty private cache: the shared linked
  executable restores with no compiler/link tool processes. The output and
  process exit status match a fresh build.
- A source dependency edit changes the receiving output; reverting recovers
  the prior immutable artifact. Mode, relevant environment and configuration
  changes cannot accept an incompatible shared executable. Environment controls
  include native layout and `SOURCE_DATE_EPOCH`; irrelevant guest variables are
  not required to produce a different executable. A stricter
  configuration is enforced before reuse.
- Same-length embedded asset edits change output, and reverting recovers the
  earlier result. Absolute path literals retain their exact bytes. Diagnostics
  and traps name the receiving project's source paths, with conservative
  rebuilding where relocation cannot be proved. In particular, headerless
  absolute source provenance misses while logical module paths may share.
- Corrupt frontend records, program records and executable bytes are misses;
  correct fresh work refills them before a later receiver accepts the result.
  Abandoned temporary files and partial publication states cannot be accepted.
- Two actual concurrent compiler publishers use separate allocators and private
  caches, then an empty receiving cache verifies their published artifacts.
- `--no-cache` and relevant verification controls suppress shared lookup and
  publication. Opt-out leaves the unconfigured shared compiler tier unused.
- Commands with an empty `PATH` and the pinned Zig provided explicitly perform
  shared compilation and reuse without Python. Existing installed-command
  qualification remains part of the full gate.
- Direct `check-project` commands independently prove cross-root syntax hits,
  private successful-verdict retention, format validation before a warm private
  replay, and `--no-cache` bypass without changing a malformed shared marker.
  Failed checks still diagnose the receiving graph after shared syntax reuse.

Focused builds and tests run through `scripts/build-slot.sh` with
`0.17.0-dev.1683+5ceec001b`, the shared Zig global cache, a worktree-private Zig
local cache and an on-disk `TMPDIR`. The parent owns compiler installation,
root/spec registration, full gates and the final report. No timing or
cross-machine reuse claim follows from this correctness matrix. Guardian
feedback logging is not required and the Guardian repository is not changed.

Focused qualification results are recorded in `qualification-summary.json`.
The acceptance plan remains separate from measured evidence; the parent owns
the final compiler identity and final full-gate result after all producer changes.
