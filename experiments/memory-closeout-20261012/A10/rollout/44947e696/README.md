# Retirement audit and isolated drafts at 44947e696

Source: `44947e6967d8eb0deeaa86b25ca2bb44bc58803d`. This is preparation, not
milestone 1, 2 or 3 completion. No default, runtime retirement or package pin is
applied by this changeset. Historical `selfhost/component-seed.json` is unchanged.

`retirement-checklist.md` and `retirement-inventory.json` classify the remaining
active paths into 13 semantic owner groups, with exact source hashes and line
anchors. The registered-file selector inventory includes both tests and shared
helpers/dispatch in files containing tests; enclosing contexts and importers are
recorded so production dispatch is not mistaken for a positive test invocation.
Fifteen current control suites retain every test name for owner review.

`internal-api-calls.json` records 542 import-qualified calls in 84 source files,
28 local implementation wrappers, type constructors and mode fields. These are
inventory sizes, not bug counts or passing tests. Every inline-source/hand-IR
entry still needs the mandatory ABI/source-checking migration; no broad test
filter or forced RC control is an acceptable replacement.

The coordinator approved this precise C3 interface:

- `guest_abi.Abi = enum(u32) { checked_owned_v1 = 0x4f574e31 }`, with
  `guest_abi.current` and identity `mylang-checked-owned-v1`.
- `Module` and `build.Input` have the fixed ABI and lose `single_owner`,
  `zero_rc` and `shared_lists`. Source `validate`/`check` always enforce the full
  owned contract; ABI metadata does not replace eager checking.
- Persisted/native artifacts require the ABI without a default; formats/keys
  change so old missing/false/zero metadata cannot decode as checked-owned.
  Link validates every unit, replacing the current OR of mode booleans.
- A real C3 component compiler pin and installed manifests require
  `memory_mode=zero-rc-v1`, `ownership_selection=checked-default-v1`, and
  `guest_abi=mylang-checked-owned-v1`.

## Prepared patches

| Patch | Scope and prerequisites |
| --- | --- |
| `C2-default.patch` | Ordinary command defaults/help after C1 qualifies. No runtime deletion. |
| `C3-cli-selector-retirement.patch` | Reject both prototype flags with exit 2; preserve guest data after `--`; remove directory/doctest forwarding. Apply after C2 and combine with the mandatory internal API migration. |
| `C3-component-retirement.patch` | Independent owned-only builder and native qualification route; reject missing/foreign selection/ABI pins; preserve the newly integrated `build.lock`. |
| `C3-root-component-default-request.patch` | Coordinator-owned root recipe selects the separate real owned pin by default and forwards it to both provision and native tests. No pin file is fabricated. Existing component input glob already includes it. |
| `C3-component-launch.patch` | Both installed adapters reject missing/old/foreign ABI or ownership metadata, including changes after planner binding. Existing digest/protocol/failure/cleanup fixtures remain. |
| `C3-verification-package-request.patch` | Coordinator-owned verification inventory/provider selection requires the same metadata and actual artifact digest. Includes fake-provider fixture updates and negative tests. |

The CLI patch deliberately does not remove internal `Codegen`/session mode
plumbing; that companion must follow the agreed A07/A08 API. The runtime and
lowering owner patches are separate. Prepared patches cannot establish legacy
RC retirement while active implementations remain.

## Isolated validation

`validation-own1/validation.json` binds the tool, builder, exact patches, commands
and raw logs. One shared build lease ran these checks successfully:

- Native LLVM ReleaseSafe component builder; 29 fake-tool orchestration and
  native-qualification argument/result tests.
- 11 test-index and 19 cache-plan protocol tests, including all existing
  allocation-failure, process deadline, changed-binary and cleanup assertions.
  New cases reject missing/legacy/opt-in/foreign markers and independently change
  all three markers after a warm binding of the same binary.
- Three Python verification-package boundary tests.
- Scratch Zig formatting and forward/reverse patch-application checks.

The 30 Zig protocol tests include the shared manifest test in each binary. This
is 30 executed tests, not 30 unique declarations. Synthetic manifests/scripts
test admission and orchestration only; they do not qualify a real guest ABI.
One earlier draft test trapped because a fixed-size memcpy used unequal string
lengths; allocated replacement fixed the test before this exact successful run.

`final-draft-checks.json` records the subsequent help-only C2 adjustment and new
root-forwarding request. Their formatting/application checks passed, and the
three native-tested package/launch/verification patch hashes stayed unchanged.
No full registered C2/C3 gate or actual installed C3 compiler/package was run.

## Remaining package boundary

At the pinned revision, omission of the owned build option still selects the
historical seed, and installed `tools/selka-components` still exposes that route.
Both component adapters accept old metadata through `component_launch`; the
verification inventory validates only filenames. These are active boundaries,
not merely historical Git matches. The patches above close them only when
applied together with an actually qualified new pin and installed package.

The default installation has `bin/mylang`, `tools/selka-components`, and the
test-index/cache-plan manifests plus their two native guest artifacts under
`libexec/mylang/components`. Compiler and builder are Zig programs; the two
language components require their own owned guest qualification. `reference`
and `shadow` component modes select explicit host oracle behavior and need not
be retired as memory modes.

Support6 independently provisioned RF ownership-selected components have real
protocol/count/LLVM/symbol evidence. That compiler still requires the prototype
flag and cannot serve as the selector-free C3 pin. Preserve its evidence and the
immutable historical seed; create and qualify the actual C3 source archive,
compiler, guest outputs and installed receipts only after the source is ready.

The ordinary C0 native counter build failure remains recorded separately. A09
now has 8 manually replayed counted C0 artifacts covering all 15 calibrated
inputs with exact outputs and clean counters/structural audits. A final candidate
must repeat that method and normal/manual controls; this retirement audit does
not relabel those measurements or the unchanged uninstrumented timing controls.
