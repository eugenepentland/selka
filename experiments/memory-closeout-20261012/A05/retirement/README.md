# Prepared A05 retirement changes — not applied

This directory is a Stage 4 preparation artifact. It does not satisfy legacy RC
retirement and must not be counted as an implementation milestone. Production
runtime files retain their opt-in branches until coordinator approval after C2.

`prepare.py` generates exact context patches and original/candidate SHA256
manifests. It reads production files and writes only this evidence directory plus
`.tmp/memory-closeout/A05/retirement-preview/`. `git apply --check` passes for both
patches on A05 revision `5a62e26c473e4033626e6340a8c74e896e13bf8e`.

`runtime-retirement.patch` changes four owned runtime files; `core_host.c` has no
RC selection/helper path and its unchanged hash is included in the manifest.

- `core_dict.c`: use direct child drops; remove count uniqueness and child-retain
  cloning; use the ordinary direct-destruction visitor. Preserve layout-driven
  key/value destructors and metadata cleanup. `myl_core_dict_copy` remains an
  independent **scalar-only** storage copy; managed descriptors are rejected and
  compiler-generated deep copies use `core_dict_copy_storage` plus owned children.
- `core_sort.c`: remove `myl_core_s2_sort_keyed`, the borrowed shallow-cloning
  legacy entrypoint. Preserve `myl_core_owned_sort_keyed`, its permutation-cycle
  moves, direct key destruction and native scratch cleanup. In-place scalar sorting
  remains.
- `core_io.c`: select the owned layouts and copies, use direct destruction, remove
  the provider retain/root-transfer functions and their now-unnecessary calls.
  Root capabilities own provider state; dependents own scope bytes and borrow
  parents. Resources borrow providers through checked lexical/IR lifetime uses.
  Provider callbacks, native buffers, the keepalive marker and cleanup stay.
- `core_durable.c`: remove the obsolete retained-capability call at acquisition.
  OS directory locking, publication/fsync semantics, native descriptor cleanup and
  direct owner destruction stay unchanged.

The preprocessor transform resolves only `MYL_ZERO_RC`; unrelated conditional
compilation remains. Additional edits are exact reviewed call/function removals.
The words snapshot/unique/release are not removed globally: provider snapshots own
independent native bytes, unique-directory means OS exclusion, and provider release
callbacks consume handles without memory reference counting.

## Coupled changes required before applying

1. A02/coordinator must make the owned `myl_block` layout, storage-kind handling,
   `myl_core_drop_owned`, `core_child_visitor`, and the `core_dict_children` forward
   declaration unconditional. A05 requires no new shared header ABI or fields.
2. A07 must remove the alternate symbol selection at Core `build.zig:2365` and
   use only the owned keyed-sort contract. Its exact two-input consuming contract
   stays `owned=3, result=transferred`. Generated dictionary copy/drop helpers and
   LLVM declarations must remain consistent with the owned descriptors.
3. `fixture-retirement.patch` migrates the current durable C fixture from RC calls
   to explicit transfer/drop, then removes the ordinary/owned selector from its
   Zig test. It removes only the duplicate ordinary invocation: the complete
   existing short-write, bounds, fsync, readdir, actual SIGKILL, concurrent-writer
   and directory-lease assertions remain in the owned test. This patch touches
   `durable_fixture.c`, which requires the coordinator's Stage 4 reservation/apply;
   A05 has not edited that production file.
4. The fixture patch removes `-DMYL_ZERO_RC`, so it must land with the unconditional
   owned root runtime. The scratch preview still defines that macro for unmodified
   non-A05 runtime files; it is native evidence only, not final Stage 4 evidence.
5. A08 must invalidate old runtime/ABI artifacts and receipts; A10 must qualify
   the installed components/commands. No immutable seed, historical commit or
   separate self-hosting branch is changed here.

After coordinated application, rerun the registered durable native test, A05's
full public-library/guest matrix, A07 ABI/LLVM/symbol checks, cache invalidation and
the complete registered gate on one frozen compiler. Recreate persistence outputs
for the new compiler identity; do not adopt an earlier binary's measurements.

The scratch native preview passed all durable scenarios with leak checking and no
legacy RC symbols. Exact runtime SHA256
`75f189cf8705f1c93f051a00861afdcf9d4b319446ede601c019653472cede52`, binary
`ac592358fb139e4936d45ec2d06b8797b67a92ef1a6f956138615b65e8d4a1d2`;
`native-preview-result.json` contains the full inputs and outputs. This preview
does not qualify the compiled guest ABI or the final installed package.
