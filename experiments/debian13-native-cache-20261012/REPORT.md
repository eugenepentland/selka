# Debian 13 native-cache review candidate — 2026-10-12

This branch supplies source, a reproducible authenticated runtime bundle, a
Python-free launch wrapper, and qualification scripts. **It is not a fully
qualified bootstrap release.** The required complete gate is blocked by the
existing immutable component seed; default component-mode guest testing also
fails at sealed executable launch inside this host's user namespace.

The development-loop work is already merged into local `main` and published to
`origin/development` at `4892aaba4e3fa9076cc5f2c8590f3f2f89500cb9`.
`origin/main` is the separate published snapshot and was not changed.

## Source and ownership

- Review branch: `codex/debian13-native-cache-20261012`.
- Bootstrap base: `dff9304b9cd7bc72e66f9feb20f1b05281d67333` on
  `codex/selka-bootstrap-20261011`.
- Prerequisite: `79c6f874a0c25f09f9f8b02e135ead1a28cc886a`, adoption of the
  previously approved native-link fix `632726724`. It keeps uncached unit
  objects alive through linking. The original bootstrap test imports remain;
  only that fix's test was added.
- Remote unpublished `d36aeeffd9f15caff10c960b17431b1fc43fb401` was unavailable
  in this clone. Its checkout and branch were not modified. Review and apply the
  candidate onto that work without resetting it.
- Zig remains `0.17.0-dev.1683+5ceec001b`. No language ownership, runtime ABI,
  component authentication, default memory mode, or bootstrap seed policy changed.

## What the profile approves

The profile `debian13-amd64-minimal-20260912-v1` approves the exact extracted
bundle, **not arbitrary installed Debian 13 machines**. The remote VM was not
available, so no claim is made about its Debian 13.6 package layout. The frozen
archive release used here is Debian 13.7, dated 2026-09-12.

The checked-in [manifest](../../scripts/native-platform/debian13/manifest.json)
and `InRelease` preserve the provenance chain:

