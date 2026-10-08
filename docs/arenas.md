# Arenas (retired)

`with arena():` regions, which released every managed object a phase of work
allocated in one step, were retired in stage S5 of the new compiler core
(2026-10). Memory is reference counted: every object is released as soon as its last
owner goes away ([managed collections](managed-memory.md#releasing-memory)), so a
region has nothing left to free early.

A `with arena():` or `with arena() as name:` block still checks and runs, as an
ordinary block, so existing programs keep their output. It warns `W_ARENA_RETIRED`
at the `with`; a program with an error does not carry the warning. `name.escape(value)`
returns `value` unchanged. Remove the `with` line and dedent its body:

```console
$ mylang run phase.my
phase.my:2:5: warning[W_ARENA_RETIRED]: `with arena():` is retired (S5-D3): the block runs as an ordinary block and frees nothing early; remove the `with arena():` line and dedent its body
      with arena():
      ^
```

What went with it: the arena escape checks (`E_ARENA_ESCAPE` and the confinement of
a value first assigned inside the block), the runtime's region chunks and their
retention, and the arena tests. The older explicit storage tier's arenas are
described in [removed features](legacy/README.md).
