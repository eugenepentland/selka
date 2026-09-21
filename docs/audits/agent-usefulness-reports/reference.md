# F1 half B — the compiler-derived reference engine

Package: **F1 — Make compiler facts unambiguous and current**, half B (the
`mylang reference` surface). Plan §F1 acceptance this package answers: reference
examples match the selected binary even when the surrounding checkout differs;
JSON uses explicit status/null fields rather than an empty set for unknowns.

## Status

**Done, in the tree, unit-tested.** The engine, its curated prose, its command shell
and twelve unit tests exist and pass. The one thing that is *not* done is wiring the
route into `src/main.zig`, which is the wiring agent's file:

| Piece | File | State |
| --- | --- | --- |
| Fact engine (`run`, `Request`, `Format`, `EntryReader`) | `src/reference.zig` | done, 36/36 focused tests pass |
| Curated prose and examples | `src/reference_text.zig` | done, every example executed by `test-docs` |
| Flag parsing, output, exit status | `src/reference_command.zig` | done, exercised end-to-end from tests |
| Unit tests | `src/reference_test.zig` | done, registered in `src/root_test.zig` |
| Spec tags | `SPEC.md` `REFERENCE-1..12` | written by the lead from these tests (one wording refinement by me) |
| Documentation | `docs/reference.md`, `README.md` bullet | done |
| `reference` route in `main.zig` dispatch | `src/main.zig` | **deferred to the wiring step** (exact diff below) |

`docs/reference.md` opens with the not-yet-wired status in a block quote, so the page
does not claim a command an installed binary cannot run yet.

## Files changed

