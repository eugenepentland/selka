# Historical Lox migration notes

The entries below are preserved historical notes. Current ownership migration
and qualification are documented in ../README.md and ../evidence/.

# mylang port

## S4 value-semantics migration (2026-10-06)

Current pin: compiler commit `a16a324e629c1c68e0180017f6d2faf20364b13d`,
binary SHA-256 `eb354a1ad3763aa0c3851f6a96eb2bccf2ab0df94a2b983db46bdd0725c34eaf`.
The migration runs on `codex/s4-lox-value-semantics` in its own locked worktree;
the existing benchmark checkouts are unchanged.

The 16 compiler/VM/parser/runtime classes are now records. `ObjRef` still carries
Lox identity in the existing object-table union. A changed function, upvalue,
instance-field table, class-method table or environment-slot row is written back
to that handle. State carriers use `mut` locals and explicit publication; call
frames publish instruction positions before calls. The bytecode, heap, index-based
AST and two-engine structure remain as before. Required call-site `mut` markers
are restored. Calls that update the same receiver are split into separate
statements for MUT-OVERLAP-RECEIVER-1, including startup, resolver annotations and
the collector's gray-stack pop.

Exit: harness release conformance is VM 246/246 normal + 246/246 gc-stress and tree
241/241 normal + 241/241 gc-stress (974/974 total). All original 63 tests remain,
and two regressions cover RHS mutation and receiver replacement. The directory
run passes 65/65 with `--jobs 4`; explicit driver provider cases pass 13/13.

The current runner includes `driver_tests.my` during directory discovery. Its
four-engine stress case needs the same 100,000,000-step budget already used by the
explicit driver invocation, so directory test.run/test.force now receive that
budget too. Every build profile command and the two-command test structure are
preserved. The previous startup-loop implementation remains; attempted startup
shortcuts were reverted after they failed to solve the default-budget issue.

Old-core CPU-10 baselines, serial tests: build cold/unchanged/one-function edit
7.6569/0.0068/0.1952 s; the two-command tests total
21.9960/0.1451/0.6481 s. The edit is bench.json's leaf_body change to clock_native;
it is restored after measurement. Full commands, identity, per-command logs,
source preservation and exit evidence are in
`experiments/new-core-s4-lox-20261006/REPORT.md`.

No language blocker was found. The notes below describe the historical port and
its earlier compiler pins; the current representation and checks are above.

Built and tested with the pinned compiler at `.tmp/lox-bench/mylang-install`
(`compiler_sha256` 98d87887…, Zig 0.17.0-dev.1683). Every command below ran
under `taskset -c 12-19`.

## Status

| Check | Result |
|---|---|
| `conformance --engine both --stress` | vm 246/246 normal, 246/246 gc-stress; tree 241/241 normal, 241/241 gc-stress |
| Same, on the `release-qbe`, `release-unchecked` and `debug` binaries | identical |
| Unit tests (bench.json `test.run`) | 63/63: 52 in the directory run across 9 programs, 11 in `driver_tests.my` |
| `check` at smoke size, normal and stress | 52/52 ok, stdout matches the oracle |
| `check --tier vm --tier tree --no-stress` | 26/26 ok (45 s wall with `-j 4`) |
| bench.json profiles | release, release-safe, release-qbe, release-unchecked and debug all build through `lox_bench.py build` |
| bench.json edits | each `find` occurs once; every edit alone, and all four together, builds and passes conformance |