1. Keys and primary fingerprints reviewed against Debian's
   [archive key page](https://ftp-master.debian.org/keys.html).
2. `gpgv` verifies all three pinned archive/release signatures over the retained
   `InRelease`; changing only a hash in the manifest cannot replace this check.
3. The signed release authenticates the complete amd64 `Packages.xz` hash and
   length; its exact package records authenticate each `.deb` hash and length.
4. `dpkg-deb -x` extracts only those packages. No maintainer scripts execute.
5. The authenticated Debian `ldconfig -X` creates the loader cache inside the
   bundle. Its exact digest and the full extracted tree (files, modes, symlink
   targets, directory membership) must match the reviewed pins before publication.

Packages are `base-files 13.8+deb13u7`, `gcc-14-base 14.2.0-19`,
`libc6` and `libc-bin 2.41-12+deb13u4`, and `libgcc-s1 14.2.0-19`.
`gcc-14-base` supplies its package data, not a GCC executable or headers.
Runtime ELF dependencies close over loader, libc, libm, libpthread and libgcc_s.
The probe exercises threads, math and backtrace; the latter dynamically loads
libgcc_s. Readelf and actual debug/release compiler traces are retained below.
No new source-to-Clang-binary build attestation is claimed.

The launch wrapper binds only this root, the pinned Zig distribution, compiler,
authenticated component fixtures when present, and the project. Host `/etc`,
`/usr` and `/lib` are not overlaid. Fixed tool placement makes sibling resources
and absent GCC/header candidates reproducible. It requires Bubblewrap and
unprivileged user namespaces on the launching machine.

Provisioning is a developer operation using Python, GnuPG, `dpkg-deb` and
Bubblewrap. Ordinary compiler builds and installed commands remain Python-free.
Retain the authenticated downloads: future archive removal causes a closed
failure, not a switch to newer packages or refreshed pins.

## Cache contract

Runtime and discovery must match the **same complete profile**. Catalog identity
binds profile ID, runtime paths/canonical targets/hashes, preload path, discovery
descriptors and state into content, generation, hint and approval identities.
Observed discovery state is included in semantic content identity too, so two
approved profiles with different directory membership cannot collide merely
because their regular files are identical.

The inventory unions the profiles' dependencies and preserves the strongest
guard for duplicate paths. Missing inputs, symlink retargets, directory membership,
restored mtimes and changes during capture still invalidate authority. Existing
Zig and library pins and environment-override refusal remain. Unknown profiles
execute without native-cache approval; there is no production profile override.
The catalog addition conservatively invalidates older keys once.

## Qualification

The exact source hashes are in [candidate.json](evidence/candidate.json).
The checked evidence is scoped as follows; a focused pass is not the full gate.

| Requirement | Result and evidence |
| --- | --- |
| Affected native identity/discovery tests | **Passed:** 35 selected tests, [log](evidence/focused-tests-final.log), including mixed-profile rejection, policy/replay isolation and membership-only identity changes. |
| Provisioning failure tests | **Passed:** four tests, [log](evidence/provision-tests.log), including corrupt downloads, signature rejection, membership and symlink tampering. |
| Authenticated reproducible bundle | **Passed:** signatures, package records, [receipt](evidence/bundle-receipt.json), and [tree](evidence/bundle-tree.json). Recreated under umask 077 with the same exact tree pin. |
| Runtime dependency probe | **Passed:** pinned Zig at O0 and O3, ELF closure, math/thread/backtrace; [runtime.json](evidence/runtime.json). |
| Debug compiler, default planner: fresh/replay/object reuse/edit | **Passed:** four fresh units, unchanged replay, all four objects reused after replay deletion, one unit rebuilt after leaf edit, correct guest output; [report](evidence/qualification-debug.json). |
| Debug compiler, default planner: warm guest tests | **Not qualified:** first test command fails sealed cache-plan executable launch with `EACCES`; no warm-result claim. |
| Debug and ReleaseFast reference-planner matrix | See [matrix status](evidence/matrix-status.json). This explicitly selected diagnostic mode does not qualify the default component path. |
| Complete verification gate | **Blocked/failed prerequisite:** 29/148 steps succeeded, 10 selected tests passed before failure. [Full log](evidence/full-gate.log). This is not a passing gate. |
| Debug and ReleaseFast compiler production | Both candidate compiler binaries compiled and installed; aggregate build failed at fresh component production. [Debug](evidence/debug-build-with-driver-fix.log), [ReleaseFast](evidence/release-compiler-with-driver-fix.log). |
| Real Debian 13.6 VM and full profile isolation integration | **Not qualified here:** VM unavailable; identity isolation has focused fixture coverage. Repeat the entire acceptance matrix there. |

The component fixtures in [components.json](evidence/components.json) were copied
from the existing bootstrap installation and checked against all seven manifests'
artifact hashes. They are evidence inputs, not proof of fresh component builds.
The runtime probe predates the deterministic generated mountpoint permissions;
its runtime files and loader cache match the final bundle byte for byte.

### Blockers to finish on the bootstrap workstream

1. The immutable seed from `0689d3407c17df34915aeb2a92e309af3a04921c` deletes
   uncached native objects before linking on this unapproved host. Adopting the
   driver fix in the candidate cannot change that existing seed. Refresh or
   replace the seed through the bootstrap owner's authenticated procedure, then
   rebuild components and repeat the full gate. Do not edit its cached binary.
2. On this host (kernel `7.0.0-31-generic`), sealed cache-plan execution via
   `/proc/PARENT/fd/N` fails with `EACCES` inside Bubblewrap. The disk artifact runs;
   a minimal sealed-memfd probe succeeds outside Bubblewrap and fails with a
   read-only bind of the original host root too. This is not proof that Debian
   libraries are defective. The exact host policy cause remains unresolved.
   No component authentication or kernel policy was weakened. Qualify the normal
   component launch on the target VM before calling this launch path accepted.

## Remote continuation

Fetch this review branch without resetting your unpublished work. Inspect the two
candidate commits against `d36aeeffd9f15caff10c960b17431b1fc43fb401`; skip the
prerequisite only if its native-link lifetime fix is already present. Keep this
work separate for the requested review before integrating into bootstrap.

From the candidate source, materialize a new bundle and use an installed compiler
whose adjacent `libexec/mylang/components` contains authenticated components:

```bash
python3 scripts/native_platform_bundle.py /path/to/new-bundle \
  --downloads /path/to/private-retained-downloads
scripts/native-bundle.sh /path/to/new-bundle /path/to/pinned-zig-directory \
  /path/to/install/bin/mylang /path/to/project -- build app.my --report
```

Run the owned-fixture acceptance under ordinary build admission, once with the
Debug compiler and once with the ReleaseFast compiler, using new work directories:

```bash
scripts/build-slot.sh build python3 experiments/debian13-native-cache-20261012/qualification.py \
  --bundle /path/to/new-bundle --zig /path/to/pinned-zig-directory/zig \
  --compiler /path/to/install/bin/mylang --work /path/to/new-scratch \
  --report /path/to/results.json --adverse
```

The default is component mode. `--planner-mode reference` is an explicit
diagnostic option and must be reported as such. The harness tests guest debug
and release builds in each compiler run, corrupt owned objects, and mutate only
owned bundle/tool copies. It never changes system libraries. Then run affected
native tests and the complete `zig build test fmt-check --summary all` under gate
admission. Return the final commit, compiler hashes, complete gate outcome and
both acceptance reports; report failures or incomplete coverage explicitly.
