# New compiler core, stage S4: codegen units and the build cache

Status: design for S4's emission and cache packages (S4-E, S4-C), written during S3
on `claude/new-core-s4-design`. Implementation starts after the S3 exit and the
user's S4 go, against the S3 exit's emitter (§3 lists what S3 added). The decision it implements is S4-1 in
`docs/audits/new-core-s4-plan-2026-10-06.md`, and the measurements behind it are that
plan's §3.

## 1. The invariant

**A unit's LLVM text is a pure function of three things:**
- the functions assigned to it;
- the whole-program facts those functions consumed (inlined bodies, caller-derived
  ranges, ownership plans);
- the target.

Nothing in the text depends on another unit's content, except the declarations of what
it calls or reads.

That makes the build cache exact without any dependency tracking. If two builds emit the
same text for a unit, its object is the same, so the object is reused. If anything the
unit consumed changed, its text changed. Every rule below exists to keep this
invariant. A rule that would let an unrelated edit change a unit's text is a cache
miss, not a correctness bug. A rule that would let a consumed fact change *without*
changing the text is a correctness bug, and the `--verify-cache` check (§6) exists to
catch it.

## 2. Units

**Release builds are one unit (the user, 2026-10-07; plan S4-1a).** Everything in §2–§5
applies to debug builds, which include `mylang test` and the edit loop. A release build
emits the whole program as one unit under the same naming rules, cached by its text like
any unit. Splitting release builds lost LLVM's inlining across units: up to 1.39× on the
split applications.

- **One unit per source module** (file). A function belongs to the module its
  declaration came from; `"my.<module>::<name>"` already carries it.
- **The entry unit** holds `@main`, the entry wrapper and the program-wide constants
  that are genuinely global: `@myl_core_source_path` and the free-list table
  declaration.
- **Generic instances and compiler-generated helpers** (structural equality per type,
  adapters) get **a unit of their own each**, named by a hash of their text.
  - Two modules using `sort[Record]` share one object.
  - A module adding a new instance compiles only that instance.
  - Tiny units are compiled in one batched `zig cc -c a.ll b.ll …` call, so they do not
    each pay a process start (§6).
- **Runtime inline helpers** (`alwaysinline` `myl_core_*`) stay `internal` and are
  copied into each unit that uses them, as the single-unit emitter does today.

## 3. Names and linkage

**Functions:**
- **Program functions keep their stable source-derived names.** A function called from
  another unit is defined `hidden` (external linkage, not exported from the
  executable). Every other function stays `internal`.
- **Calling convention:** every program-defined function uses `fastcc` at its
  definition and at every call. Today LLVM gives internal functions `fastcc` on its
  own; an external definition would lose it.
- **Runtime and `extern_c` functions** keep the C convention.
- **Check:** S4-E measures the five applications split into units against their
  single-unit build, and the gap must be within noise.

**Today's emitter numbers seven things across the whole program** (`emit_llvm.zig`),
and all of them become unit-local:

| Today | S4 |
|---|---|
| `@myl.op.N`, `@myl.fn.N`: one per trap site, in program order | removed; the site record holds its strings (§4) |
| `@myl_core_sites`, `@myl_core_site_count`: one program table | removed; a private `@myl.site.N` record per site, per unit |
| `@myl.str.N`: by module string-table index | numbered per unit, by first use |
| `@myl.layout.N`: by first use in the program | numbered per unit, by first use |
| `@myl.dict.N`: by Core IR compound type id | numbered per unit, by first use (a type id depends on what other functions created first) |
| `!range`, loop and TBAA metadata: one counter | per unit |
| debug metadata: one compile unit, one file `program.my` | one `DICompileUnit` and the module's real `DIFile` per unit |

**S3 added four more** (checked at the S3 exit, `d4994214`). They follow the same
rules:

| Today | S4 |
|---|---|
| `@myl.value.N` with `.children.N` and `.offsets.N` (`emit_values.zig`): descriptors for recursive equality and hashing, by Core IR type id | numbered per unit, by first use |
| `@myl.render.ID` with its `children`, `offsets`, `names` (`emit_render.zig`): render descriptors, by the lowering's metadata id | numbered per unit, by first use |
| `@myl.zeros` (`emit_llvm.zig`): one zeroed constant sized to the program's largest use | per unit, sized to the unit's largest use |
| `@myl_core_source_path`: one external constant that trap and trace text print | removed; each site record points at its module's path (§4) |

