# Memory escape hatch and concurrency audit — 13 September 2026

This audit answers three questions against the working tree of 2026-09-13
(branch `codex/language-mvp`, HEAD `ad96697` plus 103 modified and about 30
untracked files): how the manual-memory escape hatch should work, how concurrent
code should work, and what else would serve the stated goals. The stated goals
are maximum development speed through incremental compile/test from the start,
garbage collection by default with manual memory as an escape hatch, and syntax
close enough to Python and Go that AI agents already know it.

Evidence used: the SPEC, `docs/`, `features.json`, the 2026-09-07 feature audit,
the 2026-09-12 simplicity audit, the velocity-v1 and development-velocity-20260908
results, the schematic guest application (13 modules, 2,184 lines), the standard
library (35 modules, 7,835 lines), the lexer/parser/sema/VM/GC sources, and eight
probe programs run against `zig-out/bin/mylang` (SHA-256 `32940b7c…cfe65e`).
No implementation was changed and no gate was run.

## Summary

1. **Do not build a Rust-style borrow checker.** The escape hatch should change
   *when memory is freed* (regions/arenas) and *where objects live* (pools with
   generational handles), never *what types ordinary code uses*. Keep references
   second-class, exactly as they are today. Collapse the explicit-storage tier
   (buffers, pools, owned vectors, borrow blocks) into region allocation of
   ordinary GC objects plus a library `Pool[T]`.
2. **Concurrency should be isolates plus structured concurrency and typed
   channels, with a deterministic cooperative scheduler inside each isolate.**
   No shared mutable heap, no async/await function colouring, no `Send`/`Sync`
   tracking. This keeps the GC single-threaded per isolate and keeps every
   existing replay/receipt tool valid.
3. **Compile speed is not the bottleneck; the language surface is.** In the
   twelve-task cohort only 1.8% of My's delivery time was inside tool operations,
   My used 2.55× Python's output tokens, and a cold check of the schematic is
   8 ms. Stop investing in finer incremental checking and verification
   infrastructure; invest in the items in section 4.

## 1. Where the language stands

Strong, and worth protecting:

- Checked arithmetic, bounds, definite initialisation, exhaustive `match`,
  must-handle `Result`, `?` propagation, nominal domains and enums.
- Effects and capabilities (`noalloc`, `nogc`, `noio`, explicit allocator,
  clock, random, filesystem grants). These give local, explainable diagnostics.
- `--diagnostics=json` with move/borrow/arena provenance and repair fixtures;
  typed holes; bounded VM traces; deterministic host replay.
- `mylang test` with dependency-aware result reuse; QBE per-function object
  cache; `check-session` with syntax, verdict and function-body caches.
- A nonmoving tracing GC with cycle collection and a `--gc-stress` rooting check.

Facts that drive the recommendations below:

| Observation | Evidence |
| --- | --- |
| Three syntaxes are accepted and all are taught | 35/35 stdlib modules and 94/100 example files use the legacy `fn`/`let`/`borrow` spelling; 6 examples and the schematic use Python spelling; a brace "familiar" spelling sits between them. The formatter preserves whichever spelling it sees. |
| The keyword surface is 124 tokens | `src/lexer.zig`; Python has 35 keywords, Go has 25. About 80 of the 124 are storage/resource/float intrinsics (`acquire_buffer`, `read_slice`, `f64_add`, `restrict_resource`, …). |
| `class` is a value type without methods | Probe: `b = a; b.x = 10; shift(a)` returns `a.x == 1`; Python gives 11. `def bump(self)` inside a class is a syntax error. |
| Python essentials are absent | Comprehensions, `lambda`, `assert`, `with`, tuples, f-strings, capturing closures. |
| The two memory tiers cannot reference each other | "Explicit buffers and pools cannot contain managed references"; "lists: copyable values without must-handle obligations"; "no stored reference fields". |
| Error payloads are integers | 18 `Err(<int>)` sites in the schematic; `Result[T, int]` is the documented convention. |
| Residual low-level noise in Python-style code | Schematic still has 26 `_ = io.put(...)` discards, 55 `NNu8` literals, `&[]u8`, `len_slice`, `read_slice`, `cast<u8>`. |
| Checking is already fast | Schematic: 8.23 ms cold, 1.07 ms warm, 3.91 ms after a body edit (ReleaseFast profile); 26 ms wall including process start on this machine. |
| The language is currently slower for agents than Python | Twelve matched tasks: median 179.8 s vs 79.1 s; 2.05× responses; 2.55× output tokens; 1.8% of time inside tools. Velocity-v1 improvements moved delivery time +11.6%. |

## 2. The memory escape hatch

### Recommendation: one object model, three lifetimes, no first-class references

**Tier 0, the default: GC heap.** `list`, `dict`, `str`, a managed `bytes`, and
`class` instances are traced objects. `class` should become a reference type
with identity and methods (see 4.3); value records get a separate spelling.

**Tier 1, "free it all at once": region blocks over ordinary objects.**

