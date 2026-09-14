# D3: Keep the default managed and value-oriented

Status: accepted.

## Rule

Compiler code uses managed lists, dictionaries, strings, records, tagged unions,
results, options, and explicit loops. Fixed arrays, bytes, arenas, effect ceilings,
typed C calls, and provider APIs are opt-in boundary or measured-performance tools.

## Rejected alternative

Reject a second general allocation model, stored references, ownership syntax,
and general pointers in the compiler port. A slow workload is profiled before a
bounded representation or phase is optimized.

## Compatibility consequence

Ordinary code keeps tracing-GC and value semantics. Escape-hatch APIs remain
available but do not enter `bootstrap-v1` merely because they exist. A future
systems feature needs its own evidence and does not silently widen the compiler
subset.
