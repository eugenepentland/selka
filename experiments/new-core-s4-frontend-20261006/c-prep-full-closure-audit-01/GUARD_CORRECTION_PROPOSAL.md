# Conservative full-tool discovery correction (proposal; no source edits)

The current full helper has a reproduced input-closure gap. Keep all 20,907
existing inputs and fix that gap before final M/cache qualification. This is
separate from Wave B work on smaller per-action inventories: an observed trace
does not establish an action certificate, and a successful full-tool correction
does not establish the 7 ms/17 ms unchanged-build gates.

## Retained executable evidence

The protected corrected M compiler is SHA-256
`d6e4220ad8a833f3d56510eb5958637e25f9c367071949db281d64584d3bface`.
Its actual Debug `build` succeeds and the guest returns 7. The original runtime
C action and final compile/link action are retained separately, including every
descendant. `runtime-c.json` / `program-link.json` preserve their real argv.
Both use the approved pinned Zig executable, explicit bundled
`x86_64-linux-gnu.2.31`, existing CPU/options, and fresh native caches.

| Actual action | Distinct paths | Direct existing snapshot | Existing directory lookup guard | External discovery without a guard |
| --- | ---: | ---: | ---: | ---: |
| Runtime C | 420 | 178 | 152 | 64 |
| Final program/link | 2,608 | 873 | 734 | 65 |

The remaining categories are owned inputs/output and their CWD/parent traversal,
tool alias traversal, process-local kernel views, entropy, and four `/tmp`
staging paths. Counts are path counts, not syscalls.
No successfully read bundled file lacks a direct file snapshot. Both native
actions read `/etc/lsb-release` and resolved `/usr/lib/os-release` outside the
inventory. Exact failed lookups, enumeration, alias targets, and post-probe
metadata are retained. Directory snapshots guard lookup membership, not the
content of arbitrary descendants; this distinction is explicit in the table.

`guard-red-summary.json` is the stronger counterexample. A task-owned copy of
the actual approved Zig plus the full approved adjacent library tree remains
`cacheable=true` before and after an initially absent sibling resource is
created. The current helper returns `unchanged=true`, identical digest and
generation, and 20,907 inputs. Fresh native compilation subsequently opens and
reads the new `lib/clang/22/share/ubsan_ignorelist.txt` outside the adjacent tree.
All commands succeed. The object bytes remain equal: this proves a guard/key
omission for a real consumed input; it does not claim changed output.

## Primary-source boundary

Local Zig Git objects at `5ceec001b5` match the distribution's named revision
and explain injected `--no-default-config`, `-nostdinc`, bundled headers/CRT,
LLVM depfile exclusion, Clang argument construction, and actual linker grouping.
The linked Clang reports 22.1.8. Official LLVM `llvmorg-22.1.8` Linux/Gnu/Distro,
ToolChain and SanitizerArgs sources are retained with URLs and whole-file hashes.
They explain every discovery branch listed below and agree with the executed
driver observations. They are not a reproducible source-to-binary attestation
of the linked distribution. Restrict eligibility to the exact reviewed binary,
target, generated input policy and approved discovery state; do not extend this
reasoning to arbitrary Clang builds or flags.

## Minimal bounded implementation

Add a discovery input collector to the full helper, called by cold inventory
construction regardless of later eligibility. Reuse `Input` file/directory/
absence records, streamed hashes, symlink resolution, before/after validation,
and existing candidate/ticket/final-guard paths. Add a reviewed discovery policy
to the Core-only platform configuration. New nonempty or unsupported branches
must bypass persistent reuse; they must not silently become trusted after a
fresh inventory. Keep tool capture and generation guards on the private native
fallback. Preserve the original environment and every existing input/flag.

The smallest policy for this platform can refuse a present sibling library
root, `/opt/rh`, and `/etc/env.d/gcc`, rather than inventorying unbounded new
trees. Capture their absences before granting reuse. The real guard reducer's
copy already has an unreviewed sibling resource tree at initial capture; under
this policy it correctly becomes ineligible immediately. A separate initially
absent sibling-root regression must show `unchanged=false` after creation.
Approved executable/library copies can still qualify when their own parent
discovery state satisfies the same policy.