```python
with arena() as a:
    nodes = build_graph(input)      # every allocation in this dynamic extent
    answer = solve(nodes)            # lands in region `a`
    result = a.escape(answer)        # explicit copy-out of what survives
# region freed en masse here; `nodes` cannot be used after this line
```

Semantics: allocations performed while the region is the innermost active
region are bump-allocated into it and are not individually traced. At exit the
region is released. The existing conservative escape checker (`E_ARENA_ESCAPE`,
`docs/experiments/source-arenas.md`) already implements the static rule; the
existing region generation/lease machinery already implements the runtime
defence. What changes is that the *thing being allocated* is an ordinary list,
dict, string or object, not a distinct `buffer` type. A function-level form
(`@arena def f(...)`) covers the common "temporaries die at return, the result
escapes to the caller's region" pattern.

Keep `nogc` and `noalloc` as the way to *prove* a hot function does not touch
the heap. They are cheap, local, and agents can act on the diagnostic.

**Tier 2, "objects live in a table": `Pool[T]` with `Handle[T]`.** Already
implemented as the `pool` keyword with generational, category-checked handles.
Demote it to a standard-library generic over a managed list. This is the
graph/ECS escape hatch used by game engines and by Rust programmers avoiding
the borrow checker; it needs no lifetime machinery, handles are copyable
integers, stale handles fail at runtime with a typed error, and it composes
with GC objects because there is only one object model.

**Tier 3, resources, not memory: `with open(path) as f:`.** The current
`resource`/`complete_resource`/must-handle completion semantics are right;
re-spell them as Python's `with`. Cleanup on scope exit releases; fallible
completion (commit, close-with-flush) stays an explicit `Result`. GC finalizers
must never be the mechanism for closing external resources.

**References stay second-class.** `&T`, `&mut T`, `&[]T` parameters remain
(spelled however the canonical syntax decides), never stored in fields, never
returned except through the existing `from parameter` contract. This is the
"mutable value semantics" model (Swift `inout`, Hylo). It is what the checker
already enforces.

**Unsafe/FFI.** Raw pointers stay inside host wrappers and `extern fn`. An
in-language `unsafe` block is a non-goal until an application needs it.

### Why not a Rust-style borrow checker

- Rust's model is usable only with stored references, lifetime parameters and
  non-lexical lifetimes. The current checker is lexical, whole-allocation, and
  explicitly excludes stored reference fields. Closing that gap is the largest
  single piece of work in language implementation, and it would replace the
  simplest rules in the language with the hardest.
- It contradicts GC-by-default. Ownership in Rust *is* the memory model; it
  cannot be an escape hatch for a subset without two incompatible type systems.
  The repository already has that outcome: managed lists cannot hold buffers and
  buffers cannot hold managed references, so the "escape hatch" and the default
  do not compose.
- The agent data does not favour it. Rust's median in the same cohort was
  178.9 s, indistinguishable from My's 179.8 s, against Python's 79.1 s.
  Ownership repair loops are exactly the token-expensive turns the goal wants
  to remove.
- Regions and handles are what Zig, Odin, Jai, Go game code and most C
  programmers actually do for performance. The mental model is "everything in
  this block dies together" and "this int names a slot", both of which an agent
  states correctly on the first try.

### What this deletes

`buffer`, `pool` (as syntax), `acquire_buffer/append_buffer/read_buffer/…`,
`borrow … as`, grouped borrows, `split`, `take_field`, `read_field`,
`acknowledge`, `discard`, owned vectors/maps, and the buffer/pool/managed
partition rules. That is roughly half the keyword table and a large share of
`sema.zig` and `generic_bodies.zig`. Keep the runtime pieces (lease registry,
generations, region stack, owned-scope cleanup) because the region design
reuses them.

## 3. Concurrency

### Recommendation: isolates, structured concurrency, channels, deterministic scheduling

```python
def crawl(urls: list[str], net: NetworkCap) -> list[Page]:
    with TaskGroup() as tg:
        tasks = [tg.spawn(fetch, url, net) for url in urls]
    return [t.result() for t in tasks]     # all tasks joined at block exit

def pipeline(items: Channel[Item], out: Channel[Summary]):
    for item in items:                     # blocks cooperatively
        out.send(summarize(item))
```

- **Isolate** = one VM heap, one GC, one scheduler. Isolates share nothing.
  Parallelism is N isolates on N OS threads, which is what
  `scripts/workers.py` already does with processes.
- **Sendable** values cross isolate boundaries: immutable values (`int`,
  `float`, `str`, `bytes`, value records, enums), capabilities passed
  explicitly, and GC graphs that are deep-copied. A later optimisation can
  *move* a graph whose root refcount is 1 (the VM already refcounts roots).
- **Inside an isolate**, tasks are green threads over the VM's existing explicit
  frame stacks. Switching happens only at channel operations, task join, I/O
  and explicit `yield()`. No preemption, so two tasks can never interleave a
  list mutation; no function colouring, so any function may block.
- **Structured**: every task belongs to a `TaskGroup` (or a `Channel` scope);
  block exit joins or cancels; an error in a child propagates as a `Result`.
  This maps directly onto the existing scope-exit cleanup and region stack.
