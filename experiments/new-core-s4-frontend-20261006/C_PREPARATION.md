# S4-C preparation: reviewed units and closed tool inputs

Read-only preparation, 2026-10-07. Implementation stays held until all Wave A
packages qualify and integrate. This checklist uses E
`702ede7f1c459845529d3bae03e9ed98b5514c35` sparse inline provenance/Analysis
and Unit{name,source_path,kind,llvm,number,math}, plus M
`b8d007bdc884caf1959fed09c01e529f4174d382` tool helpers, publication guards
and private native-cache correction.
No compiler source was edited for this preparation.

1. **Reconcile the driver first.** Preserve M's absolute resolved tool, strict
   identity capture, x86_64-linux-gnu.2.31 target, native CPU flags, private
   unproved-tool work and Guard.check before runtime/number publication and after
   linking. Preserve E's unit order, ABI, provenance-bearing LLVM and dependency
   flags. Unknown executable/library/runtime/env closures bypass persistent unit
   and executable reuse. Provisional replay helpers authorize read-only replay;
   a miss must return to strict capture before compilation/publication.

2. **Frame every object-key input.** BLAKE3 namespace/version, exact emitted LLVM
   bytes, guest optimization mode, all semantic ordered compiler flags, resolved
   native CPU/model/features and explicit target, tool content identity, Zig
   version, runtime ABI and emitter version. Runtime includes complete source and
   O2/C11/CPU flags; number includes all copied Zig sources and its exact options.
   M's tool digest covers reviewed executable, selected libraries and runtime;
   version strings/basenames alone prove nothing. Unit names, IR/frame IDs and
   private staging paths are not substitute identities. Keep compile/link key
   inputs separate. Use full 256-bit keys and version new persisted records.

3. **Validate and repair every served object.** A bounded checksummed record
   binds key, byte length/digest and faithful file generation (inode, ctime,
   mtime, size, kind/mode). Reject missing/truncated/unreadable/symlinked/malformed
   entries. A changed stamp requires guarded content hashing; restored mtime
   must not hide corruption. Recompile a bad entry, never link it. Retain object
   generations through link so replacement after lookup fails final validation.
   Include damaged object/record, mtime-restored edit and replacement regressions.

4. **Publish only completed, validated work.** Invocation-owned random staging,
   immutable source text, success status and expected nonempty object, then tool
   Guard before each object rename; checksummed metadata must refer to those
   bytes. Mixed old/new object/metadata during concurrent publication is a miss.
   Per-key synchronization/dedup prevents conflicting writers. Revalidate tool,
   object and external input snapshots before accepting or atomically installing
   the final executable. Test a real tool/lib mutation during compilation and
   assert no object/receipt is published under the earlier identity. Kill/reap
   failed or timed-out workers and clean only their own staging.

5. **Make byte verification real.** --verify-cache recompiles every unit served
   as a hit through fresh native caches, then compares complete object bytes;
   corruption repair remains a separate action. Keep source_filename and source
   DWARF paths unchanged. Keep physical input basenames canonical; prove complete byte stability
   across private directories in both modes. The actual E Debug unit proof below
   needs no extra directory flag. If another actual unit differs, retain its RED
   before testing a generic stable debug-compilation-directory flag.
   Do not strip debug data or normalize away differences to pass verification.
   Preserve exact multi-module trap/error ancestry and generic identities.

6. **Batch and parallelize actual misses.** Dedup equal keys, group compatible
   tiny LLVM units by bounded bytes/argument count, compile larger units alone,
   honor MYLANG_JOBS/available affinity, and gather outputs by canonical key.
   Multi-input -c cannot use one -o: give each input a unique stable basename and
   execute in an invocation-owned directory. Workers use private arenas/logs;
   merge reports in unit order. No worker may link before all required objects
   qualify. Retain actual batch argv/id/wall time; don't invent per-unit times.

