# Borrowed provider context: tested proposal for coordinator integration

This adds the narrow local borrowing contract needed by A10's unchanged
`Context(fs=fs, env=env)` entry example. It is a tested private compiler overlay,
not an integrated C1, default promotion, package retirement or final gate claim.
The legacy RC implementation and selector still exist.

The source predicate admits a direct flat local record/tuple initializer with
provider fields rooted in immutable borrowed parameters/projections and otherwise
integer, Boolean, Unit, float, Stream or Host fields. It checks at most 64 fields
and 64 provenance steps; provider parameter positions must fit the existing
64-bit ownership signature. A `mut` local spelling does not grant structural
mutation. Read-only helper calls, field methods and scoped file acquisition work.
Nested **borrowed** contexts, mixed owning managed children, arbitrary local-root
borrows, escaping/storage/copy/mutation/partial moves and aggregate-parameter
resource-return inference remain refused. Nested **owned** providers retain their
existing supported behavior.

`src/core/borrowed_provider.zig` shares the exact source predicate between the
checker and builder. A compiler-only `myl_core_borrowed_provider_v1_<type>` call
constructs the inline record from borrowed fields. Its complete signature,
parameter provenance and nonconsuming result/projection uses are validated;
central marker validation also verifies CFG and dominance at fresh-pass,
ownership and cache-restore boundaries. Both Core inlining traversal paths refuse
the marker-bearing function, preserving parameter provenance. Emission assembles
the existing record ABI directly. There is no new runtime function, allocation,
reference count, parameter destruction or runtime helper admission.

The existing native `myl_core_provider_keepalive` body is exactly `(void)provider;`
(`src/core/runtime/core_io.c:1218`). Its noalloc classification additionally
requires the exact generated empty `runtime_c (capability)->void` declaration,
zero owned/consumes/views bits and zero source span. A source extern using the
same name or a malformed signature remains unresolved. The borrowed-context
marker uses a similarly exact declaration check for its noalloc classification.

## Exact artifact and integration inputs

`overlay-identity.json` records source hashes, component pin, helper hash and
compiler SHA256 `0fdd1d8afa9e7e833d5508888b3da0065b89935dbee4d6bb3aafb47e7254bc24`.
`overlay-reproduction.patch` reconstructs the private source overlay from
`07f16c65415819c36c46eb0657530abce734e395`, including the A07 validator arena fix and
scratch-only test registration. Build with the coordinator-supplied qualified
owned Support6 component pin/cache; the initial immutable legacy-seed preparation
failure is preserved in `evidence/borrowed-overlay-build.log` and is not a passing
build. The subsequent owned preparation and focused compiler build succeeded.

Coordinator should cherry-pick this evidence-only commit, apply `new-files.patch`
(the three exact new helper/test files), `shared-hooks.patch` and
`registration.patch`, then commit the complete registered implementation together.
`new-file-hashes.json` records the losslessly archived source files. The shared
patch contains eight reviewed consumer changes:
`single_owner.zig`, Core `build.zig`, `own.zig`, `emit_llvm.zig`, `verify_ir.zig`,
`inline.zig`, `marker_validation.zig`, and `cost.zig`. The inputs for that patch are
hashed in `shared-input-hashes.json`. Merge the marker-validation hooks with A07's
subsequent hardening; keep its scratch arena. Register
`borrowed_provider_test.zig` and `borrowed_provider_cache_test.zig` in the existing
Core test root. No production source files are changed by this evidence-only commit. Root
combines the hooks and new files on the current integration tree.

## Qualification

- Eight named focused tests pass (Guardian runner reports 8/8, build exit 0).
  The scratch registrations are in a comptime block. Tests cover exact source/IR
  contracts, malformed helper identities/signatures, consuming escapes through
  copies/projections, corrupt operand slices/cycles, all current inlining paths,
  exact noalloc contracts and a checksum-valid persisted snapshot with a corrupted
  owning parameter bit. The latter decodes structurally but cache restore refuses
  it. `evidence/borrowed-overlay-final-style-build.log` is the final raw receipt.
  Its runner prints a `failed command` line despite reporting all tests passed
  and process exit 0; both facts are retained, with no full-gate claim.