- **Deterministic scheduler by default** (seedable for tests). Runs are
  reproducible, `--gc-stress`, host replay and verification receipts stay
  valid, and an agent can reproduce a concurrency bug from a seed.

### Why this and not the alternatives

| Alternative | Why not |
| --- | --- |
| Shared-memory threads with data-race freedom (Rust `Send`/`Sync`) | Requires the borrow checker rejected in section 2. |
| Go-style goroutines on a shared heap | Needs a concurrent GC (the current collector is single-threaded with refcount roots and a nonmoving sweep); data races become the dominant agent bug; determinism is lost. |
| Python `async`/`await` colouring | Agents forget `await` and mis-colour helpers constantly; the effect system already tells the checker what may block, so colouring adds nothing. |
| Actors with mailboxes only | Fine as a library on top of channels; not needed as a primitive. |

### Implementation notes

The VM already runs calls iteratively on heap-allocated frame buffers, so a
task is a second frame stack plus a scheduler queue. The `--max-steps` counter
is a natural fairness hook (trap a task that never yields). Effects extend
naturally: `spawn` requires the callee's effect ceiling to be satisfiable from
the capabilities actually passed. The process-worker experiment's typed-message
contract is the sendable contract; keep it, drop the process boundary.

## 4. Other items that serve the goals, in priority order

### 4.1 Redirect effort from compile speed to surface area

The measurement infrastructure (SQLite scheduler, merge certificates, shared
receipts, cohort analysis) is now larger than the standard library. Phase 6
finer semantic reuse is correctly gated on measurement; the measurement says
8 ms. Keep the body cache and the QBE object cache, and stop there. The one
piece of incremental tooling agents actually feel is `mylang test --watch`
with function-level affected-test selection, which the navigation call graph
and the existing test-receipt dependency tracking can already support.

### 4.2 One syntax, and make the repository teach it

Agents imitate what they retrieve. Today that is 35 legacy stdlib modules and
94 legacy examples. Rewrite the standard library and examples in the canonical
syntax, move the rest to `legacy/` with a header saying so, and reject legacy
spellings under `--strict` until it becomes the default. The 2026-09-12 audit
made the same point; the Python decision since then makes it more urgent, not
less.

### 4.3 Give `class` Python's object model

`class` should be a reference type with identity, methods with explicit `self`,
and mutation visible through aliases. The GC heap already exists; records
become traced objects instead of copied snapshots. Keep value semantics under a
separate spelling (`struct`, Go-familiar, or a `@value` decorator). The probe
result `110` where Python gives `1111` is the single most likely silent
divergence an agent will hit.

### 4.4 Fill the Python gaps agents will type on the first attempt

Comprehensions, `lambda` and capturing closures (cheap now that the GC exists;
the noncapturing callback design was a workaround for its absence), `assert`
with diff rendering, `with`, tuples and multiple return, f-strings, `in`/`not in`
everywhere, slicing with step. Each absence today is a syntax error and a repair
turn.

### 4.5 Make errors readable

`Result[T, int]` with `Err(5)` forces agents to invent code tables. Make the
error payload an enum or `str` by convention, let `main` return `Result[..., E]`
for any `E` with a `str` conversion, and have the runner print the error and
the propagation trace.

### 4.6 Cut keywords to library calls

Every `read_slice`, `f64_sqrt`, `acquire_resource`, `restrict_resource`,
`wrapping_add` should be a method or module function with ordinary call
syntax. Target Python's 35 keywords. Managed `bytes`/`bytearray` removes most
`&[]u8`, `len_slice`, `read_slice` and `NNu8` literals in the schematic.

### 4.7 Drop module boilerplate

`module main` must match the file name, `export` lists are separate from
declarations, and a mismatch is `E_MODULE_NAME`. Infer the module from the
path, and use Python's underscore-prefix privacy (or Go's capitalisation) on
the declaration itself.

### 4.8 Land the working tree

103 modified files, ~6,000 insertions, and the three documents that define the
new syntax (`python-syntax.md`, `managed-memory.md`, `familiar-syntax.md`) are
untracked. Commit in coherent pieces so the audits, velocity evidence and
feature receipts can pin a hash.

## 5. Suggested sequence

1. Commit the current tree. Declare Python spelling canonical; add `--strict`.
2. `class` → reference type with methods; `struct` for values. Managed `bytes`.
3. Regions over ordinary objects (`with arena()`), reusing the region checker
   and runtime. `Pool[T]` as a library. `with` for resources.
4. Delete the explicit-storage tier and its keywords; rewrite the stdlib and
   examples in the canonical syntax.
5. Comprehensions, closures, `assert`, tuples, f-strings; readable errors.
6. Green tasks + channels + `TaskGroup` inside one isolate with a deterministic
   scheduler; isolates on threads replacing process workers.
7. Re-run the twelve-task cohort against Python with the same harness.

Each step is a versioned migration; the formatter cannot do it because it
preserves spellings, so a separate checked migration tool is needed for step 4.