| Discovery branch and primary location | Required capture or conservative refusal |
| --- | --- |
| Zig executable/library selection; local `src/introspect.zig` / actual `/proc/self/exe` and `lib/zig` then `lib/std/std.zig` probes | Keep full adjacent and override trees. Bind canonical executable and its lexical parents/aliases. Higher-priority `lib/zig` is already protected by adjacent-library membership. Guard every additional outside-parent selection candidate if it becomes reachable; unsupported layout refuses reuse. |
| Distro fallback; `Distro.cpp` 23–190 | Capture `/etc/os-release`, `/usr/lib/os-release`, `/etc/lsb-release`, `/etc/redhat-release`, `/etc/debian_version`, `/etc/SuSE-release`, `/etc/gentoo-release`. Preserve presence/absence, exact contents for regular files, symlink target and logical/resolved paths. Approve only reviewed platform content/type state. Later fallback branches are covered even though current Ubuntu `resolute` returns after LSB. |
| GCC prefixes; `Gnu.cpp` 2088–2223, 2251–2319 | Fixed Core argv uses no explicit GCC install/triple/toolchain or Clang sysroot override. Candidates are the tool's parent prefix then `/usr`. Capture both selection roots and relevant library roots. Guard absence of `/opt/rh` and `/etc/env.d/gcc`; either becoming present disables reuse, covering every RHEL toolset and Gentoo `CURRENT`/`LDPATH` branch without following outside trees. |
| GCC aliases/library roots; `Gnu.cpp` 2364–2382, x86 dispatch 2627–2644 | Cover `/lib64`, `/lib` and biarch `/lib32`, `/libx32`, `/lib` under each permitted prefix. Cover `gcc` and `gcc-cross`, then every fixed-target/biarch triple candidate listed below. An absent enclosing root can protect all deeper candidates. Capture resolved directory aliases. |
| GCC version enumeration and selection; `Gnu.cpp` 2767–3003 | Guard exact version-name membership of every present candidate directory, not only selected version 15. Initial bounded approval allows only reviewed candidates/membership; a new valid version/triple disables reuse. Capture selected `crtbegin.o`, and all `64/32/x32/sparcv8plus/crtbegin.o` presence/absence branches. Hash present files conservatively. Guard relevant C++ include-directory existence used by selection/warnings; no header contents are read by this branch. Refuse unexpected membership or externally retargeted paths. |
| C++ include existence; `Gnu.cpp` 3286–3410 | For reviewed version 15 capture selected `include/c++`, `/usr/include/c++/15`, `/usr/include/x86_64-linux-gnu/c++/15`, `/usr/x86_64-linux-gnu/include/c++/15`, and installation-local `include/g++-v15`, `include/g++-v15.<parsed-minor>` and `include/g++-v15` fallbacks. Debian detection also checks its derived multiarch directory. `-nostdinc` prevents generic system header inclusion; it does not prevent GCC detector existence tests. |
| Clang resource/stdlib directory selection; `ToolChain.cpp` 954–1067 | Actual resource root is `<tool-parent>/lib/clang/22`; runtime triple is `x86_64-unknown-linux5.10.0-gnu2.31.0`. Runtime/lib, stdlib and architecture candidates are under sibling `<tool-parent>/lib`. Minimal initial policy captures/refuses this entire sibling-root presence; do not assume the approved adjacent `<tool-directory>/lib` covers it. This also covers sibling include/target-library/resource candidates before they become present. |
| Default sanitizer special-case lists; `SanitizerArgs.cpp` 193–231 | Debug actions search resource `share/ubsan_ignorelist.txt`, parse a present file, and can change sanitization. Sibling-root refusal covers this branch initially. If the policy later permits that root, capture all relevant default-list files and absences explicitly, validate their content/selection and version that policy. Do not preserve current trust by merely adding a successful-read list. |
| Linux library/program path selection; `Linux.cpp` 233–378; `Gnu.cpp` 3091–3187 | Guard metadata/aliases for `/lib`, `/lib64`, `/lib/x86_64-linux-gnu`, `/usr/lib`, `/usr/lib64`, `/usr/lib32`, `/usr/libx32`, `/usr/lib/x86_64-linux-gnu`; selected GCC version/sibling-lib paths and `/usr/x86_64-linux-gnu/{lib,lib64,bin}`. These paths can affect selected options/link inputs. Capture/refuse all higher-priority candidates, even when the tested object bytes stay equal. Current Zig final linker uses bundled explicit inputs, but do not infer no driver effect from one equal object. |
| Clang system include/stdlib and non-x86 sysroot branches; `Linux.cpp` 405–463, 743 onward | Fixed approved target is x86_64 GNU, not Android/MIPS/CSKY/etc; injected `-nostdinc` excludes default system include discovery. Supported Core-generated C/LLVM/Zig actions must preserve these constraints. Unknown flags/target/action or input-selecting environment use the unproved/private path. No recursive `/usr/include` inventory is justified by current permitted actions. |
| Native loader/default runtime closure | Preserve all existing exact reviewed loader/libc/libm/libgcc_s/libpthread/cache and preload guards. They do not cover the distro/GCC/Clang inputs above and must not be removed. |