7. **Reuse the complete executable.** Unit hits alone still leave a zig cc link,
   violating the unchanged-build gate. A separate link key covers ordered object
   keys/content, runtime and numeric object identities, -lm union, exact linker
   flags/target/tool and entry contents. A valid executable hit installs/copies
   the checked bytes without Zig. External --link inputs need their entire
   include/link closure and generation guards; conservatively bypass executable
   reuse when that closure is unproved. Do not claim direct C source hashing
   covers its headers. Test output removal/new output path and concurrent builds.

8. **Union dependencies from every unit.** Cached module/generic/helper/entry
   units still contribute unit.number and unit.math. Link runtime once, numeric
   object when any unit requires it, -lm when any unit requires it, and each
   unique object once in deterministic order. Do not infer requirements only
   from newly compiled units or the entry. Existing float-renderer helper and
   cross-unit aggregate/trap fixtures are direct regression inputs.

9. **Prune only owned regenerable caches.** New unit/link stores under
   .mylang-cache/core need explicit eviction coverage; global helper content
   memo is only the owned core-tools-v1 namespace. Preserve dry-run, active
   worktree/quiet-period/keep protections, logs/sources and pinned oracles.
   Rename whole cache aside before removal; never follow cache symlinks into
   external trees. Concurrent removal must become a miss/refusal, never partial
   trusted state. The existing cap targets only .zig-cache, so inspect whether
   active Core/global stores need their own bound. Prune script changes require
   the full old gate, with the old/fuzz qualification lock sequencing unchanged.

10. **Report and measure the exact artifacts.** MYL_CORE_BUILD_REPORT=1 should
    map source_path to llvm_path/object_path/key/hit, plus actual compile/link
    argv, batch membership and phase wall times. Keep LLVM inputs through
    comparator replay. The current devloop tool needs a post-C tool-only fix:
    a traced multi-input batch has no -o and must not become the singular edited
    unit comparator. Reconstruct standalone -O3 -c for only that unit with the
    same flags and fresh local/global Zig caches; report batch time separately.
    Use matched ReleaseFast compiler hosts with build-mode/commit/SHA receipts,
    fresh role/mode caches, and previously unseen one-function edits. CPU10 with
    its shared lock measures ordinary single-worker builds; reserved build CPUs
    measure 192k cold release at 16 workers separately. Trace successful Zig cc
    starts independently: unchanged must be zero, including the linker. Execute
    every cold/warm/edit/trace/parallel output against the old oracle. Required
    bars remain 48k debug edit <=2s, release <=1.5*one-unit-O3+1s, 192k/16 cold
    <=60s and the frontend's 96k edited check <=0.45s. Smokes cannot qualify.

After source freeze run all inherited gates: test-core, both conformance modes
with leak/fact verification, 50 strict cases per relevant kind, all46 with both
relative limits, uncontended real Core rebuild <=10s, and full old when outside
src/core changes. Include actual cache-hit traces, one-module edit/inlining
ripple, concurrent/corrupt-cache repair and --verify-cache over a multi-module
fixture; S4-X additionally verifies Lox and the EDA slice.


Retained filename proof: `c-prep-filename-01/summary.json` is RED in both
O0/O3 when identical actual Core LLVM inputs have different physical basenames.
`section-differences.json` isolates the mismatch to .symtab/.strtab filename
strings; LLVM/source DWARF text was unchanged. `c-prep-filename-02/summary.json`
is GREEN in both modes with the same canonical input basename in distinct
private directories and distinct fresh local/global native caches. Full object
bytes match, without stripping or normalization: Debug SHA256
`ed7ed99cd123585a50d0b1535f38c2cca0071b0fc8a6dedecca87195098d8ffd`, Release
`f6ed037660019fad2f566b2f18d7aeb5c5cb10bfc88a5b5ecdd061ebf78e1d93`.
These isolated native correctness probes use build slots and change no compiler
source; they do not qualify C or its eventual split-unit batch layout. The
implemented cache must test its own canonical basenames and batch working
paths. Apply validation/repair and final-input guards to runtime/number objects
and cached executables as well as emitted unit objects; M's publication guards
prove tool generations, while its current access-only runtime/number hits do
not establish object-byte integrity.


