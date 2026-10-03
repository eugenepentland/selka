This isolated trial enables the already reviewed native V2 variant glue only for
the resolved QBE backend with the current compiler producer. Standalone emission,
LLVM (including the retired `qbe_llvm.py` spelling), foreign overrides, GC and
counted RC retain the original helper path. No Lox source changes or performance
runs were made in this lane. Selection and integration belong to the parent task.

The compiler patch is against `3b33df52044a10cb84b908f8b1641af439e8c729`.
It uses zero-context hunks; replay with `git apply --unidiff-zero compiler.patch`
in a clean checkout of that base.
The bounded V2 bodies come from `9ab993c1b9e2088c471ea1b57c98361b8554d0ae`:
declared edge-free cases may copy/clear complete value bytes, while managed,
unique, malformed, large/niche/domain and overlapping cases retain the original
checked helper. Take keeps its unsigned region-depth guard. Original policy
refuses before layout/catalog/temp queries, so it cannot disturb declaration or
temporary numbering. This trial adds no new ownership authority or external IL
proof metadata.

Policy is selected before frontend, module/config, imported-unit, fragment,
manifest-replay and native-test cache lookups. Only a current producer receives
the internal flag. Foreign overrides receive the established argv. External
`--manifest-file` remains an unchanged checked-input route; no transformation or
admission is added there. The selective CLI and retained native-test session
forward only this new policy field, keeping their existing COW counting, debug,
step and frame defaults. Whole-project full-policy emission is unchanged.

The final source descriptor is `.tmp-lox-native-policy-20261003/frozen-source-v2.json`
(SHA256 `d2962dbc3edc07a9e505e702eb6cf547e198dbc42eb67e94c5e38b10e696cb43`).
It binds 878 core/build/test inputs and all 37 selected AST files. Its `core_copy`
is the authoritative corrected `frozen-core-v2` copy; inherited `proof_source`
still names the historical V1 proof body, which is unchanged. No frozen V1 files
were overwritten. The installed final compiler is
`.tmp-lox-native-policy-20261003/compiler-final-v2/bin/mylang`, SHA256
`81fe478471d256e9c6023d786b61dd6183f3b51363c4abe9d1d015c1268600cc`.
Its entire bin/lib prefix is owned, with an owned adjacent QBE SHA256
`99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63`.
No install step writes through a symlink into a frozen prefix.

Final receipts in that scratch directory:

- `builds-v2.json`: four successful actual RC/GC guests, LLVM O3/LTO and explicit
  pinned QBE, with source/tool/runtime/binary identities before/after.
- `equivalence-v2.json`: all 420 selected LLVM units and metadata are byte exact
  to d14; LLVM RC/GC and QBE GC ELF headers/program/allocated sections are exact.
  Full ELF files differ only in recorded nonallocated debug metadata. QBE RC is
  the optimized arm. These are reproduction facts, not speed claims.
- `public-v2.json`: 84 tests × QBE Debug/LLVM release × default checked RC/native
  tracing GC stress = 336 fresh passes. Names, zero cache/skips/failures and source
  hashes are asserted. Directory runs omit `--cases`: provider entries are
  structurally preserved, without a provider-backed execution claim.
- `native-v2/completed.json`: 1,168 bounded exact comparisons (416 RC, 416 ordinary
  GC, 336 native GC stress), 96 additional AST comparisons and eight exact RC
  native-stress refusals. Status, full stdout/stderr and Lox stats match controls.
  Eight refusals are not program passes; 80 native-GC-stress smoke cells remain
  explicitly unrun. The prospective `native-v2-ceiling.json` pins the sole copied
  helper change, process timeout 120→240 seconds; inputs, errors and omissions
  remain unchanged. No timing conclusion is drawn from behavioral timeouts.
- `selected-boundaries-verified-v2/qualification.json`: 40 actual commands,
  including 20 V2 comparisons against d14 and eight separate historical V1
  comparisons. Every V2 selected/session IL and raw metadata file matches the
  control under counting 0/1 and explicit selective drop flags. Only the physical
  fragment-store root is normalized. BLAKE3 reference names and dereferenced
  bytes are compared; independent artifact SHA256 is recorded. The whole-project
  GC witness emits COW tally calls. Historical V1 GC-counting mismatches are
  reproduced, not attributed to V2.
- `producer-check-final-v2/qualification.json`: 12 cold/warm actual producer
  checks, resolving QBE, LLVM and legacy LLVM, with foreign wrappers that reject
  any new flag. Foreign checks use whole-program builds and preserve captured
  old argv; the underlying compatible producer is this trial compiler.
