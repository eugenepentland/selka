# Compiler caches

The compiler keeps three bounded in-process caches: parsed module syntax, a
whole-program checking verdict, and checked function bodies. Ordinary one-shot
commands build an independent project and use none of them; `mylang check-session`
keeps them across requests so an editor or an agent can check the same project
repeatedly in one process. Every reply is one `check-session-v1` JSON line whose
`reuse`, `cache`, `semantic` and `functions` fields report what was actually
reused. The design records are
[bounded incremental module syntax](../experiments/incremental-syntax.md),
[persistent CLI checking sessions](../experiments/check-session.md) and
[larger-project incremental checking](../experiments/large-project-checking.md).

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
functions that did not change can still be reused. Reuse is conservative and
independently owned: a snapshot carries its own spans, nodes, statements and
locals, relocated into the current source, and any relocation that cannot be
validated falls back to checking fresh rather than trusting a stale reference.
A changed declaration, type or import identity invalidates body reuse, generic,
constant and alias configurations always check fresh, and the region, effect and
codec passes rerun completely after every body edit — so reusing a caller never
reuses a callee's effect verdict, and a callee that gains an effect still rejects
an unchanged effect-bounded caller. The `functions` counters report bodies
actually reused and actually checked. In this single-module session `perimeter`
is rewritten between the two requests and the other two bodies are reused.

```console
$ mylang check-session app/main.my
check
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":1},"cache":{"hits":0,"misses":1,"stored":1,"evicted":0,"bypassed":0,"retained_bytes":11452},"semantic":{"hits":0,"misses":1,"stored":1,"bypassed":0,"retained_bytes":670},"functions":{"reused":0,"checked":3,"stored":1,"bypassed":0,"retained_bytes":5914}}
check
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":1},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":16624},"semantic":{"hits":0,"misses":2,"stored":2,"bypassed":0,"retained_bytes":524},"functions":{"reused":2,"checked":4,"stored":2,"bypassed":0,"retained_bytes":9118}}
quit
{"version":"check-session-v1","action":"quit","status":0,"failure":null,"reuse":{"hits":0,"misses":0},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":16624},"semantic":{"hits":0,"misses":2,"stored":2,"bypassed":0,"retained_bytes":524},"functions":{"reused":2,"checked":4,"stored":2,"bypassed":0,"retained_bytes":9118}}
```
