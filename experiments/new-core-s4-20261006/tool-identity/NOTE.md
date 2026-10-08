# Shared guest-tool identity and provisional ticket checkpoint

The coordinator owns integration of the uncommitted helpers
`src/core/tool_identity.zig`, `src/core/tool_ticket.zig` and the Core-only
`src/config_core_tool_platform.zig`. The frontend package's
frozen production source was not edited. These helpers own no driver or receipt
wiring and change no persisted frontend encoding.

The stable identity API accepts `Request{arena, io, environment, executable,
cache}`. `capture` returns `Identity{path, digest, generation, native_target,
inputs, memo_hit, cacheable}` after two generation validations. Spawn the returned
canonical absolute path. Explicit paths and PATH are resolved without old-driver
sibling or MYLANG_ZIG overrides; pinned Zig POSIX spawn searches the parent PATH
rather than a separately supplied child environment map. `unchanged` validates
tool selection, CPU and every known generation before accepting replay or
publishing results. The digest belongs in test and unit/link keys.

The identity covers the complete executable, adjacent Zig lib, ZIG_LIB_DIR
(including a relative override resolved against cwd), directory layout, absent
roots, resolved symlinks, native CPU model/features, OS/ABI and Core target flags.
It also inventories the default loader logical path, libc, libm, loader cache
and preload-file presence. The parent final validation therefore detects a
native runtime change after a child attempted provisional replay.
File content streams in 64 KiB chunks with opened-file generations checked before
and after reading. Sorted generations include inode, size, nanosecond ctime/mtime
and mode. Additions, removals and same-size writes with restored mtime invalidate
ordinary local filesystem generations.

Content memos are checksummed 117-byte binary records. A checksummed binary
inventory hint stores sorted paths and generations, bounded to 100,000 inputs
and 32 MiB. Warm refresh directly stats every known input, avoiding repeated
realpath and directory walks for ordinary paths. Directory-generation changes,
absence/kind changes and symlink-target changes force complete rediscovery.
Malformed hints and damaged memos are misses; allocation errors propagate.
Strict capture still refreshes twice and validates before returning. Atomic
publication uses unique pending filenames and rename.

The owned global namespace is `$XDG_CACHE_HOME/mylang/core-tools-v1` or
`$HOME/.cache/mylang/core-tools-v1`; the request cache is a fallback when neither
is available. Different project cache roots reuse full content hashing. S4-C
must include this owned namespace in its pruning policy. Hints are keyed by
canonical executable, native target and normalized override, while content
memos are keyed by the complete generation digest.

`cacheable` requires the exact reviewed pinned executable SHA256
`1d314883fd8cf4490c1c29dd73ad8b64e319a8a53c4d9087d1135b52977df37f`
and the exact normalized bundled library closure SHA256
`e6b4a1cd237963366bfba71c9e3b33d3b052274e4963d9a85d26fda3c9adf3f6`.
The library approval hashes sorted relative paths, kinds and streamed file
SHA256 values, so relocated complete copies may qualify. Internal library
symlinks and additional or changed content refuse approval. Static ELF metadata,
basenames and version strings do not establish dependency closure.

`static-delegate-red-01.json` retains the concrete pre-repair counterexample:
a static ELF delegated to an outside actual Zig binary. Changing the delegated
binary did not change the earlier structural helper's approved identity. The
repair accepts only reviewed content; tiny owned fake ELF/library fixtures have
an additional `builtin.is_test`-only content allowlist, never a production request
or caller trust override. Unknown executables/libraries still compile with reuse
disabled.

Default native Zig header discovery also reads `/usr/include`, as retained in
`native-header-discovery-01.log`. The coordinator changed every Core native
runtime/number/program/link compile to the reviewed bundled-libc target
`x86_64-linux-gnu.2.31`, preserving native CPU flags and the current SysV layout.
`bundled-header-discovery-01.log` proves this target's header search stays in the
reviewed Zig distribution. The helper requires that exact compile policy and
hashes it in native target domain `core-native-cpu-v2`. S4-C must preserve these
compile and link flags.