- `evidence/wrapper.json`: the final wrapper fixture passes all five modes:
  release, unoptimized debug, verified release, optimized debug, release without
  facts. It exercises a wide context containing Unit/float, provider projections
  from helper parameters, nested file scopes, early Err, repeated calls,
  independently owned caller providers, caller reuse and final destruction.
  Whole-program counters are 175 allocations, 12,448 allocated bytes, managed peak
  736 bytes, exit-live 0, runtime/shared RC events 0 in every mode. Its wrapper-only
  `scalar_context` function is admitted under `noalloc` and records zero
  allocations. These are traffic/managed-memory observations, not RSS or timings.
- `evidence/owned-regressions.json`: existing owned `provider_record` and
  `guest_capability_fields` each pass all five modes with zero RC/live bytes and
  clean LLVM/symbol audits. `evidence/preliminary-native-fixture-failure.json`
  preserves the earlier new-wrapper fixture syntax failure (`None` instead of
  Unit `()`); final receipts use the corrected fixture and final compiler.
  No original required assertion was removed. `evidence/native-raw.json` is the
  complete final raw native harness receipt; the two extracted reports explicitly
  classify the compiler as a private overlay, excluding it from C1 export gates.
- `entry_context.my` is byte-identical to A10's source, SHA256
  `cb4471d34b70ed9fdd4a43a8d8c7f6ff7bcd27258b01587ae4c2cd38011c87b1`.
  `evidence/entry.json` has 15/15 passing actual entry-provider executions:
  five modes times granted file, missing file and denied target. A dedicated
  environment grant supplies one actual environment name; successful file access
  returns 6, missing/denied targets return 0. Every run has zero managed exit-live
  bytes/RC events; compiler markers and legacy RC symbols are absent. No factory
  replaces the entry authority in this fixture.
- `evidence/negative.json`: all nine source negatives pass ordinary checking and
  refuse checked ownership, with specific diagnostics for return, copy, field
  extraction, field mutation, rebind, nested borrowed storage, mixed owning text,
  owning tuple unpack and aggregate-parameter resource return.
- `evidence/cache.json`: cold build links; warm and warm-after-layout-edit runs
  reuse the complete program; an earlier used record forces a fresh link; invalid
  borrowing still refuses; restored and relocated sources reuse and execute
  correctly. Six native executions plus one expected refusal pass. Raw cache
  reports record actual reuse; no compile-time speedup is claimed.

The first worker production commit attempt is preserved in
`evidence/first-worker-commit-gate.log`. Guardian rejected the orphaned new files
and absent shared dependencies in the older worker branch, plus style findings.
The boolean/conditional-test style findings were corrected and the complete
private overlay was rebuilt and rerun. At coordinator direction, final source
files were archived, roundtrip-checked and removed from this older production
tree; the evidence commit leaves integrated registration and its gate to root.
No whitelist or fake registration was added to bypass that failure.

All final results above use the exact same final overlay compiler. Final C1 must rerun
the required combined checks, export/application matrices and full gate after
coordinator integration; the overlay does not qualify the complete installation.

## Shared SPEC request

Extend `CAPABILITY-FIELD-METHOD-1` with the implemented contract: a direct flat
local record/tuple may borrow provider fields from immutable function parameters
and otherwise hold unmanaged scalar fields; its identity is borrowed for that
invocation, cannot be moved, copied, stored, returned or structurally mutated,
and may be read/passed to ordinary helpers or used for scoped acquisition.
Nested borrowed wrappers and aggregate-parameter resource returns remain outside
this bounded rule. Owned provider aggregates retain ordinary transfer/cleanup.