Full tool-generation scans are an unresolved C/P performance risk. The retained
observational CPU10 helper probe05 measured candidate+required final validation
about 0.065s and parent+final about 0.122s. Other build slots were active, so
these are not uncontended qualifications. They already exceed the P old warm
unchanged-build bars of Lox 0.0068s and EDA 0.0165s by several times. Sharing one
capture among directory children avoids repeated scans, but does not establish
the fast unchanged-build gate. Do not weaken generation checks or assume an
approved static compiler can consume no other inputs.

A sound optimization requires an explicit, versioned proof of the dependencies
actually consumed by each approved native action: LLVM object compilation,
fixed runtime C, numeric Zig object, and linking. A compiler dependency manifest
or observed trace alone is insufficient if it omits failed lookups, dynamic
searches, selected target resources or compiler behavior. Review the pinned
compiler and exact flags, capture the complete successful inputs and relevant
absence/search-directory generations, and guard symlinks plus canonical tool
and ZIG_LIB_DIR selection. Cold content identities may then be retained under a
complete generation inventory for that proved action; warm reuse still stats
every proved input with ctime and validates lookup locations. Preserve the
small loader/libc/libm/libgcc/pthread/cache/preload closure. Unknown actions,
custom tools, altered lib roots or external includes/link inputs must fall back
to the full strict path before compilation or publication. This needs a new
artifact-closure proof/API rather than relabeling the current full-tree Identity
while dropping inputs. An actually immutable content-addressed toolchain could
prove stronger reuse, but ordinary permissions, directory mtime or an approved
executable hash alone cannot. Do not change system state to manufacture proof.

The actual C/P cold/warm phase profile on matched ReleaseFast hosts and fresh
artifacts must decide the implementation. Preserve the full scan's current
inputs, resolve its discovered closure gap before qualification, and report a
timing miss until a proved improvement passes.

Foreign-header counterexample: c-prep-foreign-header-01 retains successful
approved Zig argv/artifacts before and after a same-size VALUE7->VALUE8 header
edit with restored mtime. Both native compiles returned zero, but both guests
returned7 and had the same executable SHA256. ctime and content digest changed.
retained-artifacts.json additionally preserves the exact canonical compiler SHA,
current device/inode/ctime/mtime/size/mode/hash for the C source/header/executable,
and a new raw execution's stdout/stderr/status without overwriting historical
receipts. This original probe is a bare Zig native-cache counterexample.
Unproved external-source executable reuse already bypasses M test
receipts; C must also establish fresh private native caches or a complete native
cache dependency proof for uncaptured C headers. External source hashing alone
will not repair the compiler's stale native cache result.

The follow-up c-prep-core-foreign-header-01 reproduces the defect through the
current immutable M Core --link path (compiler SHA 591886dc7d20409c878ee0a5b15c9faa0394b5b836eeaaa8c75e43a31350f120,
source 0ebc9c8f0). Both identical builds succeed; after the same-size/restored-mtime
header edit, guest exit remains 7 instead of 8. The exact native cc/link argv,
raw native/build streams, header generations, identical whole executable/LLVM
bytes, and stale cached value.o are retained. This is a Wave A native correctness
defect requiring a correction before qualification; no repair or cache policy
relaxation is part of the preparation evidence.

The authorized M-only driver correction was subsequently reduced/verified:
fresh local-only and local+global controls both produce the correct 8, and the
fresh corrected Core (SHA d6e4220ad8a833f3d56510eb5958637e25f9c367071949db281d64584d3bface)
produces 8 against the preserved stale cache. M now scopes private local+global
native caches to final actions with external links or unproved tools; original
Guard environments and closed runtime/numeric keys remain. Two meaningful
focused tests (actual Debug/Release header edit and unknown-shim mutable-input /
failure cleanup) passed; Guardian passed 88. C must preserve this behavior until
it proves a complete replacement foreign-source/header closure. Source hashing
plus the existing native cache alone still fails the retained RED.

