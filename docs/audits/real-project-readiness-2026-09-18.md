# Real-project readiness audit — 2026-09-18

Question asked: is anything left to implement or simplify before rebuilding sections of
the EDA project (`../eda`, the `netlisp` tool) in mylang and comparing change time and
line counts against the Zig original, and what would make building a parser easier?

Method: five guest programs were written the way a Python programmer writes them first
and repaired until the compiler accepted them; every repair is recorded here. The
programs, their reference implementations and the input generator live in
[`experiments/readiness-probes-2026-09-18/`](../../experiments/readiness-probes-2026-09-18/README.md)
and every measurement below is reproducible from
[`real-project-readiness-2026-09-18-probes.json`](real-project-readiness-2026-09-18-probes.json).
The EDA tree was surveyed read-only to pick the port target. Compiler:
`zig-out/bin/mylang` built from the working tree at commit 23058a99 plus the uncommitted
`export NAME` → `public` migration (see §6).

## 1. Verdict

The language is usable for the port today: a three-module S-expression tokenizer and
parser with tests took 213 lines, type-checks in 0.04 s and runs its tests in 0.5 s
warm. Nothing found is a hard blocker. Six items should land first because each one
costs a port either a silent design detour or a rewrite, and they are cheap relative to
the experiment they protect:

1. **Fix the docs that contradict the compiler** (`print`, `export`, test example).
2. **Give `str[i]` an allocation-free path and add `ord`/`chr`** — a character-level
   parser over `str` is 12× slower than CPython today; the same code over `bytes` is 7× faster.
3. **Allow a union payload to close a type cycle** (or document `class` as the AST idiom).
4. **Structural `==` on records, unions, `Result` and `Option`** — otherwise every test
   assertion on a parser result is a four-line `match`.
5. **Let tests live in a subdirectory of a project.**
6. **Stop demanding `mutates(c)` on every function that takes a `class` parameter**, or the
   accepted D2 policy (warn, then error) turns a parser into annotation noise.

Everything else is ergonomics that the comparison will measure rather than something the
comparison needs.

## 2. What the EDA port target looks like

`../eda/src` is 546,081 lines of Zig; its whole design language is S-expressions. The
parser stack is small and isolated:

| File | Lines | Tests | Depends on |
| --- | ---: | ---: | --- |
| `src/sexpr/paren_span.zig` | 88 | 1 | `std` |
| `src/sexpr/tokenizer.zig` | 668 | 16 | `std`, `ast.zig` |
| `src/sexpr/ast.zig` | 152 | 1 | `std` |
| `src/sexpr/parser.zig` | 456 | 13 | `std`, `ast`, `tokenizer` |
| `src/sexpr/printer.zig` | 426 | 7 | `std`, `ast`, `infra/fs` |
| `src/leak_tests/sexpr.zig` | 226 | 11 | the above |

No closures, no `comptime`, no `anytype` outside the printer's writer parameters. The
tokenizer returns borrowed slices into the source and lexes SI-scaled values (`220k`,
`100nF`, `3.3V`) and dimension units; the parser is recursive descent with a depth cap of
10,000 and reports `ParseDiagnostic{span, message}` — a direct `Result[T, E]` analogue.
`ast.Node.Tag` is a recursive tagged union, which is the one construct that needs care
(§3.3). Second, differently shaped candidate: `src/gerber_verify.zig` (916 lines, 9 tests,
line-oriented, and it has an oracle in `export_gerber.zig`). The EDA repo has no mylang
code and no line-count or change-time metrics to compare against; both ledgers start empty.

Recommended order: `paren_span` → `tokenizer` → `ast` + `parser` → `printer`, 1,790 lines
with 49 tests, with round-trip through the printer and the existing `.sexp` corpus under
`../eda/stdlib` and `../eda/projects` as the oracle.

## 3. Findings, ranked

Each finding names the probe that produced it. "Repair" is what the first draft needed.

### 3.1 Documentation contradicts the compiler (blocks the first program)

