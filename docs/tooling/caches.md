# Compiler caches

Native builds also keep an on-disk cache; see
[the native build cache](#native-build-cache) below. This document covers the
in-process caches and the [persistent frontend cache](#persistent-frontend-cache)
that ordinary one-shot commands use across processes.

The compiler keeps three bounded in-process caches: parsed module syntax, a
whole-program checking verdict, and checked function bodies. `mylang check-session`
keeps them across requests so an editor or an agent can check the same project
repeatedly in one process. Every reply is one `check-session-v1` JSON line whose
`reuse`, `cache`, `semantic` and `functions` fields report what was actually
reused. The design records are
[bounded incremental module syntax](../experiments/incremental-syntax.md),
[persistent CLI checking sessions](../experiments/check-session.md) and
[larger-project incremental checking](../experiments/large-project-checking.md).

## Persistent frontend cache

Ordinary one-shot `mylang check`, `mylang run`, `mylang build` and `mylang test`
also reuse work across processes through a content-addressed on-disk cache. It is
deliberately narrow: it can skip lexing and parsing, and it can replay a whole
program's already-successful warnings; it never stores a checked program, a symbol
index, an interface or a resolved declaration.

The cache root is `<cache-dir>/frontend/` when `--cache-dir` is given, otherwise
`MYLANG_FRONTEND_CACHE`, otherwise the per-project `.mylang-cache/frontend`.
`mylang build` and `mylang test` pass their own cache directory through to the
frontend, so frontend entries sit under the same root as the native object cache.
`--no-cache` disables frontend reuse for `check`, `run`, `build` and the project
commands; a native `build` still uses its separate object cache. Within the root,
entries are partitioned by the compiler's
build-time identity (a digest of every file under `src`, the Zig toolchain and the
optimize mode), so a rebuilt compiler can never read an older build's entries.

The cache has two independent layers, and both are always keyed by the compiler
identity, a format version and the six-dimension cache contract: compiler build
identity, bootstrap-language version, target, runtime ABI, effects/capabilities
contract and invoking flags. The contract fingerprint is mixed into every syntax,
verdict, checked-body, specialization and native-object key, so changing any
dimension invalidates an entry even when the source bytes are identical. The
on-disk format is `mylang-frontend-cache-v3`; the runtime ABI dimension is
`runtime-abi-v0-unfrozen` until Wave 4 freezes `runtime-abi-v1`. See
[the incremental contract](../experiments/incremental-contract.md#cache-key-contract).

| layer | stored | key also includes | skipped on a hit | still runs fresh |
| --- | --- | --- | --- | --- |
| parsed syntax | one parsed module body | exact source path, exact source bytes, module body start | the lexer and parser for that module only | every declaration, symbol, export, visibility, ownership, effect and typed-body check |
| project verdict | the rendered warning text of one successful `check-project` | every loaded module's name, exact path and exact bytes, plus the diagnostic format | declaration/interface resolution and the entire semantic check | loading every module from disk and recomputing the key |

Single-file commands (`check`, `run`, `emit-qbe`) key syntax with body start `0`;
project commands key it with the module header's body start, so the two shapes
never alias. A syntax hit returns independently owned AST storage: the two
growable `Program` lists are persisted as exact-length owned slices, so a restored
list owns exactly its items and never advertises capacity it did not allocate.

### Limits and fallbacks

- **Nothing typed is persisted.** Checked `typed.Program` bodies, the semantic
  function cache, symbol indexes, interfaces and resolved declarations are never
  written. A re-invocation after any edit re-checks every function body; only the
  in-process `check-session` reuses checked bodies. The persistent cache therefore
  cannot mask a changed declaration, visibility, ownership or effect bound, and it
  does not reproduce the `functions` counters of a session.
- **Failed checks are never stored.** A verdict entry is written only after a
  complete, error-free `check-project`; a type, privacy, import or deleted-file
  error can never inherit an earlier success. The verdict key covers all loaded
  bytes, so a changed file, module name, import graph or generated input misses.
- **Damaged entries degrade to a miss.** Every entry repeats its key, payload
  length and an XxHash checksum in its header. A truncated, foreign, resized or
  bit-flipped entry is rejected (`damaged` in the receipt) and the caller parses
  or checks fresh; no partial result is ever used. Stores stage to a unique
  `.tmp` file and rename atomically, and concurrent trims can only cost a miss.
- **Bounded retention.** One identity namespace holds at most 128 MiB of entry
  files; an entry larger than that is bypassed rather than stored, and the
  directory is trimmed oldest-mtime-first after a successful store. `retained_bytes`
  is the size observed during the last trim, so a pure cache hit reports `0`.
- **Invalidation is exact-content.** Any change to the compiler sources, Zig
  toolchain, optimize mode, diagnostic format, source path or source bytes
  changes a key. There is no time-based expiry and no notion of a "changed but
  currently unread" file: the caller always reloads every module first.

`--report` prints one `frontend-cache-v1` JSON receipt on stderr; `--timings=json`
adds the same JSON receipt alongside the phase-timing lines. The receipt now also
carries a `stages` object with a hit/miss count for each of the nine incremental
query stages. Plain `--timings` keeps its existing
`timings: native_ns=<integer>` text protocol and does not emit a receipt.
`mylang build --report` keeps its own native `qbe-build-v1` receipt on its usual
stream; the frontend counters are available from `check`, `run` and
`check-project` (or any command with `--timings=json`).

`--explain-invalidation` compares the current checked project against the
previous `project-dependencies-v1` receipt and prints one
`invalidation-report-v1` line on stderr, naming the hit/miss status and the first
changed dependency for every stage. The baseline lives at
`<cache-dir>/invalidation/<entry>.json`, is deliberately not partitioned by
compiler identity so a compiler change can be explained, and `--no-cache` reads
and writes no baseline. A missing baseline is nine misses with `"no-baseline"`;
a corrupt baseline is nine misses with `"corrupt-baseline"` rather than a
failure.

```console
$ mylang check-project app/main.my --report --cache-dir=.mylang-cache/qbe
{"version":"frontend-cache-v1","syntax_hits":0,"syntax_misses":2,"syntax_stored":2,"verdict_hits":0,"verdict_misses":1,"verdict_stored":1,"damaged":0,"bypassed":0,"evicted":0,"retained_bytes":685,"stages":{"load_source":{"hits":0,"misses":0},"lex_parse":{"hits":0,"misses":2},"resolve_interface":{"hits":1,"misses":0}}}
$ mylang check-project app/main.my --explain-invalidation --report --cache-dir=.mylang-cache/qbe
{"version":"invalidation-report-v1","hits":6,"misses":3,"queries":[{"stage":"load_source","status":"miss","key":"...","first_changed":"module:main"},{"stage":"resolve_interface","status":"hit","key":"..."},{"stage":"check_body","status":"miss","key":"...","first_changed":"module:main::main"}]}
{"version":"frontend-cache-v1","syntax_hits":2,"syntax_misses":0,...,"stages":{"load_source":{"hits":1,"misses":0},"lex_parse":{"hits":1,"misses":0},"resolve_interface":{"hits":1,"misses":0}}}
```

## Syntax cache

A module's parsed body is retained under its path, its complete source bytes and
its body start, and reused only when all three match exactly; no hash comparison
can produce a false hit. A hit skips the interface phase's second lexer pass and
the body parser, and deep-copies the syntax into the fresh project, so returned
syntax never borrows retained storage and clearing or eviction cannot invalidate
it. Everything else still runs: source is reloaded and re-lexed for module
headers, and symbols, exports, resolution, visibility, ownership, effects and
every body are checked again. Retention is 256 entries and 16 MiB of entry arena
capacity with oldest-insertion eviction; larger entries are bypassed rather than
stored. In the session below the two-module project is checked, then `main.my` is
edited between the requests, so the unchanged `helper.my` parse is reused and
only the edited module is parsed again.

```console
$ mylang check-session app/main.my
check
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":2},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":5568},"semantic":{"hits":0,"misses":1,"stored":1,"bypassed":0,"retained_bytes":602},"functions":{"reused":0,"checked":4,"stored":1,"bypassed":0,"retained_bytes":4748}}
check
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":1,"misses":1},"cache":{"hits":1,"misses":3,"stored":3,"evicted":0,"bypassed":0,"retained_bytes":8500},"semantic":{"hits":0,"misses":2,"stored":2,"bypassed":0,"retained_bytes":602},"functions":{"reused":3,"checked":5,"stored":2,"bypassed":0,"retained_bytes":5232}}
quit
{"version":"check-session-v1","action":"quit","status":0,"failure":null,"reuse":{"hits":0,"misses":0},"cache":{"hits":1,"misses":3,"stored":3,"evicted":0,"bypassed":0,"retained_bytes":8500},"semantic":{"hits":0,"misses":2,"stored":2,"bypassed":0,"retained_bytes":602},"functions":{"reused":3,"checked":5,"stored":2,"bypassed":0,"retained_bytes":5232}}
```

## Exact verdict cache

One successful whole-program verdict is retained together with its rendered
warnings. A hit requires that the project and its input manifests were loaded
afresh and that every loaded module's name, path and source bytes compare equal;
the hit then replays the owned warning text and skips interface and semantic
work entirely, which is why a verdict hit reports no syntax lookup at all. Failed
checks are never retained, so a type, privacy or deleted-file error cannot
inherit an earlier success, and `clear` drops the verdict along with the other
caches while leaving the cumulative counters. Retention is one snapshot under a
separate 16 MiB arena-capacity bound; oversized entries bypass it. Below, the
second `check` of an unedited project is a verdict hit, and the `check` after
`clear` is a miss again.

```console
$ printf 'check\ncheck\nclear\ncheck\nquit\n' | mylang check-session examples/modules/main.my
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":2},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":12928},"semantic":{"hits":0,"misses":1,"stored":1,"bypassed":0,"retained_bytes":2778},"functions":{"reused":0,"checked":4,"stored":1,"bypassed":0,"retained_bytes":8578}}
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":0},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":12928},"semantic":{"hits":1,"misses":1,"stored":1,"bypassed":0,"retained_bytes":2778},"functions":{"reused":0,"checked":4,"stored":1,"bypassed":0,"retained_bytes":8578}}
{"version":"check-session-v1","action":"clear","status":0,"failure":null,"reuse":{"hits":0,"misses":0},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":0},"semantic":{"hits":1,"misses":1,"stored":1,"bypassed":0,"retained_bytes":0},"functions":{"reused":0,"checked":4,"stored":1,"bypassed":0,"retained_bytes":0}}
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":2},"cache":{"hits":0,"misses":4,"stored":4,"evicted":0,"bypassed":0,"retained_bytes":20312},"semantic":{"hits":1,"misses":2,"stored":2,"bypassed":0,"retained_bytes":1624},"functions":{"reused":0,"checked":8,"stored":2,"bypassed":0,"retained_bytes":8138}}
{"version":"check-session-v1","action":"quit","status":0,"failure":null,"reuse":{"hits":0,"misses":0},"cache":{"hits":0,"misses":4,"stored":4,"evicted":0,"bypassed":0,"retained_bytes":20312},"semantic":{"hits":1,"misses":2,"stored":2,"bypassed":0,"retained_bytes":1624},"functions":{"reused":0,"checked":8,"stored":2,"bypassed":0,"retained_bytes":8138}}
```

## Function body cache

When the verdict cache misses because a module changed, the checked bodies of
functions that did not change can still be reused. The reuse gate is
**declaration-identity backed**: each ordinary declaration contributes a stable
`declarationIdentity` and a semantic interface digest, and the cache publishes
that ordered table together with the resolved type-catalog digest. A second check
reuses only when the ordered identities/interfaces and catalog are unchanged; a
body is reused only when its own full declaration text (header plus body) is
byte-identical, so relocation is exact and position-independent. An interface
change to any declaration stays conservative and rechecks every body, because an
unchanged caller may depend on the changed contract. Whitespace or comments
outside declarations leave every declaration text unchanged and therefore reuse
every body. Reuse is independently owned: a snapshot carries its own spans,
nodes, statements and locals, relocated into the current source, and any
relocation that cannot be validated falls back to checking fresh rather than
trusting a stale reference. Generic, constant and alias configurations still
check fresh, and the region, effect and codec passes rerun completely after every
body edit — so reusing a caller never reuses a callee's effect verdict, and a
callee that gains an effect still rejects an unchanged effect-bounded caller. The
`functions` counters report bodies actually reused and actually checked. In this
single-module session `perimeter` is rewritten between the two requests and the
other two bodies are reused.

```console
$ mylang check-session app/main.my
check
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":1},"cache":{"hits":0,"misses":1,"stored":1,"evicted":0,"bypassed":0,"retained_bytes":11452},"semantic":{"hits":0,"misses":1,"stored":1,"bypassed":0,"retained_bytes":670},"functions":{"reused":0,"checked":3,"stored":1,"bypassed":0,"retained_bytes":5914}}
check
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":1},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":16624},"semantic":{"hits":0,"misses":2,"stored":2,"bypassed":0,"retained_bytes":524},"functions":{"reused":2,"checked":4,"stored":2,"bypassed":0,"retained_bytes":9118}}
quit
{"version":"check-session-v1","action":"quit","status":0,"failure":null,"reuse":{"hits":0,"misses":0},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":16624},"semantic":{"hits":0,"misses":2,"stored":2,"bypassed":0,"retained_bytes":524},"functions":{"reused":2,"checked":4,"stored":2,"bypassed":0,"retained_bytes":9118}}
```

## Native build cache

`mylang build` (and `mylang run`, which builds and then runs) keeps an on-disk
cache of native artifacts. It has three parts with different scopes and lifetimes:

1. **Object cache** — one content-addressed object per guest function, plus the
   generated entry and typed-metadata objects. It lives under `--cache-dir`
   (default `.mylang-cache/qbe`, per project). Keys cover the compiler's build-time
   identity, the runtime content hash, the Zig and QBE tool stamps, and the target
   and optimize mode. A stored object is reused only when a fingerprint over its
   length and contents matches the `.digest` beside it.
2. **Runtime source tree** — the runtime C sources and headers the entry and
   metadata objects compile against, materialized once per content hash. With an
   explicit `--cache-dir` it stays hermetically under `DIR/runtime/<hash>`; by
   default it is shared at `$XDG_CACHE_HOME/mylang/runtime/<hash>` (else
   `$HOME/.cache/mylang/runtime/<hash>`), so a fresh project reuses a tree another
   already derived. It falls back to the per-project cache when no absolute home is
   named.
3. **Prebuilt runtime archive** — installed beside the compiler under
   `lib/mylang-runtime/` by `zig build`, one archive and text-formatter object per
   optimize mode. A cold build links a matching install directly instead of
   compiling the runtime, and falls back to a source build when none matches. See
   [Prebuilt runtime archive](native-build.md#prebuilt-runtime-archive).

The precedence a cold build follows for the runtime: link the installed archive if
its hash matches; otherwise compile it from the runtime tree (shared or hermetic)
into the object cache. `--cache-dir` never reads or writes the shared location.