Native execution still uses the system ELF loader, libc and libm. The config
contains their exact reviewed SHA256 values and resolved paths, plus the exact
reviewed `/etc/ld.so.cache` SHA256. `runtime-reviewed-platform-01.json`, the
three `runtime-reviewed-*.log` readelf receipts and
`runtime-reviewed-lookup-01.json` prove the captured default closure: loader
requires no additional shared object, libc requires that loader, and libm requires
that libc and loader. There is no RPATH/RUNPATH. The exact reviewed loader cache
selects the captured `/usr/lib/x86_64-linux-gnu` files. Missing files, changed
content/aliases, unfamiliar loader-cache bytes or a nonempty preload file disable
reuse. This is a bounded reviewed platform, not a generic ELF/cache parser.

Nonempty native/header/tool environment overrides and LD_/DYLD_ variables
refuse reuse, including CPATH, C_INCLUDE_PATH, LIBRARY_PATH, SDKROOT, ZIG_LIBC,
CCC_OVERRIDE_OPTIONS and GLIBC_TUNABLES. Environment value hashing alone cannot
prove mutable paths. Primary documentation confirms [Clang include environment
paths](https://clang.llvm.org/docs/CommandGuide/clang.html) and [CCC argv
rewriting](https://clang.llvm.org/docs/UsersManual.html#ccc-override-options).
The ordinary known default environment remains eligible.

Content memo encoding stays v1: its generation key remains an opaque 32-byte
digest. The expected inventory expanded, so its hint magic/key domain and
generation domain are v2. This rejects pre-runtime hints that omit the new files.
A separate checksummed `approval-v2` memo is keyed by the complete generation,
reviewed executable/library/runtime approvals and test/production namespace;
unknown or damaged approval records miss. Approval misses stream reviewed
content and validate generations again before publication. Warm approval hits
perform no tool subprocess and avoid rehashing the large executable/library.

`captureReplayParent` permits one generation refresh on a proven memo hit only
for provisional read-only directory replay. Its miss/unproved path retains the
strict two-scan guards. The parent must call `unchanged` after all children and
reject aggregate success on mismatch/error. No borrowed identity may publish a
result; on replay miss the child discards it and takes a full local capture.

`lookupReplayCandidate` reads only a checksummed hint and matching content memo,
checking canonical executable/CPU selection, executable generation, safe
environment and the matching reviewed-closure approval memo without scanning
library generations. It may be used only
for buffered read-only manifest replay. Before accepting cached success, a full
`unchanged` scan must pass and manifest dependency bytes must be validated again.
Any miss/mismatch discards it and uses strict capture. It never publishes a memo,
hint, test result or native object.

`tool_ticket.Request{tool, compiler_identity, input=.stdin()}` exposes
`encode(Request, Identity)` and `borrow(Request)`. The internal marker is
`tool_ticket.hint` (MYL_CORE_PARENT_TOOL_TICKET), excluded from receipt environment
hashing and removed from native guest environments. A checksummed envelope is
limited to 16 KiB and binds the actual parent PID, compiler identity, canonical
tool executable generation and native CPU. Before reading private stdin, the
child verifies getppid and matching /proc parent/self executable device, inode,
size, mode and timestamps; it checks provenance again after reading. Missing,
invalid or foreign tickets fall back to strict capture. Library validation stays
with the parent before accepting the provisional aggregate.

`runtime-focused-03.log` passes all 20 focused tests. They cover ticket
provenance/corruption/binding, path resolution and allocation failure, memo and
hint corruption, restored-mtime edits, library additions/removals/overrides and
symlinks, candidate final refusal, unknown static delegates/library contents,
approval memo corruption, uncaptured environment overrides, missing/unknown
runtime content and stale runtime generations. Task-owned runtime fixtures
prove restored-mtime library edits, preload-file creation and loader alias
retargeting invalidate the same final generation refresh used by directory
parents. `runtime-fmt-03.log` is green. Final whole Guardian88 is green in `runtime-guardian-05.log` after the
coordinator registered the actual named config-module entry in orphan-files roots;
no check was disabled. Guardian03's only failure was that missing module root.
Guardian04 completed green before an unadmitted-waiter cancellation inspection,
so no process was canceled; its NOT_RUNNING inspection receipt remains.
Earlier failures and probes
remain retained, including Guardian's correct hardcoded-platform-path refusal
before config extraction. Full M package integration gates belong to the
coordinator.

Focused recipe:

```sh
scripts/build-slot.sh build -- zig test --dep core_tool_platform \
  -Mroot=src/core/tool_ticket.zig \
  -Mcore_tool_platform=src/config_core_tool_platform.zig \
  --cache-dir .mylang-cache/s4-m/tool-ticket-runtime-03
```

The temporary ReleaseFast probe records binary hashes and exact JSON identities.
All probes used CPU 10 under the shared timing lock while other builds remained
active, so these measure overhead rather than uncontended package gates.

| Probe | Cold capture | Warm strict capture | Parent capture + final validation |
| --- | ---: | ---: | ---: |
| 01, repeated full walk/realpath | 1.42737 s | 0.27851–0.29530 s | not measured |
| 02, binary metadata hint/global memo | 0.65381 s | 0.09659–0.10339 s | not measured |
| 03, provisional parent API | not measured | 0.07821 s | 0.08650–0.08875 s |
| 04, candidate API plus required final scan | not measured | not measured | 0.08172–0.08589 s |
| 05, approved content plus default runtime closure | 0.91533 s | not measured | 0.08459–0.14416 s |

Prior probes of pinned Zig produced 20,900 inventoried inputs and identical
content/generation digests in their warm runs. Current probe05 inventories
20,905 inputs including the five default runtime paths, and its approved
production identity is stable in every warm run. The retained static-delegate
production probe now returns cacheable=false; the actual reviewed pinned
executable/library/runtime returns cacheable=true. Probe 02 reused the content memo from a
different project cache; probe 03's parent-plus-final median is 0.086667 s.
No tool subprocess runs on memo hits. Warm overhead remains material against
Lox's 0.1451 s combined old directory/explicit-driver baseline; the coordinator
will measure actual port commands. Probe 04 counterbalances three candidate and
three parent runs. Candidate lookup plus its required final full generation scan
takes 0.073447 / 0.061856 / 0.061031 s (median 0.061856 s); parent capture plus
final validation has median 0.083414 s. These numbers exclude manifest replay
and checking. Candidate overhead alone exceeds the old explicit driver command's
0.0342 s baseline, so this checkpoint does not establish warm command parity.
Current probe05 counterbalances three candidate/parent pairs. Candidate plus
its required final scan has median 0.064670 s; parent capture plus final scan
has median 0.121957 s (samples 0.144157/0.121957/0.084595 s). Other build slots
were active, so the dispersion and all samples remain retained rather than
selecting the fastest trial. No warm command parity is claimed. Strict
standalone file replay pays capture and a final generation validation; candidate
replay reduces the library scans to one before success.

Generation validation assumes faithful ordinary local filesystem metadata; an
unverifiable filesystem requires content hashing or bypass. No all46, full old
gate, or package qualification is claimed for this helper checkpoint. Source
hashes frozen for coordinator build: identity
`cafbb2bd8493045084f4bc26ece2523412dc6b9633f3393b6c49115235482a98`, ticket
`5e529827b943e53e1c25db3a7adea6d570bd49c2e9504ce5e3ce03b27aa2094d`, config
`5efaeb5e342bcaf704e5b0c7334b21a359716be94989851f0106848f7462cda2`.

Required append-only Guardian feedback was committed in guardian-zig as
`9fe3b5106632185148173b6c975561f655825e81`; its normal whole-tree commit gate
also passed 88 checks. No mylang main merge or push occurred.


## Backtrace runtime closure correction, 2026-10-07

The pre-extension checkpoint above and M source checkpoint `7bc4a745f` are
historical. `core_rt.c` calls glibc `backtrace`, which loads `libgcc_s.so.1`
dynamically. The retained bundled-target C probe ran before source edits:
`backtrace-runtime-{build,load,closure}-01.log` proves the load via the reviewed
loader cache. Its O3 counterpart is probe02. The C O0/debug path also loads
`libpthread.so.0`; `backtrace-pthread-closure-01.log` reviews that bounded input.
Both libraries have no RPATH/RUNPATH. Libgcc needs only libc and the loader;
libpthread needs only libc. Those dependencies were already captured.

Actual installed M Core `67ad628f8743dd803c81bbd071f5c3e7816ff2977ad44bb10c52bb4e36672906`
built Debug and Release guests through the current driver, including the Zig
numeric object. Each prints `1.25`, then a division-by-zero trap exercises the
runtime's actual stack unwinding. Both load libc and libgcc, with no additional
shared dependency. `backtrace-core-summary-03.json` and the mode-specific
exec/build/closure/load logs retain all flags, binary hashes and load traces.
Earlier failed fixture probes remain: probe01 used an invalid module filename,
and probe02 claimed an unused Host capability; neither is qualifying evidence.
The numeric helper is present in both emitted LLVM files and executed before
the trap. No system files were changed. `LD_DEBUG=libs` was used only on the
probe child, with other loader overrides removed.

The bounded reviewed platform now additionally captures:

- `/lib/x86_64-linux-gnu/libgcc_s.so.1`, resolved to
  `/usr/lib/x86_64-linux-gnu/libgcc_s.so.1`, SHA256
  `9d339ecb409578d6a5d587e6c537a8f9589b8a13fefba30d167433a4b5758bee`.
- `/lib/x86_64-linux-gnu/libpthread.so.0`, resolved to
  `/usr/lib/x86_64-linux-gnu/libpthread.so.0`, SHA256
  `1327fc40710691dbd94e88b6cf4efce27fefe8fbb93f7d1164a75b4dccaea696`.

Inventory-hint domain/header moves from v2 to v3, and its key now hashes every
runtime descriptor (logical path, resolved path, reviewed SHA256) and preload
path. Old hints cannot omit a newly approved runtime input; the existing
corruption test now also rejects a checksummed v2 hint. The binary inventory
payload codec is unchanged. The content memo remains v1 with unchanged opaque
digest interpretation; approval-v2 already included all runtime descriptors,
so its format/domain requires no change. Full generation validation and final
parent validation cover the added paths through the existing inventory logic.
Unreviewed tool/library/runtime closures still bypass persistent reuse.

Fresh `backtrace-runtime-focused-01.log` is green 20/20, formatter01 is green,
and `backtrace-runtime-guardian-01.log` is green 88/88. The existing runtime
inventory test asserts every configured descriptor is present, covering both
additions. Production probe09 inventories 20,907 inputs, returns cacheable=true,
and its strict capture and provisional candidate plus final validation agree:
content digest `0857a59f7471a35d17e3bf28c19979a79e3ae9bc712cc6c4be87930a1e1c3cc2`,
generation `788ee0a448dead0e7bec2bd00e061aa27055b27b49e65ae63efd3ac2a33df363`.
This is a correctness probe without an uncontended performance claim. Exact
source hashes in `backtrace-runtime-receipt-01.json`: identity
`e3f8f09bae559a843391b24f8c79aa9676adccd0511b78c11d2629b4bf20f8a7`, ticket
`5e529827b943e53e1c25db3a7adea6d570bd49c2e9504ce5e3ce03b27aa2094d`, config
`b9468ccefd4037fca68a2bb4ff53354e0da2006b1110860d66afa4cbc9f0d8c5`.
These helpers are frozen for the coordinator's fresh compiler build and full
M package gates; those gates are not claimed by this helper receipt.

Append-only Guardian feedback for this closure correction was committed in
`guardian-zig` as `96ff1611b3446fcdeedc1a9210c2b9ac3da5babc`; its commit gate
also passed all 88 checks. No mylang main merge or push occurred.