The source-derived x86_64 aliases are `x86_64-linux-gnu`,
`x86_64-unknown-linux-gnu`, `x86_64-pc-linux-gnu`, `x86_64-redhat-linux6E`,
`x86_64-redhat-linux`, `x86_64-suse-linux`, `x86_64-manbo-linux-gnu`,
`x86_64-slackware-linux`, `x86_64-unknown-linux`, `x86_64-amazon-linux`.
Include exact effective versioned target and no-vendor target strings from
the approved pinned compiler, not just the short Core target spelling.
Biarch aliases include effective i386 target/no-vendor strings,
`i586-linux-gnu`, `i686-linux-gnu`, `i686-pc-linux-gnu`,
`i386-redhat-linux6E`, `i686-redhat-linux`, `i386-redhat-linux`,
`i586-suse-linux`, `i686-montavista-linux`, and the x32 aliases
`x86_64-linux-gnux32`, `x86_64-pc-linux-gnux32`. Source selection includes
biarch target itself. These candidates belong in a versioned descriptor list;
do not derive a broader policy from whichever candidates happened to succeed.

Do not snapshot membership/mtime of invocation-owned CWD, output/cache parents
or every directory traversed by `realpath`. The native trace's Core worktree and
private probe directory metadata are owned output traversal, bound by actual
argv and producer relationships. Their normal writes would otherwise create a
false `SourceChanged` on every command. Tool/input/search alias selection is a
separate requirement: validate canonical executable/discovery resolution and
relevant symlink targets, not unrelated parent-directory contents. The `/home`
and user-home `readlink(...)=EINVAL` calls are tool canonicalization traversal.
Bind that alias selection through canonical resolution; they do not justify
membership snapshots of all `/home`.

For a present search directory, the generation guard catches membership changes
within an existing invocation. Fresh approval must also validate its reviewed
membership and child selection predicates. Otherwise a new GCC version may
produce a fresh "approved" identity with a content key that omits the changed
selection. For missing search paths, snapshot absence and the relevant nearest
existing parent/alias selection; additions/removals or retargeting must invalidate
old candidates/tickets and final publication guards. Existing logical/resolved
file records alone cannot substitute for an enumerated directory's membership.

## Output provenance and domains

Do not collect compiler outputs into the persistent tool closure. The final
trace proves exclusive creation and same-action production/rename of temporary
`/tmp/abi-note-49dac5.s` and `/tmp/start-2-93ef7e.s`; those are bundled-source
preprocessor outputs. `generated-staging-provenance.json` preserves the events.
Likewise private native-cache files require captured argv and producer/input
relationships, not just a cache or `/tmp` path-prefix exemption. Process-local
`/proc/self/*` targets must be taken from the actual traced process; entropy for
owned staging is not a mutable file-content input certificate.

Use inventory hint domain/namespace **v4** and closure approval **v3**, and include
the complete discovery descriptor/policy in both keys. Old v3 hints must never
skip the added collector through `lookupReplayCandidate`, parent lending or
strict capture. Current binary content and `Input` encoding can remain unchanged
only if their record interpretation is unchanged; document that distinction.
If membership is a new serialized record type, bump that codec too. All native
keys/receipts continue to include the resulting full tool digest. Final
generation checks must validate the extension before replay acceptance and
before every runtime/numeric/program publication.

## Required correction validation

Retain the current RED. Add focused absence-add/remove, symlink-retarget,
same-size/restored-mtime distro/resource edits, GCC version/member selection,
unsupported prefix/layout and damaged/old-hint/approval tests. Use owned roots
or test-only fixture injection; never modify host distro/toolchain/GCC files.
Production receives no trust override. Test the actual current helper against
approved executable copies and unchanged real native actions, plus candidate
replay/final guard refusal after a discovery mutation. Unknown closure must
execute through fresh private caches with `cacheable=false`. Run whole Guardian
and inherited final source gates after a reviewed implementation. No such repair
or qualification is part of this evidence package.

## Separate Wave B proof and cost work

The current full candidate-plus-final validation observation is about 65 ms,
already above Lox unchanged 7 ms. This conservative extension stays intact.
Future smaller LLVM-object, runtime-C-object, numeric-object and final-link
guards each need their own complete action proof, effective flags/inputs,
searched absences/aliases, native layout/order and actual performance gates.
Do not delete full-tool inputs because a trace did not read them. The tested
`--gcc-toolchain`, resource override, `-nostdinc`, or `--no-default-config`
controls are diagnostic only; no native flag change is proposed here.