`[stats]` at smoke size, normal mode (identical to the Go port's figures):

```
fib           vm   allocations=9 collections=0 freed=0 live=9
fib           tree allocations=1980 collections=0 freed=0 live=1980
binary_trees  vm   allocations=8442 collections=0 freed=0 live=8442
binary_trees  tree allocations=63300 collections=2 freed=45239 live=18061
closures      vm   allocations=4087 collections=0 freed=0 live=4087
closures      tree allocations=14309 collections=0 freed=0 live=14309
```

`lox_bench.py loc --port mylang`:

```json
{
  "files": 26,
  "lines": 5120,
  "nonblank": 4182,
  "test_files": 9,
  "test_nonblank": 501
}
```

Test timings (bench.json `test.run` on an empty cache): 16.7 s cold, 2.9 s warm,
3.1 s with `test.force`. The cold release build is 31-36 s (LLVM codegen about
20 s, LTO link about 10 s); a cold QBE or Debug build is about 20 s through the
harness, and about 5 s once the cache holds the runtime.

## Layout

One file per SPEC §2 module (`value.my` … `main.my`), all at the port root; the
project entry is `main.my`. Tests sit beside the modules as `<module>_test.my`
files (`scanner_test.my`, `lox_strings_test.my`, `table_test.my`,
`value_test.my`, `heap_test.my`, `compiler_test.my`, `parser_test.my`,
`resolver_test.my`) plus `driver_tests.my`, and each is a standalone test entry
that imports the module it tests.

How `mylang test` wants a project laid out, as far as this port needed:

- `mylang test <dir>` runs every root under the directory: each file with a
  top-level `main` and each standalone `*_test.my`. Library modules are not
  roots, so a `*_test.my` next to its module, importing it, is the natural shape.
- Only `public def test_*() -> bool` functions of the entry are discovered.
- A test may declare `out: Stream`; the runner supplies it. Any other parameter
  (a `Clock`, say) needs `arguments` from a `--cases` file, and a case file cannot
  make a capability.
- `--cases` is rejected for a directory run, and a directory run would try to
  build any `.my` file with a `main`. Hence `driver_tests.my` (not `_test.my`)
  runs in its own invocation, and the repros are stored as `*.my.txt`.
- Each test process has a 1,000,000-step budget. The driver tests need
  `--max-steps=100000000`: creating a Runtime alone (a 16,384-slot stack and 64
  frames) costs a large share of the default.

bench.json's `test.run` is therefore two commands:
`mylang test . …` then `mylang test driver_tests.my --cases driver_cases.json
--max-steps=100000000 …`.

## Representation choices

**Value** (`value.my`) is `union Value: nil, boolean: bool, number: float,
obj: ObjRef`, 16 bytes. `ObjRef` is `type ObjRef = int` (an object-table index);
"none" is the constant `NO_OBJ = -1`. Integers are i64 in mylang, so ObjRef is
64-bit rather than 32-bit; nothing depends on the width.

**Object table** (`heap.my`, `object.my`) is `list[Obj]`, with the payloads
stored inline in a union: `union Obj: free, string: StringObj, function:
FunctionObj, native, closure, upvalue, klass, instance, bound_method, env,
tree_function`. An `Obj` is 40 bytes (the tag, padded to 8, plus the largest
payload, `TreeFunctionObj` at 32). Payloads are `record`s (values) except the two that
change after allocation, `FunctionObj` (the compiler fills in arity, upvalue
count and name) and `UpvalueObj` (closing moves the value in), which are
`class`es, so the table slot and the compiler/VM share one mutable object. Other
mutable parts are reference types inside records: a `Table` is a class, and
`ClosureObj.upvalues`, `EnvObj.slots` and a chunk's lists are managed lists.
`StringObj` is `{chars: bytes, hash: u32}` (16 bytes). The mark bits live beside
the table in `Marker.marks: list[bool]`, with the gray stack; the free list is a
`list[int]` used as a stack. A table `Entry` is `{key: ObjRef, hash: u32, value:
Value}`, 32 bytes.

**Runtime** is a `class` passed as `rt: mut heap.Runtime`. It holds the value
stack (16,384 preallocated slots and `stack_top`), 64 preallocated `CallFrame`s
and `frame_count` (as clox does), the open-upvalue head, the compiling-function
roots, the tree engine's current env, saved envs and permanent roots, and the
clock capability as `Option[Clock]`. A `CallFrame` is a class holding the
closure ref plus its function, code list and upvalue list, which is what clox's
`frame->closure` and `frame->ip` pointers give it.

**Output** (`output.my`) is a class with two `byte_buffer`s and the two streams;
it is passed next to the Runtime (heap may not import output). stdout goes
through the 64 KiB buffer; each stderr line is one `stream.write`.

**AST** (`ast.my`): `union Expr` and `union Stmt` whose payloads are records,
held in the `Program`'s arrays `exprs: list[Expr]`, `stmts: list[Stmt]` and
`functions: list[FunctionDecl]`; children, bodies and method lists are indices.
An `Expr` is 112 bytes, a `Stmt` 88, a `Token` 40. The resolver writes its
annotations back with `program.exprs[id] = Expr.variable(replace(node,
hops=…, slot=…))`. A `TreeFunctionObj` names its declaration by index into
`Program.functions`. The first version used classes for nodes, which is what the
SPEC suggests for mylang; see friction item 2 for why it had to change.

**Opcodes** are `public const OP_…: int` in `chunk.my` and code is `list[int]`;
mylang has no integer `case`, so the dispatch loop is an `if`/`elif` chain.
**Token kinds** are an `enum` (`ast` re-exports it, so the interpreter can name
operators without importing `scanner`).

## Departures from the spec

1. **`strings` is `lox_strings.my`.** mylang's standard library owns the name
   `strings`, and a project module of that name is silently ignored in favour
   of the standard one (the import resolves and the first use reports
   `E_UNKNOWN_SYMBOL … did you mean find`).
2. **`run_source` takes the authority its code could use:**
   `run_source(source, engine, gc_stress, out: Stream, clock: Option[Clock])`.
   mylang's effect system charges every function with every effect it can
   reach, and the capture path reaches the stream writes and the clock read
   even though capture mode never takes those branches. The stream is held,
   never written; tests pass the runner's `out` and `None`.
3. **The driver tests run with a substituted `natives.my`.** A test cannot hold a
   `Clock`, so nothing that reaches `time.now` can be a test. `driver_cases.json`
   uses the runner's provider fixtures to replace `natives.my` with a copy whose
   `clock` returns 0 without a capability, for the eleven driver tests only. The
   real `clock` native is covered by conformance (`function/print.lox` prints
   it) but no test calls it. The fixture repeats natives.my's startup code, so a
   change to the startup order must be made in both places.
4. **`lox` is a shell wrapper.** A mylang executable consumes `--gc-stress`,
   `--print-result`, `--max-steps=`, `--max-frames=` and `--timeout=` from the
   arguments before the first `--`, and `--gc-stress` turns on mylang's own
   stress collector. bench.json therefore builds `lox-native` and installs
   `lox.sh` as `lox`, which runs `exec lox-native -- "$@"`. Measured runs pay one
   `/bin/sh` exec (about a millisecond). The build commands are `sh -c` so they
   can copy the wrapper.
5. **The clock is wall-clock time.** The only clock API is `time.now(clock)`
   (Unix nanoseconds); mylang exposes no monotonic or process clock.
6. **AST by index, and `TreeFunction.decl` is an index** (see Representation).
7. **Startup lives in `natives.start`**: it interns `init` (the Runtime root)
   and then defines `clock`. Heap cannot do it because heap may not import
   strings.

Things that are not departures but might look like it: `Output` travels beside
the Runtime rather than inside it (module order); `ast` re-exports
`scanner.TokenKind` and `scanner.Token`; the tree engine's global assignment
checks with `get` then `set` (jlox), where the VM does `set` then `delete`
(clox), which changes nothing observable.

## Spec questions I settled

- **Argument parsing.** Known flags in any order, then exactly one path. A
  `--`-prefixed argument that is not a known flag, a second path, or anything
  after the path prints the usage line and exits 64. Repeated flags are allowed.
- **When the parser interns.** "When it builds the node": a function's name and
  then its parameters are interned after its body is parsed; a `var`'s name
  after its initializer. Only strings that interning creates are appended to the
  permanent roots (clarification 3), detected by the allocation count changing.
- **Resolver scopes without hash maps.** A scope is a list of `(name, defined,
  slot)` searched linearly, keyed by the interned name ref; `this` and `super`
  use two reserved negative keys. A duplicate declaration keeps the first
  slot (it is an error, so nothing runs).
- **The desugared `for` with no condition** gets a `Literal(true)` built after
  the body, as in jlox.
- **Tree call depth.** `depth + 1 > 63` is `Stack overflow.`, counted in
  `enter_function` after the arity check, for plain calls and the unbound
  class-init call alike.
- **Initializer result.** Read from the call env's enclosing env, slot 0: that is
  `fn.closure` for a bound `init` and the this-env for the class call.
- **NUL bytes** in the source are `Unexpected character.` (the scanner ends at
  the byte length; clox stops at the first NUL).
- **A print longer than 64 KiB** flushes the buffer first and then appends the
  whole line (the buffer grows past 64 KiB for that one line).
- **The value stack** has no overflow check beyond the frame limit, as in clox;
  an overflow would trap on the list bound.

## Language and toolchain friction

1. **Effects are charged along every static path, and only a `Stream` reaches a
   test.** Capture mode had to take a `Stream` it never writes (departure 2),
   and the clock made the driver tests need provider fixtures, a second test
   invocation and a hand-copied `natives.my` (departure 3). Because those 27
   tests take `out: Stream`, the `output` effect makes them uncacheable: a warm
   `test.run` still executes 16 of the 52 directory tests and all 11 driver
   tests. A callback parameter did not help either: passing a pure function where
   a `def() -> float effects(clock)` is expected still charges the caller with
   `clock`.
2. **The mutation-overlap check is by type, and proving disjointness is
   exponential.** `evaluate(mut it, expr)` with class-based AST nodes produced
   `E_MUTATION_OVERLAP` while any `list[int]` appeared in both the interpreter
   state and the AST, and once the types were made disjoint `check-project`
   spun at 100% CPU for over two minutes without finishing
   (`repros/overlap_proof_blowup.my.txt`: two node classes and two heap classes
   with three fields each do not finish in 30 s; `typesMayAlias` in `src/origins.zig`
   remembers only the pairs on the current path). The fix was to rewrite the
   AST as index-addressed arrays so no call passes a node. The same rule forced
   smaller workarounds: the GC's mark state had to move into its own `Marker`
   class, because `mark_table(mut rt, rt.globals)` overlaps and
   `blacken(mut rt.marker, rt.objects[ref])` "may alias" through `list[int]`
   (a closure's upvalue refs versus the gray stack); `run_statements(mut it,
   statements: list[int])` and `new_block(mut p, statements)` were rejected
   the same way and became loops over indices read inside the function.
3. **Mutation tracking is inconsistent.** Writing through a class payload taken
   from `match rt.objects[i]` does not count as writing `rt`: in an early probe,
   a `close(rt: mut Runtime, i)` that only closed an upvalue held in `rt`'s
   table was rejected with "`rt` is declared `mut` but never written" (and
   `table.add_all(<table read from rt>, mut <table read from rt>)` is accepted,
   though both tables sit in the same heap). A class passed as a parameter is
   tracked, and the resolver's `E_MUTATION_MARKER` errors pointed at unrelated
   lines (`r.current_function = kind`) rather than at the writes.
4. **The QBE backend dies on a mid-sized dispatch loop.** The first VM `run`
   (all opcodes inline, 2.2 MB of IL) failed `--mode Debug` and `--backend
   qbe` builds with `vendor/qbe/rega.c: dying: no more pm slots`; LLVM built it.
   `repros/qbe_pm_slots.my.txt` reproduces it in 140 lines. The VM now calls
   one handler per complex opcode.
5. **The native runtime owns some argument spellings** (departure 4,
   `repros/runtime_flags.my.txt`).
6. **Small surface gaps, each worked around:** `counter.n += 1` on a class
   field is `E_ASSIGNMENT_TARGET`; `match` payload bindings are immutable, so
   `up.closed = v` needs `target = up` first; a local may not share a name with
   any top-level function (`function`, `statement` and `call` all collided,
   `E_SHADOWING`); a function-scoped local keeps one type, so `b` could not be
   a `Value` in one branch of the dispatch loop and a `float` in another; there
   is no `case 1:` on integers; `byte_buffer` has no `clear` or truncate, so a
   flush allocates a fresh 64 KiB buffer and `format_number` cannot drop `.0`
   in place (it does `str(x)`, then slices); there is no `unreachable`, so kind
   accessors return a dummy value after `assert False`.
7. **Misleading or wrong diagnostics and runtime output:** a method call on a
   capability stored in a field (`o.out.write(buf)`) is `E_COLLECTION_METHOD`
   with a list of collection methods; binding it to a local first works
   (`repros/stream_field_method.my.txt`). `out.print(x)` for a float whose
   positional form is over about 64 characters traps `InternalError`
   (`repros/print_long_float.my.txt`; `str(x)` is fine and is what the port
   uses). Printing a union whose payload is a class shows a garbage field, and
   with a larger object table segfaulted (`repros/print_union_class_payload.my.txt`).
   `fs.read_file` on a FIFO or `/dev/fd/N` answers "denied: outside the granted
   directories" with no `--restrict` in force, so `lox <(…)` does not work
   (`repros/read_fifo.my.txt`).
8. **What went well.** `str(float)` already renders the shortest round-trip
   digits positionally, so `format_number` is three lines; `parse_float_range`
   parses a NUMBER lexeme in place and rounded every halfway case I tried
   correctly; byte indexing keeps scanning allocation-free, `bytes.view` names a
   lexeme without copying it and `copy()` makes the one owned copy an interned
   string needs; unions, `replace(...)` and `?` made the
   jlox error unwinding direct. The index-based AST was not planned but reads
   cleanly.

The repros are stored as `*.my.txt` so that `mylang test .` does not pick them
up; copy one to `.my` to run it. Each file's header gives the command and the
output.

## Not done, on purpose

No performance work. Things a tuning pass could look at, all left alone: the
dispatch loop goes through a `CallFrame` class field for every byte; `push`,
`pop` and `peek` are calls (LLVM inlines them in release); every table lookup
first fetches the key's hash from the heap; `print` of a number allocates three
times; the tree engine copies a 112-byte `Expr` out of the node array per
evaluation.

## Re-pinned to main 26f16e90 (2026-09-23)

The port was written against a compiler built from `perf/schematic-integration`
(the call-site `mut` work plus the perf lanes). The benchmark now pins a ReleaseFast
build of `main` at 26f16e90, which carries the fixes for the bugs this port found
(see `repros/`). Changes made so the same design builds there:

- 1,024 call-site `mut` markers (`f(mut x)`) removed, plus 99 in the embedded
  `natives.my` fixture in `driver_cases.json`. `main` parses the marker but rejects it
  as not yet checked; parameter declarations (`x: mut T`) are unchanged.
- `Option.unwrap_or` (two NUMBER-lexeme parses) became a `match`; `.is_none()` in
  three tests became `is None`. `main` has no intrinsic `Option` methods.
- `lox.sh` is gone. A built executable now hands `main` its argv unchanged, so
  `lox --gc-stress` reaches the program, and bench.json builds `lox` directly.
- The `release-unchecked` profile is gone: `main` has no `--unchecked`.

Conformance (vm 246/246, tree 241/241, normal and gc-stress), all 63 unit tests and
the four-way `check` (78/78 runs identical to the Zig, Rust and Go ports, `--stats`
included) pass on the new compiler.
