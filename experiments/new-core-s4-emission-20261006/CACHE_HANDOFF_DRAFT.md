# Read-only S4-C handoff preparation

This is preparation for the cache package. No S4-C source is implemented here;
S4-E must qualify and merge before C starts.

E supplies ordered `emit_units.Unit` inputs with stable name, kind, source path,
LLVM bytes and number/math requirements. Program calls use hidden fastcc; the
runtime ABI changes only site indexes to pointers. The driver must retain the
union of every unit's formatter and math dependencies, plus ordered user links.
`--emit-llvm` still writes the inspection whole module. Its output is independent
of the native unit cache.

M's shared `tool_identity.zig` supplies the resolved canonical tool path, a full
content digest, generation digest, native CPU/features identity, and cacheability.
Its identity covers the static Zig executable, complete adjacent/override lib
tree, and native target flags. `unchanged` rechecks selection, CPU and input file
generations. Scripts, dynamic tools and unproved dependency closures have
`cacheable=false`. Parent replay candidates are read-only hints: a miss must
capture a local full identity before compilation or publication.

C must combine complete tool identity, target/CPU/features/options, runtime ABI,
emitter/cache format versions and LLVM content in every object key. Resolved
library/default link inputs and all external source/header/object dependencies
also enter link identities. M conservatively disables receipt replay for explicit
external links; C must keep bypassing reuse until those transitive inputs are
proved. Native/sysroot/libc and environment overrides need explicit dependency
proof or cache bypass. The memo namespace is `XDG_CACHE_HOME/mylang/core-tools-v1`
(fallback `HOME/.cache`); pruning must account for it.

Keep deterministic LLVM input basenames and explicit source/debug metadata, so
`--verify-cache` recompilation can compare object bytes independently of worker
scheduling and owned output temporary names. Every publisher owns its random
temporary and performs atomic publication; no fixed `.partial` is shared. M is
reducing the tool-mutation race in which a runtime/numeric object was published
before the final generation check rejected the build. Its additive guarded
publication change must be preserved. Unit publication also needs generation
validation before rename, or all writes must remain staged until validation.

Required independent probes:

- Trace executable calls: unchanged unit/link/runtime hits start no Zig process;
  changed body compiles exactly the changed owner and genuine imported callers.
- Change target features, optimization, tool bytes/lib files, runtime sources,
  emitter version, ordered links and included headers: reuse is rejected.
- Pause a real tool during compilation, mutate a task-owned tool/lib input, then
  release it: command rejects the change and publishes no old-key artifact.
- Simultaneous cold publishers, interrupted builds and failures leave either
  verified complete objects or no published objects, with owned partial cleanup.
- Recompile every cache hit for `--verify-cache`, compare actual object bytes,
  and execute the linked program with leaks and fact verification.
- Unsafe/unproved tool or external dependency configurations build correctly
  while bypassing persistent object/link/runtime reuse.

For S4-X retain a per-unit report with `name`, `kind`, `source_path`, `llvm_path`,
`object_path`, `key`, `cache_hit`, `compile_argv`, and `compile_seconds`, plus link
hit and phase timings. Retain the changed LLVM files until measurement finishes.
The harness independently traces argv and replays the identified changed unit's
`-O3 -c` command on CPU 10 with a fresh Zig cache. Multiple changed units without
an unambiguous edited-source mapping cannot qualify the release-edit formula.