- `policy-v2-frozen-focus.command.json`: 20 policy unit and five CLI checks pass.
  `guardian-v2.command.json`: all 88 checks pass. The earlier V1 2,495 unit tests
  passed in eight bounded shards; main/CLI correction did not alter those unit
  source files, and that historical result is not relabeled a fresh V2 broad run.
  Fresh `inherited-v2-focus` passes19 (12 common blocks also appear in policy20).
  `qbe-gate-v2` executes515 tests in five roots, plus its golden root checks231
  corpus cases with373 explicitly skipped corpus entries and zero mismatches.
  Its five Guardian checks are cached zero-blocking; `gate-postflight-v2.json`
  records the owned installed gate tools separately from the pinned99ad guests.
- `postflight-v2.json`: retrospective current binding for full prefixes and all
  current imported helpers. Native full-prefix equality was asserted by the
  guarded runner in memory; its completed receipt does not retain those full
  maps or a prospective registry of every imported helper. Actual used compiler,
  guest, sidecar, runtime and input before/after hashes are retained. No rerun or
  retrospective prospective-coverage claim is made.

The four final guest file hashes are:

| Runtime/backend | SHA256 |
| --- | --- |
| RC/QBE | `f83bed941450b3b1e7050ee7dbcb5d6c111a756f9470b1aeafdd8f5221cb9f92` |
| RC/LLVM | `b4bebf2c708fc41e11ac0d179b8cd9769177d58672b9f1bcff780cbd2ac2b371` |
| GC/QBE | `04b1f3bbca3f72f691ed006c2d9e49fccc39c8f7a8c1e3702ee5b3daa79abb90` |
| GC/LLVM | `5a29241c1a7235be7999e4941c9d5bd0efd759b4eb53e1fa778b546ce5967f61` |

Historical failed attempts remain in the evidence archive and original scratch.
The first 876-file descriptor omitted two unchanged root build inputs; complete
878 scope was established prospectively. V1 forwarded full parsed policy at two
old-default boundaries; V2 corrects that finding. V1 native validation stopped
after 80 comparisons at a real 120-second GC-stress timeout, so it is incomplete.
A separate 240-second diagnostic passed for both candidate and exact control;
it is not an isolated original-120-second pass or evidence of host contention.
Compatibility harness failures preserve their raw status/streams: old frontend
cache spelling, build-slot diagnostic envelope, forbidden explicit runtime
flags for retained sessions, lean-reference decoding and a SHA256/BLAKE3
assumption. The final receipt resolves those harness mistakes.

Guardian initially reported seven maintainability issues: linked spec-primary
tags, public test fixture docs, parser cognitive complexity, an unused default
API, struct field counts, line width and a repeated runtime import. Fixes link
the contract, keep/ref-test the old default API, extract option parsing and group
ownership/tool settings. No waiver, ratchet acceptance or gate disabling was
used. Parent owns the consolidated Guardian feedback entry.

Replay in a fresh isolated checkout of this commit with the pinned local controls
available, including an OWNED copy of historical f0 `compiler-final` under the
new scratch directory (required by the historical comparisons): run `freeze-v2.py`, build with `scripts/build-slot.sh build zig build
-Doptimize=ReleaseFast -Dcompiler-only=true --prefix
.tmp-lox-native-policy-20261003/compiler-trial-v2 --cache-dir
.tmp-lox-native-policy-20261003/release-cache-v2`, then run `install-v2.py`.
Set private `TMPDIR`, `ZIG_GLOBAL_CACHE_DIR`, and `MYLANG_TIMING_CPUS=2,3,10,11`.
Run `build-v2.py`, record full default LLVM `emit-project-qbe` for the selected
AST with `--rc-runtime --drop-debug --drop-step-checks --drop-frame-checks
--no-cache` as `llvm-v2-emission.stdout`, and retain the equivalent d14 output as
`llvm-control-emission.stdout`. Then run `equivalence-v2.py`,
`selected-boundaries-v2.py`, `producer-check-v2.py`, `public-v2.py`, and finally
`scripts/build-slot.sh build python3 .../native-v2.py`. Use distinct new scratch
outputs, without overwriting historical receipts. `record.py` captures outer
argv/environment/status; replay scripts retain raw streams and exact identities.
All actual build/test phases use build slots and exclude CPUs 2,3,10,11.