**The driver also decides two links by scanning the one `.ll` text** (`driver.zig`):
- the cached float-text object, when `number_runtime.needed(llvm)`;
- `-lm`, when the text calls `llvm.sin.f64` or `llvm.cos.f64`.

With units, each decision is the union over every unit in the program, cached or not.
So a unit's cache entry records its own two answers.

The spike's `--normalize` mode simulates exactly this renumbering. With it, a 48k-line
project's units changed only where the edit was, or where the edited function was
inlined (`units-ripple.json`).

## 4. Trap sites and error traces (a runtime ABI change)

**Today:**
- `myl_core_trap(i32 index, i64, i64)`, `myl_core_assert_fail(i32 index)` and
  `myl_core_err_trace(i32 index, i32 restarts)` index the program-wide
  `myl_core_sites` table;
- the error-trace ring and its origin store those indexes (`core_rt.c`).

**S4:**
- Each unit emits its sites as private `%myl.site` records, with the operation and
  function strings inline or as private constants.
- The three runtime entry points take `ptr` to the record.
- The trace ring and origin store `const myl_core_site *`.

**Cost:**
- Trap and assert calls are cold, so nothing changes on a hot path.
- An error-trace push stores 8 bytes instead of 4. S4-E measures `result_propagate` and
  the applications that propagate errors, and the gap must be within noise.

**Output:** trap reports, error traces and their text are byte-identical to today's.
The record carries the same kind, line, column, width, operation and function.
Conformance at 0 mismatches is the check.

## 5. Facts and determinism

- **Cross-unit facts are correct by construction.** A callee whose parameter ranges come
  from callers in other units (`NEW-CORE-FACTS-10`) carries those ranges, and their
  verify asserts, in its own text. A caller edit that changes them changes the
  callee's unit. Inlined bodies are in the caller's text.
- **Emission must be deterministic:** units, functions, constants and metadata in IR
  order, and no iteration over hash maps. Two builds of the same program must give
  byte-identical units. That is a test (§7).
- **Line numbers:** an edit that shifts lines changes only its own module's unit,
  because only that unit's debug metadata names those lines.

## 6. The cache and the driver (S4-C)

**Key:** BLAKE3 over all of these:
- the unit text;
- the optimization level;
- the resolved target, which means the host CPU's model and features rather than the
  string `-march=native`, so a cache copied to another machine cannot serve a wrong
  object;
- the Zig version;
- the core runtime ABI version;
- the emitter version.

**Store:** `.mylang-cache/core/units/<key>.o`, written to a temporary name and then
atomically renamed. `scripts/prune-caches.sh` evicts it like the other caches.

**Hits** spawn no process; that is why the cache is the core's own and not only Zig's.
Zig's own local cache also reuses an identical `.ll`, but at a process start per unit.

**Misses** compile in parallel:
- up to `MYLANG_JOBS`, else the available cores;
- small units are batched into one `zig cc -c` call with several inputs;
- the runtime object stays cached by content, as today;
- linking all objects with the runtime took 0.04–0.07 s for 49 units.

**`--verify-cache`** recompiles every unit the cache served and compares object
bytes. The new core's test suite runs it on a multi-module fixture, and S4-X runs it
once over the Lox port and the EDA slice.

## 7. Tests S4 adds

- **Unit text stability:**
  - build a multi-module fixture twice; every unit is byte-identical;
  - change one function body; exactly its unit changes;
  - add a statement with a new checked operation; still only its unit;
  - change a small public helper that another module inlines; its unit and the
    caller's unit, and no other.
- **Cache:**
  - a second build of an unchanged program compiles nothing;
  - an edit compiles exactly the changed units;
  - `--verify-cache` passes;
  - a corrupted cache entry is detected and rebuilt, never linked.
- **Behavior:**
  - full conformance, debug and release, at 0 mismatches, with the leak and verify
    sweeps;
  - trap and error-trace text identical across a multi-unit build;
  - the 46 rows, all single-module programs, emit one unit plus the entry unit, and
    their timings stay unchanged.
- **Release mode (S4-1a):**
  - a release build of a multi-module program emits exactly one unit;
  - an unchanged release build starts no `zig cc`;
  - a split debug build's output equals the release build's on the five applications.
