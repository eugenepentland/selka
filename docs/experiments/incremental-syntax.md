# Bounded incremental module syntax

The embedding compiler now exposes `syntax_cache.Cache` and
`interfaces.buildWithCache(project, &cache)`. Keep a cache across successive projects
to reuse parsed module bodies when their source path, complete bytes, and body start
match exactly. The existing `interfaces.build` remains the uncached path.

```zig
var cache = language.syntax_cache.Cache.init(allocator, .{
    .max_entries = 64,
    .max_bytes = 16 * 1024 * 1024,
});
defer cache.deinit();
// Load a fresh Project for each source snapshot, then:
var index = try language.interfaces.buildWithCache(&project, &cache);
var compilation = try language.project_compile.Compilation.init(&index);
try compilation.check();
```

Each retained entry owns its source and syntax arena. Hits deep-copy all syntax
slices into the current project's arena, preserving local spans and node identities.
Clearing, eviction, and cache destruction cannot invalidate returned syntax. The
shared AST copier also performs the existing checked module-source relocation;
its allocator is supplied per operation instead of implying ownership in a mapper.

This caches parsing, not a semantic verdict. Fresh project loading still reads and
lexes sources for module headers/import graphs. A hit skips the interface phase's
second lexer pass and body parser. Symbols, exports, name resolution, signature
visibility, source relocation, ownership/effects, and all bodies are checked again.
Changing a dependency's signature or privacy therefore still rejects incompatible
unchanged callers, including on subsequent all-hit parses. Invalid syntax is never
retained; successfully parsed syntax may be reused even when semantic checking fails,
because those semantic checks always run again.

Exact byte equality is required; no hash collision can create a false hit. Old source
versions may remain reusable until deterministic oldest-insertion eviction. Default
retention is 256 entries and 16 MiB of entry arena capacity. Entries exceeding the
byte budget are bypassed; zero entries disables retention. The byte limit measures
retained arena capacity, including source/syntax allocations, but excludes the bounded
entry index and transient construction/caller copy storage. It is not a whole-process
memory limit. Allocation failures propagate and cleanup is tested. Access is serialized
by the caller; the cache has no internal locks or persistent disk representation.

`statistics` reports successful hits, misses, retained insertions, evictions, bypasses,
and current retained arena bytes. A hit is actual syntax reuse, not evidence that
semantic work or source I/O was skipped. No speedup claim is made: deep-copying syntax
still costs work, and header lexing and semantic passes remain uncached.

`syntax_cache_test.zig` checks warm hits, a dependency body edit, returned results,
cache clearing before use, every allocation failure, deterministic eviction, source
and expanded-AST byte-budget bypass, fresh signature/privacy errors on warm caches,
failed-parse recovery, and provider bounds. Existing source relocation and full
compiler suites exercise the shared copier. Ordinary CLI invocations use independent uncached projects; embedding hosts opt
in explicitly, and [check-session](check-session.md) retains a cache across CLI
requests while reloading source and input manifests.

This is the first frontend query-reuse component. Since these measurements,
persistent syntax storage and semantic query/dependency caching have landed through
the frontend and `semantic-cache-v2` stores: one-shot commands reuse checked
ordinary bodies, symbolic templates and validated concrete specializations, and
native-test selection adds receipt and reduced-graph reuse. Automatic watch
integration was dropped with the Python watch driver; finer invalidation reports,
per-function lazy lowering and native incremental linking remain open. The
embedding cache described here still covers parsing only. It does not complete the
F roadmap track.