- `src/reference.zig` (new) — the engine.
- `src/reference_text.zig` (new) — seven curated syntax/boundary entries.
- `src/reference_command.zig` (new) — `run` / `answer` / `usage`.
- `src/reference_test.zig` (new) — twelve tests, `// spec: REFERENCE-1..12`.
- `src/root_test.zig` — one appended line: `_ = @import("reference_test.zig");`.
- `SPEC.md` — `REFERENCE-1..12` bullets (appended by the lead; I refined
  REFERENCE-2's wording only).
- `docs/reference.md` (new) — the surface, the fact-status vocabulary, the curated
  examples as executed `mylang` blocks.
- `README.md` — the "Compiler-pinned references" bullet now points at the current
  surface (`mylang --features`, `list-declarations`, `list-interfaces`,
  `schema-project`) and marks the experiments page historical.
- `src/compiler.zig` — **not mine**; the lead added `reference_tables` (see below).

## Commands run, and what they said

```
$ python3 scripts/focused_test.py units reference
focused tests: units filter='reference'
selected: 36 test(s)
result: PASS - 36 passed, 0 failed, 0 skipped
elapsed: 7.0s

$ zig build fmt-check            # exit 0, no output
$ ../guardian-zig/zig-out/bin/guardian-check all .
guardian: run-all: 88 check(s) passed — diff-scoped vs b8f6ec3f...

$ ./zig-out/bin/mylang doctest . --filter 'docs/reference.md'
  docs/reference.md: 6 run, 1 checked, 0 skipped, 0 mis-tagged, 0 failed
```

`zig build test-docs` as a whole **fails on another package's file**, not on this
one: `docs/audits/agent-usefulness-reports/baseline-2026-09-20.md:244` runs the
deliberately incomplete `todo[int]()` probe and gets `E_TYPED_HOLE` (the W0 report
also has four mis-tagged blocks). That page needs `# doc: expect-error E_TYPED_HOLE`
or `# doc: not-mylang`; the baseline is evidence I must not rewrite, so I left it.

## The module boundary that shaped the design

Zig refuses a source file that belongs to two modules: *"file exists in modules
'root' and 'mylang'"*. `src/main.zig`'s root module already imports the compiler as
the `mylang` module, so `reference_command.zig` cannot relative-import anything
inside `compiler.zig`'s closure — and `project.zig`, `interfaces.zig`,
`project_compile.zig`, `effect_set.zig`, `source.zig`, `prelude.zig`,
`prelude_builtins.zig`, `buffer_operations.zig`, `io_builtins.zig`,
`float_intrinsics.zig` and `runtime_values.zig` are all inside it. The unit root
(`src/root_test.zig`) has no `mylang` import at all, so the engine cannot use
`@import("mylang")` either.

The only shape that compiles in both roots is a **comptime language parameter**:
`src/reference.zig` imports only `std` + `reference_text.zig`, and every entry point
takes `comptime language: type` first. The installed executable passes
`@import("mylang")`; `reference_test.zig` passes the same compiler root assembled
from relative imports. The lead added one declaration to `src/compiler.zig`:

```zig
pub const reference_tables = struct {
    pub const prelude = @import("prelude.zig");
    pub const prelude_builtins = @import("prelude_builtins.zig");
    pub const buffer_operations = @import("buffer_operations.zig");
    pub const io_builtins = @import("io_builtins.zig");
    pub const float_intrinsics = @import("float_intrinsics.zig");
    pub const runtime_values = @import("runtime_values.zig");
};
```

## API, and the wiring diff to make it a command

Public API of `src/reference.zig`:

```zig
pub const envelope_version = "reference-v1";
pub const Format = enum { text, json };
pub const Error = error{ OutOfMemory, EmptyQuery };
pub const Request = struct { query: []const u8, format: Format = .text, check_bodies: bool = true };
pub fn run(comptime language: type, allocator: std.mem.Allocator, request: Request) Error![]u8;
pub fn EntryReader(comptime language: type) type;   // the embedded project's whole provider
pub const entry_module = "reference";
pub const entry_path = "reference.my";
pub const standard_modules = [_][]const u8{ ... };  // the twelve, pinned by a drift test
```

`src/reference_command.zig`:

```zig
pub const usage: []const u8;
pub const Error = error{ OutOfMemory, WriteFailed };
pub const Outcome = struct { status: u8, stdout: []const u8, stderr: []const u8 };
pub fn answer(comptime language: type, allocator: std.mem.Allocator, args: []const []const u8) Error!Outcome;
pub fn run(comptime language: type, process: std.process.Init, args: []const []const u8) Error!u8;
```

**The one-line wiring**, exactly as it should land in `dispatch()`, beside the
`doc-coverage`/`doctest` routes (any position among the other self-contained
subcommands works; line 216 in today's `src/main.zig` is directly after `doctest`):

```zig
    if (args.len >= 2 and std.mem.eql(u8, args[1], "reference")) return @import("reference_command.zig").run(@import("mylang"), process, args[2..]);
```

The only difference from the sketch in the lead's message is the explicit
`@import("mylang")` first argument, which is what makes the same engine instantiable
from the unit test module. `run` parses `--query TERM` / `--query=TERM`,
`--format=text|json` / `--format=text|json`, and `--help` itself; it never touches
`Parsed`/`parseArgs`/`Command`, so no `Command` enum entry is needed.

**Usage text I cannot reach from my file** — one line added to the `usage` constant in
`src/main.zig`, anchored after the doctest line:

```zig
    "doctest [<repo-root>] [--filter GLOB] [--report PATH] [--jobs N] [--verbose] (run every fenced documentation example)\n       mylang " ++
    "reference --query TERM [--format=text|json] (compiler-derived facts from this executable)\n       mylang " ++
```

(`mylang reference --help` already prints the command's own fuller usage from
`reference_command.usage`.)

## The derivation route, and its fact-status label

The engine builds a **checked in-memory project**, and nothing else:

1. `entrySource` synthesizes `module reference` importing all twelve embedded
   standard modules plus a `def main() -> int: return 0`. The `main` matters: without
   an entry point the checker leaves the program unset and every effect falls back to
   the conservative full vocabulary.
2. `project.Project.load` runs against `EntryReader`, whose `read` serves only
   `reference.my` and answers `NotFound` for everything else. The twelve standard
   modules never reach a provider: `project.intern` resolves them through
   `standard_library.source(path)` first.
3. `interfaces.build` builds the index; `project_compile.Compilation.init` + `check`
   attaches the checked program (the project's pre-check problem is saved and
   restored exactly as `list-interfaces` does); then `Index.render` prints the
   versioned `module interfaces v1` listing.

Status vocabulary, per declaration and for the library:

| `analysis` | When | `effects` | `ceiling` / `mutates` |
| --- | --- | --- | --- |
| `checked` | bodies checked and a checked instantiation exists | the checker's own inferred mask from `program.functions[].policy.effects` | from the listing |
| `template` | bodies checked but the declaration is generic and nothing instantiated it | `null` (the symbolic entry's conservative full mask is **not** republished as an inference) | from the listing |
| `declaration-only` | bodies not checked (`check_bodies = false`, or the check failed) | `null` | from the listing |
| `declared` | a type/resource/constraint declaration | `null` | n/a |

`library.status` is `checked`, `declaration-only` (with the body-check error name as
`reason`) or `unavailable` (with the project's diagnostic code as `reason`, and
`declarations: null` — which is a different fact from a list that matched nothing).

**Why not the plan's suggested `renderContracts`/`contractSignatureText` route:** it
does not work on the embedded standard library. `Index.renderContracts` fails with

```
@stdlib/network.my:5:29: error[E_UNKNOWN_SYMBOL]: declaration is not present in the resolved module
  public resource Connection: network
```

reproducible with the frozen binary (`mylang list-interfaces <entry importing network>
--contracts`, exit 1) and with the working tree. `contractSignatureText` is private to
`interfaces.zig`, which this package must not edit. The engine therefore parses the
`module interfaces v1` listing — the compiler's own published surface, not a source
parser — for the declared facts (signature, `ceiling(...)`, `mutates(...)`), and reads
the inferred effects from the checked program instead of the listing's published mask,
because that mask is the unbounded fallback when no instantiation exists.

`--query` matching is a documented **case-insensitive substring** over each fact's
slug/name/summary/signature/families/source table; categories are emitted in a fixed
order and each is sorted by key, so two runs are byte-identical. `match` is `exact`
when the term equals a whole key, `substring` otherwise, `none` with count 0 when
nothing matched; an empty or whitespace-only query is `error.EmptyQuery`, which the
command turns into a usage failure (exit 2).

## Findings for other packages

1. **`list-interfaces --contracts` is broken for any project that imports the
   embedded `network` module** (repro above). That is the `interfaces.zig` owner's
   fix; F1's C1/H1 successors would otherwise build on a route that cannot see the
   standard library's contracts.
2. **`standard_library.zig` exposes only `source(path)`**, so the engine repeats the
   twelve paths as `reference.standard_modules`. A test enumerates `src/stdlib/*.my`
   in the checkout and fails when the sets differ, so the copy cannot drift silently;
   exposing the path table from `standard_library.zig` would remove the copy.
4. **The doctest gate fails on `docs/audits/agent-usefulness-reports/baseline-2026-09-20.md`**
   (line 244) — the deliberately incomplete probe needs `# doc: expect-error
   E_TYPED_HOLE`; three other audit-report blocks are mis-tagged.
5. `mylang reference` is not yet in the README's command list or `main.zig`'s usage;
   both belong to the wiring step above.

## Remaining limits (stated, not hidden)

- **The engine always checks the embedded bodies.** `check_bodies = false` is the
  documented/tested degraded path, but no *user-facing* flag exposes it: with the
  embedded library always checkable, the honest per-declaration distinction that
  matters in practice is `checked` vs `template`.
- **Templates report no inferred effect set even when the compiler could have proved
  one** for a symbolic body. That is the conservative direction F1 asks for.
- **Signature derivation depends on the `module interfaces v1` listing grammar.** The
  parser is small (`parseFunctionLine`/`parseNominalLine`) and documented, and the
  focused tests pin the current output; a format change is a loud test failure, not a
  silent mis-parse. The declaration name/signature split is robust to callback types
  (it anchors on the *last* ` effects(`), and clauses are read by keyword.
- **Curated discovery seeds.** `prelude_builtins.reserved` and
  `float_intrinsics.operation` answer names rather than publishing a list, so
  `reference.zig` carries a small seed list and emits a fact only when the checker's
  table accepts the seed. A newly added prelude builtin would not appear until a seed
  is added; the arities that do exist always come from the table.
- **Builtin arities are `null` where the table carries none** (the eleven prelude
  names, the capability type names) rather than invented. `io_builtins.Builtin`,
  `buffer_operations.Kind.arity`+`spelling`, and `prelude.arity` supply the rest.
- **Collection-method arities** are computed as "every operation whose source spelling
  is this name contributes its arity", so `split` answers `{0,1}` and the `pop`
  spelling answers `{0,1,2}`; the checker's receiver-dependent vocabulary rules are
  not restated.
- The `reference` route is not wired, so no user-facing command exists yet; the
  README's current-surface bullet lists only commands that already run.