- `CLAUDE.md` ("`print` contributes the `output` effect… an unbounded `def main() -> int`
  may print") and `docs/python-syntax.md` ("`print(values...)` writes its arguments") both
  describe bare `print`. The compiler rejects it: `E_OUTPUT_CAPABILITY: print needs a
  Stream; add out: Stream`. Only `docs/io.md` is current. An agent following the guide
  fails on its first program.
- `docs/modules.md` says "the separate `export NAME` directive is still accepted"; the
  working-tree parser rejects it with `E_EXPORT_REMOVED`.
- `examples/testing/main.my` writes every test as `-> bool effects():`. Copying that
  shape into a test that calls anything allocating fails with `E_EFFECT_BOUND` (probe
  `sexpr-str`, three errors). The example should drop `effects()`.
- `docs/tooling/guest-tests.md` does not say where test files may live in a multi-module
  project (§3.5).

Fix: one doc pass; `mylang doctest` does not catch these because the stale claims are
prose, not fenced examples.

### 3.2 `str` indexing allocates, so a character-level parser is slow

`str` is stored as UTF-32 and `text[i]` copies one scalar into a fresh heap object
(`src/native_text.c:73`, `myl_native_text_at` → `myl_native_text_copy`). Measured on a
1,287,988-byte KiCad-like file with 247,008 nodes (`gen_big.py`):

| Program | mylang native binary | CPython 3.14 |
| --- | ---: | ---: |
| character-level parser over `str` (`sexpr-str`) | 3.65 s | 0.31 s |
| same parser, `list[str]` + `join` for string literals | 3.72 s | — |
| same parser over `bytes` (`sexpr-bytes`) | 0.48 s | — |
| token-list parser over `bytes` (`proj`) | 0.33 s | 0.26 s |
| micro: index every scalar of the file once | 0.32 s | 0.021 s |
| micro: iterate the file with `for ch in src` | 0.38 s | — |
| micro: 200,000 single-character `acc = acc + ch` | 3.76 s | 0.35 s |
| micro: compare an 8-character slice at every offset | 0.42 s | — |

The `bytes` route is the intended one (`src/stdlib/json.my` uses it) but nothing in the
guide says so, `bytes` has no `isdigit`/`isalpha`, and turning a lexeme back into text is
`src[a:b].decode()` returning a `Result` that must be matched. There is no `ord` or `chr`;
`s.encode()[i]` is the only way to get a code point, and `chr` is a table lookup.

Fix, in order of leverage: (a) keep 128 immortal one-scalar strings for ASCII so `s[i]`,
iteration and `enumerate` over ASCII text never allocate; (b) add `ord(s)` and `chr(i)`;
(c) add `isdigit`/`isalpha`/`isspace` on a byte `int` or on `bytes`. A string builder
(`strings.Builder` or an amortised `+=` on a uniquely referenced string) is the fix for the
append row; the `list[str]` + `join` idiom is documented in `selfhost/prototype/api_report.md`
but not in the user docs. Note that even the good case is not faster than CPython: the
native pitch should not be assumed in the comparison.

### 3.3 A record → union → record cycle is rejected

`record Binary: left: Expr; right: Expr` with `union Expr: binary: Binary` fails with
`E_RECURSIVE_RECORD: type fields must form a finite by-value layout` (probe `expr`). A
recursive union through a `list[Node]` works (probe `sexpr-str`), and the repair is to make
the payload a `class`, after which mutual recursion, `?` propagation and exhaustive `match`
all work. The repair is not documented anywhere; the EDA `ast.Node.Tag` port and any
typed AST with binary nodes hits this on day one.

Fix: either box a union payload that closes a cycle automatically (the variant already
carries a tag; storing that payload by reference is invisible to the guest) or state
"use `class` for recursive payloads" in `docs/records-and-unions.md` with an example.

### 3.4 No structural equality on aggregates

`P(1, 2) == P(1, 2)`, `N.a("x") == N.a("x")`, `C(n=1) == C(n=1)` (class), `f() == want`
for `Result` and `v == None` for `Option` all fail with `E_TYPE: aggregate equality is not
defined`. `docs/python-syntax.md` says records are values, and the feature list carries
`collection-membership-and-value-equality`, so this is surprising. For a parser it means
`assert parse(x) == Ok(expected)` is impossible; probe `expr` needed two helper
functions and probe `proj` compares rendered strings instead. `print`, f-strings and
`assert` already render aggregates structurally, so the traversal exists.

Fix: structural `==`/`!=` on `record`, `union`, `enum`, `Result` and `Option`, and on
`class` per the recorded 2026-09-17 aliasing decision (structural, cycle-safe).

### 3.5 Tests cannot live in a subdirectory of a project

Probe `proj` tried `tests/parser_test.my`: with `module tests.parser_test` the runner
reports `E_MODULE_NAME` for both `mylang test tests` and `mylang test .`; with
`module parser_test`, `import sexpr.parser` resolves relative to `tests/` and fails
with `E_MODULE_READ`. The only working layout is `parser_test.my` beside `main.my` at the
project root. Both failures end with `mylang: host failure: NativeToolFailed`, which reads
as a tool crash rather than a layout error. The EDA port will want `tests/` from the start.

Fix: resolve a `*_test.my` root's module name and imports from the enclosing project root
(the nearest ancestor holding `mylang.json` or the entry's directory), and replace the
`NativeToolFailed` line with the diagnostic alone.

### 3.6 `mutates(c)` on every parser function

A parser's cursor is a `class` (the documented reference type), and every function that
advances it gets `W_MUTATES_MISSING` — six warnings in the 130-line `sexpr-str` probe,
printed twice per `mylang run` (once by the check, once by the build). The accepted D2
policy promotes this to an error. Writing through a reference-typed parameter is the
purpose of `class`; requiring the annotation there yields no information.

Fix: exempt `class` parameters from the mandatory footprint (infer and display in
`list-interfaces`, as the quality audit's P-policy already prescribes), and print each
diagnostic once per command.

### 3.7 Parser ergonomics that cost lines rather than designs

| Gap | Probe evidence | Cheapest fix |
| --- | --- | --- |
| `union` variants are comma-separated, unlike `record` fields; writing them like fields gives `E_SYNTAX: expected a dedent` | `sexpr-str`, first compile | accept newline-separated variants, or name the fix in the diagnostic |
| `match` has no literal patterns and is a statement; no ternary | `case "(":` → `E_SYNTAX: expected a name`; `x = 1 if c else 2` → `E_SYNTAX` | literal `str`/`int` patterns in `case` |
| `?` on an `Option` inside a `Result` function is `E_TRY_RETURN` | `v = int(t)?` in `-> Result[int, str]` | `?` with the `Option` → declared error conversion, or `.ok_or(err)` |
| no module-level `dict`/`list` constants | `const KEYWORDS: dict[str, int] = {...}` → `E_CONSTANT_EXPRESSION` | frozen literal collections in `const` |
| standalone call whose value is unused needs `_ =` | `bump(p)` → `E_EXPLICIT_DISCARD_REQUIRED` | keep; the fix text is clear |
| `Ok(...)`/`Err(...)` need a typed context | `x == Err("...")` → `E_RESULT_INFERENCE` | falls out of §3.4 |
| `str(record)` rejected while `f"{record}"` renders it; `"a" < "b"` rejected | `E_TEXT_CONVERSION`, `E_TEXT_OPERATOR` | allow both; `sorted` already orders `str` |
| f-string `assert` message is lost under `mylang test` (`R_ASSERT` alone) and printed as a stray stdout line under `run`; a literal message works | `tfail` probe | route the rendered message through the trap detail |
| `fmt` does not auto-detect module files (`check`/`run` do); `fmt-module` is needed, and it emits `-> Result[Node, ParseError]mutates(s)` without the space | `proj` | auto-detect in `fmt`; add the space |
| `L_UNTESTED_EXPORT` and `list-interfaces` `tests(0)` miss tests that call an export from another module | `proj`: `parse` is called by three tests | count cross-module calls |
| `check` can print the same error twice | `E_TYPE` on `read_text` printed twice | dedupe by position |

### 3.8 Things that worked first time and should stay

Recursive `union` through `list`, exhaustive `match` with payload binding, `?` on
`Result` across mutual recursion, `enum` with `match`, `class` as a cursor, `bytes`
indexing/slicing, `with open(fs, path, "rb")`, `list` `pop`/`insert`/`sort`,
`dict.items()`, comprehensions, f-strings, `--filter`, receipts (`0 cached` still shows
because each rerun re-executes; warm cost is 0.5 s for 4 tests across 2 programs),
`list-interfaces` showing inferred effects. Edit loop on `proj` (213 lines, 3 modules):
`check` 0.036 s, cold `test .` 1.24 s, unchanged rerun 0.51 s, rerun after a tokenizer
edit 0.57 s. `check` on the 14-module, 2,186-line schematic guest is 0.013 s warm.
`E_MUTATION_OVERLAP` on two same-typed list parameters no longer fires.

## 4. Simplifications worth doing before the port

- Finish and commit the `export NAME` removal (in flight, §6) and update `docs/modules.md`.
- Fold `fmt-module`/`fmt-project` into `fmt` the way `run` absorbed `run-project`.
- Drop `effects()` from `examples/testing/main.my` and every doc example that only needs it
  for show; exported functions no longer need a ceiling.
- The 2026-09-14 lexer keyword deletions (`f64_*`, `codec_*`, resource tier) are still in
  `src/lexer.zig` (96 keywords). Not a port blocker, but each is a name an agent can trip on.
- Print each warning once per `run`.

## 5. Running the comparison

- Port the sexpr stack (§2) as one mylang project with `tests` at the root until §3.5 lands.
  Keep the tokenizer over `bytes` with `(start, end)` offsets and a `lexeme()` decoder; the
  Zig version's borrowed slices have no free equivalent.
- Oracle: `netlisp` round-trip through `src/sexpr/printer.zig` on every `.sexp` under
  `../eda/stdlib` and `../eda/projects`, plus the 49 existing Zig tests transcribed.
- Record per accepted change: wall-clock, compiler rejections before green, lines
  touched, test count; keep the compiler-fix ledger separate from the application ledger as
  `docs/experiments/application-comparison.md` §1 requires. Line counts for the probes
  here: `sexpr-str` 200 lines for a parser + 3 tests, `proj` 213 lines for tokenizer +
  parser + 4 tests + CLI; the Zig originals are 1,790 lines partly because of allocator
  and `errdefer` plumbing, which is a real difference and should be reported as such.
- Do not read the timing rows in §3.2 as a performance verdict on the backend; they
  measure one runtime representation choice (UTF-32 `str` with per-index allocation).

## 6. State of the tree when this was written

39 tracked files are modified and uncommitted: the `export NAME` → `public` migration
(`src/parser.zig` adds `E_EXPORT_REMOVED`, `src/doc_coverage.zig` and
`src/input_manifest.zig` follow, and 35 test files are rewritten), and `src/stdlib/*.my`
were being edited by another session while this audit ran. `zig build` succeeds; the full
gate was not run against the moving tree. Commit that migration, run the gate, and start
the port from a green commit. The probes in `experiments/readiness-probes-2026-09-18/`
pass against this build (`sexpr-str` 3/3, `expr` 3/3, `proj` 4/4).