For C integration, keep foreign inputs out of whole-executable reuse until their
complete source/header/search/absence/link closure is proved. A closed emitted
LLVM unit may still reuse its independently keyed object with an approved tool:
it is compiled separately from foreign C and its object contains the declared
foreign ABI, not the foreign implementation. The final external-link action
must preserve M's fresh local+global native caches; do not silently route it
through a shared miss-worker cache. Unproved tools bypass persistent unit,
runtime/numeric and executable reuse. Preserve original captured environments
for all generation guards, clone a separate environment for private native
actions, and clean only invocation-owned directories on success and failure.
Keep link dependency unions from every cached or fresh unit. Any future complete
foreign closure replacement must invalidate old object/executable namespaces
and retain the actual restored-mtime RED/control/GREEN regression.

Actual E debug cwd proof: c-prep-e-debug-cwd-01 copies immutable E5994 LLVM
unit SHA 1c40b584bc71793ebd6e8a1d597b03c65677dd33857bed2370293efed1363e48
with DIFile.directory="" into different private working directories using the
same canonical basename and fresh local+global native caches. Preserved original
native flags produce identical full 3184-byte Debug objects, SHA
d8dd5741be1e8c641748d89dec8810ff602a9203e1b8afeaf4006e4cfe7a0b37.
DWARF has no DW_AT_comp_dir, and no additional stable-directory flag is needed
for this actual unit. Keep per-unit full-byte verification; this evidence does
not prove stability of native C/Zig source objects. The probe serialized against
CPU10 timing and is correctness evidence only.

## Actual LLVM-only filesystem and link grouping preparation

The prospective target 2.31 object action is traced in
`c-prep-action-closure-01/README.md`, including successful reads, failed
lookups, searched directories, symlinks and comparison with the 20,907-input
current inventory. Explicit config/header controls preserve all object bytes
but do not stop system GCC/distro discovery. An owned empty GCC toolchain
removes GCC enumeration; both distro content reads remain outside the
inventory. `-MD` writes no LLVM depfile and changes the full object bytes by
selecting a direct-Clang path. These are observations and source-review
requirements, not a reduced closure proof or a production flag decision.

Root's retained E prebuilt-object replacement changes native C main layout
(0x1032940→0x1008ac0) at the same high-level argv position. Pinned Zig ELF
linker source appends explicit link objects before generated C/LLVM objects.
C must capture the actual child linker input order and kind groups, bind that
policy in executable keys, inspect complete ELF layout and repeat all app/row
gates for its all-object link path. Printed driver argv order alone is
insufficient. Source excerpts and unresolved closure requirements are retained
with the action probe; no compiler implementation changed.

## Full helper discovery gap and conservative correction

`c-prep-full-closure-audit-01/GUARD_CORRECTION_PROPOSAL.md` preserves a real
unchanged-helper RED: an approved actual Zig copy plus its approved adjacent
library remains cacheable, unchanged and equal-keyed after a sibling Clang
resource appears; the next fresh native compilation reads that file. Equal
object bytes do not prove complete identity or absence of driver/link effects.
Actual protected corrected M runtime-C and final compile/link descendants read
the same unguarded distro files and perform GCC/resource selection outside the
current full inventory. Bundled header lookups have direct file or directory
membership guards. CWD/output/cache traversal is distinguished from discovery;
our own output writes must not invalidate the tool generation.

The proposed correction keeps every current input and native flag, captures a
bounded reviewed distro/GCC/alias/absence selection state, and conservatively
refuses unreviewed sibling resource roots, Gentoo/RHEL prefixes or new layouts.
Inventory hint v4 and approval policy v3 must invalidate old fast hints. Primary
official Clang tag sources explain the discovery branches, but their exact
build relation to the pinned binary remains unestablished; fixed-layout refusal
preserves that limitation. Final M/cache qualification is held for a reviewed
repair and fresh source gates. This preparation contains no helper correction.

Wave B action-cost optimization is separate. The conservative full scan stays
intact; LLVM-object, runtime-C-object, numeric-object and final-link certificates
must each prove their complete inputs/searches/aliases before reducing work.
The observational full candidate+final cost around65ms already exceeds Lox's
7ms unchanged-build bar. No trace, directory-mtime shortcut, approved-executable
hash alone, equal object bytes or matching high-level link argv qualifies that
performance or correctness gate.
