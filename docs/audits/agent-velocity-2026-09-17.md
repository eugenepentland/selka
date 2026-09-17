# Agent development-velocity audit — 17 September 2026

**Question asked:** what should be added to, removed from, or changed in the language and
its tooling so that an AI agent gets from a task to a correct program in the fewest turns,
on a large codebase, with the default path as simple as possible and performance available
as an opt-in escape hatch.

**Method.** Nothing in the implementation was changed and no gate was run. Every claim
below is either a source citation or a probe executed against the installed
`zig-out/bin/mylang` (compiler identity `d7bf295b7f028d62…`, working tree at `bcd0c652`
plus uncommitted edits) on 17 September 2026. The probes are 110 small programs written
the way an agent writes Python on the first try, one 60-line "realistic" program iterated
to green, one three-module project exercised through `run`, `check`, `test` and directory
runs, and two delegated probe sets (effects/mutation ceremony; tooling latency and
diagnostics). Sources, exit codes and diagnostics for the 110 idiom probes are in
[`agent-velocity-2026-09-17-probes.json`](agent-velocity-2026-09-17-probes.json); the
appendix lists them. Prior audits ([14 Sep](language-simplicity-2026-09-14.md),
[15 Sep](interfaces-and-agent-development-2026-09-15.md)) are not repeated except where
a recommendation is still open.

## Verdict

Inside a function body, over lists, dictionaries, strings and records, the language is
already close to statically typed Python and compiles fast. Of the 110 idiom probes,
**31 compiled and ran; 79 did not**, and the failures cluster into four groups that are
worth different amounts of attention:

1. **Silent wrong answers (three of them).** A Python-shaped program compiles, runs, and
   computes the wrong thing with no diagnostic. These cost the most turns of anything in
   this audit, because the agent has no signal to repair from. Fix these first.
2. **Ceremony that the checker could infer.** Exported functions and tests must carry
   `effects(...)` ceilings, string literals count as allocation, two-list helpers trip an
   overlap check with no annotation anywhere, callbacks need ceilings on both sides,
   every file that imports needs a `module` header that matches its path, and every
   public name needs an `export` line. Each of these is one extra turn per occurrence and
   none of them prevents a mistake an agent is likely to make.
3. **Python expression syntax that is missing.** Conditional expressions, tuples and
   destructuring, chained comparisons, `**`, bit operators, docstrings, module-level
   constants, f-string format specs, `round(x, n)`, `split()`, `set`, match on literals,
   nested comprehensions and generator arguments. Each is cheap; together they are most of
   the 79 failures.
4. **Tooling seams on large projects.** `mylang test` breaks on `print` inside a test,
   cannot run a library module as a test entry, and misreports nested modules in directory
   runs; `check` does not accept a project file that `run` accepts; a 10-million-step
   budget stops honest programs after ~18 ms of work; the module count is capped at 256;
   a one-line edit costs about 300 ms of fixed overhead however small the change, and
   no diagnostic ever suggests a candidate name.

The escape hatches (ReleaseFast default, `noalloc`, arenas, `extern def`) are honest and
documented, but thin: the fastest storage is still `list[T]`, `[N]T` is O(N) per access,
and C cannot see guest data.

## 1. Silent wrong answers — fix before anything else

### 1.1 Writes through a record copy are silently dropped

Records are values. A Python programmer reads `for it in items: it.visited = True` as
mutation of the objects in the list; here it mutates a copy and the list is untouched.
All three shapes an agent will write compile cleanly and do nothing:

```text
for it in items: it.visited = True        # d01: prints "visited: 0"
node = nodes[0]; node.value = 42          # d02: nodes[0].value is still 1
a = accounts["a"]; a.total = 42           # d06: accounts["a"].total is still 0
def bump(c: Counter): c.n = c.n + 1       # effects probe p2c: caller's c unchanged
```

`items[0].n += 0` and `c.n += 1` are rejected (`E_ASSIGNMENT_TARGET`), so the augmented
form is caught but the plain form is not. The 14 September audit noted the
`layout_graph.my` workaround (index loops) as "authorial"; it is not — three loops in that
file exist *because* `for item in nets: item.group = 9` has no effect.

**Recommendation.** Two levels:

- *Minimum (small):* a warning, `W_DEAD_RECORD_WRITE`, when a field of a record local
  that came from a collection read, a loop variable or a by-value parameter is written and
  the local is never read afterwards. The checker already has definite-assignment
  analysis and knows the origin of each local.
- *Real fix (design):* give the language a reference-typed aggregate. `class` is accepted
  today as a "compatibility spelling" of `record` — a Python `class` with the opposite
  aliasing semantics from Python is the most dangerous spelling in the language. Make
  `class` a GC-managed reference type (like `list` and `dict` already are), keep
  `record` as the value type, and let `class` carry methods (§3.5). Python programmers
  then get what they expect by default, and `record` becomes the explicit, documented
  escape hatch for value semantics and arena-free scalars.

### 1.2 `dict.items()` yields `(position, value)`, not `(key, value)`

```text
d = {10: 100, 20: 200}
for k, v in d.items(): total += k + v     # a20: 301, Python gives 330
```

This is documented (`docs/managed-memory.md:203`) and deliberate, and it was flagged as a
design defect on 15 September. It is still there. With integer keys the program is
type-correct and wrong. `enumerate` is already special-cased as a two-name iteration
source; `items()` should use the same mechanism to bind the key. Do this even if tuples
(§3.2) are deferred.

### 1.3 `round` rounds halves away from zero

`round(2.5)` is `3.0` (Python: `2`), `round(0.5)` is `1.0`. Low impact; document it in the
compatibility list or rename the operation.

## 2. Ceremony the checker could infer

### 2.1 Exported functions and tests require an explicit effect ceiling

Every exported function in a project, and every `test_` function, rejects until it
carries `effects(...)`, `noalloc` or `noio`:

```text
shared/geometry.my:13:5: error[E_EFFECT_CEILING]: exported function requires an explicit
effect ceiling; the body's compiler-derived bound is effects()
```

The compiler prints the bound it derived and then refuses to use it. This rule landed on
15 September (`5848f636`, "velocity(e2)") so that the declared ceiling can serve as the
public-API fingerprint for incremental identities. It appears in no user-facing page —
`docs/effects.md` still says "an omitted annotation imposes no bound" — and it is the first
error an agent meets on any multi-file project (three errors on a three-module probe).
The standard library shows the cost: 134 of its 189 functions carry an annotation, 65 of
them the near-meaningless `effects(managed_allocation)`.

**Recommendation.** Freeze the *inferred* ceiling in the fingerprint instead of requiring
the user to type it. The incremental system needs a stable public signature; it does not
need the author to spell it. Keep explicit ceilings as an opt-in narrowing (`noalloc`,
`noio`, `effects(output)`) and, if a project wants the stricter rule, make it a
`mylang.json` policy rather than the default. Until then, document the rule on
`docs/effects.md` and `docs/modules.md`.

### 2.2 String literals count as `managed_allocation`

```text
# doc: not-mylang
def main() -> int effects(output):
    print("hi")
error[E_EFFECT_BOUND]: effect `managed_allocation` exceeds declared bound: main;
inferred bound is effects(managed_allocation, output)
```

`print(42)` passes; `print("hi")` does not. `return "x"` under `effects()` and
`len("abc")` under `noalloc` fail the same way. CLAUDE.md's advice ("write
`effects(output)` on any function that prints") is wrong for the first program that
prints text. Intern literals (they are immutable and known at compile time) so a literal
is not an allocation, or exclude literals from the effect. This also removes most of the
65 `effects(managed_allocation)` annotations in the stdlib.

### 2.3 Mutation overlap fires on code with no annotation anywhere

```text
def merge(dst: list[int], src: list[int]):
    for v in src:
        dst.append(v)

def combine(a: list[int], b: list[int]):
    merge(a, b)
error[E_MUTATION_OVERLAP]: writable argument may alias an argument promised read-only;
pass a fresh snapshot, make both inputs writable, or split the call
```

Forwarding two same-typed collections through any helper rejects, whether or not the
helper is annotated (probes q12, r1, r9, q11, q13 in the effects set). The definitely
aliased call the documentation says is rejected — `touch(values, values)` from `main` —
is accepted (p5c, q7, r4, r5), so the rule keys on "origin is a parameter", not on
aliasing. Of the suggested repairs, `mutates(a, b)` on the caller does not work, `.copy()`
costs an allocation, and `mutates(dst, src)` on the callee is a false declaration.

**Recommendation.** Apply the overlap check only where a `mutates(...)` contract is
declared, and only when aliasing is possible by the documented rule. Unannotated code
should behave like Python: sequential, shared, no proof obligation.

### 2.4 Callbacks need ceilings on both the slot and the value

`f: def(int) -> int` rejects (`E_CALLBACK_EFFECTS: callback types require an explicit
effects ceiling`); once the slot says `effects()`, passing a plain `def double(v: int)
-> int` rejects again (`function values require a declared effect ceiling`). Two turns
before `apply(double, 21)` works, and 34 of the 42 `effects(...)` in `examples/` exist
only for this. `sorted(ps, key=score)` has the same cost (a27). The checker infers every
function's effect set already; let an unannotated function fill any slot whose ceiling
covers its inferred set, and let an unannotated slot default to unbounded.

### 2.5 Module headers, export lists and test discovery

| What an agent writes | What happens |
| --- | --- |
| `import math` at the top of a plain file | `E_MODULE_HEADER: file must begin with a module declaration` |
| `module main` in `report.my` | `E_MODULE_NAME: declared module name does not match its requested path` |
| `mylang check main.my` on a project entry | `E_SYNTAX: expected def` (only `check-project` accepts it; `run` auto-detects) |
| `def test_x() -> bool:` without `export test_x` | silently not discovered: `0 passed`, exit 3 |
| `export test_x` without `effects()` | `E_EFFECT_CEILING` |
| `from inventory import Item` | `E_SYNTAX: expected def` |

The header carries no information the path does not already carry. Derive the module name
from the file path and make the header optional; make `check` detect a project entry the
way `run` does; discover `test_` functions without `export`; and reject `from x import y`
with a message that names the `import x` + `x.y` spelling. On exports, either export by
default with a leading-underscore convention (Python's rule) or accept a `pub def`-style
prefix on the declaration — the 14 September audit counted 242 directive lines in the
corpus, and that number has only grown.

## 3. Python syntax that fails on the first try

The table lists what an agent writes, the current diagnostic, and the recommended action.
"Add" means implement the Python meaning; "message" means keep rejecting but say what to
write instead, because today's message is a parser fallback that names neither the feature
nor the alternative.

| Idiom | Probe | Today | Action |
| --- | --- | --- | --- |
| `y = 42 if x > 0 else 0` | a01, a70 | `E_SYNTAX: expected a newline` | **Add** |
| `0 < x < 10` | a02 | `E_TYPE: expected bool, found i64` | **Add** |
| `a, b = b, a`; `return q, r`; `q, r = divmod(...)` | a03, a04, a56 | `E_SYNTAX: expected a newline` | **Add tuples** (§3.2) |
| `if r is None:` on an `Option` | a05 | `E_SYNTAX: expected an indented block` | **Add** with narrowing (§3.3) |
| `r == None` | a06 | `expected Option<i64>, found unit` | message (and render `Option[int]`) |
| `"""docstring"""` at module or function level | a12 | `E_SYNTAX: expected def` | **Add** (no-op statement) |
| `MAX = 42` at module level | a37 | `E_SYNTAX: expected def` | **Add** as `const` sugar |
| `f"{x:.2f}"`, `round(x, 2)` | a16, a33 | clear messages, no alternative in the file | **Add** format specs; today the only route is `module` + `import strings` + `Result` |
| `2 ** 5` | a34 | `E_EXPRESSION: expected an expression` | **Add** |
| `a & b`, `a \| b`, `1 << 4`, `~x` | a54, e02, e03 | `&` "was removed and has no replacement" (it has: `bit_and`); `\|` is an "unexpected character" | **Add** the operators; the named forms already exist |
| `set[int]`, `{1, 2, 3}` | a21, a22 | `E_UNKNOWN_TYPE` / `E_SYNTAX: expected :` | **Add** `set[T]` (a dict without values) |
| `"ab" * 3`, `"a" < "b"` | a19, a65 | `E_TYPE` / `E_TEXT_OPERATOR` | **Add** |
| `s.split()` (whitespace), `s.title()` | a64, a79 | `E_ARITY` / unknown method | **Add** the zero-argument split; list the known methods in the message |
| `ps.sort(key=...)`, `sorted(xs, reverse=True)`, `range(a, b, step)`, `enumerate(xs, start=1)` | a26, a28, a30, a44 | mostly clear messages | **Add** |
| `chr`, `ord`, `hex`, `divmod`, `pow` | a55, a56 | `E_UNKNOWN_FUNCTION` | **Add** |
| `match x: case 1:` / `case "a":` | a49, a50 | `E_SYNTAX: expected a name` | **Add** literal patterns |
| `del xs[0]`, `del d[k]` | a51 | `E_SYNTAX` | **Add** (or message naming `pop`) |
| `[x for row in g for x in row]`, `{k: v for ...}`, `any(x > 2 for x in xs)`, `sum(x*x for x in xs)` | a66–a68 | `E_SYNTAX: expected ]` / `}` / `)` | **Add** nested generators and generator arguments to `any`/`all`/`sum`/`min`/`max`/`sorted` |
| `"""multi\nline"""`, `r"raw"` | a53 | `E_BYTE_LITERAL: unterminated byte literal` (it is not a byte literal) | **Add**; fix the message either way |
| `assert x == 2, f"got {x}"` | a57 | `E_SYNTAX: expected a string` | **Add** any `str` expression |
| `record` field defaults `retries: int = 3` | a45 | `E_SYNTAX: expected a dedent` | **Add** |
| `P(1, 2) == P(1, 2)` | a46 | clear message | **Add** fieldwise equality for records whose fields all support it |
| `str(record)` | a47 | `E_TEXT_CONVERSION` although `print(p)` and `f"{p}"` render it | **Add** (one renderer) |
| `x = y = 21` | a10 | `E_SYNTAX` | Add or message |
| `int \| None`, `Optional[int]` | a23, a24 | `E_TOKEN` / `E_SYNTAX` | message naming `Option[int]` |
| `v = parse(s)?` where error types differ | c02 | `expected i64, found str` | message: "error payloads differ; translate the error first" |
| `if not xs:`, `if n:` | a11 | `expected bool, found List<i64>` | keep; render `list[int]` |
| `try/except`, `raise` | a40 | `E_SYNTAX: expected a newline` | message: "no exceptions; return `Result`" |
| `class` with `__init__`/methods | a38 | `E_SYNTAX: expected a name` | see §3.5 |
| nested `def`, capturing `lambda`, `global`, walrus, `for/else`, `%`/`.format`, `if __name__` | a13, a14, a36, a73, a48, a17, a18, a58 | parser fallbacks | keep rejecting; each message should name the feature and the alternative |

Everything marked "Add" already has a total, side-effect-free meaning; none needs new
runtime machinery except `set[T]` and tuples.

### 3.1 The realistic-program measurement

A 60-line program (parse a comma-separated order file with a `Filesystem`, aggregate
totals per customer into a `dict`, print a sorted report with cents formatted as
dollars) written once in the documented style needed **one repair round**: `read_text`
returns `Result[str, str]`, and the diagnostic for `text.splitlines()` on the unmatched
result was `E_UNKNOWN_TYPE: type is not declared` — it named neither the `Result` nor the
`?` that fixes it. The corrected program ran first time. Three nested `match` blocks were
needed to parse three integers because `int(text)` returns `Option[int]` and `?` on an
`Option` requires an `Option`-returning function; a `Result`-returning parse function
cannot use it. `parts = line.split(",")`, `totals.get(k, 0) + n`, `sorted(d.keys())`,
f-strings and `//`/`%` all matched Python exactly.

### 3.2 Tuples

Five of the 79 failures are tuples (swap, multi-value return, `divmod`, destructuring,
and the `items()` wart of §1.2). The 14 September audit deferred tuples as a design
project. This audit recommends adding them in their smallest form: fixed-arity immutable
values `tuple[int, str]`, constructed by `a, b` and taken apart by destructuring
assignment and `for k, v in ...`. No indexing, slicing or methods are needed on day one.
This one feature removes a record declaration from every function that returns two
values and gives `items()` and `zip` their Python meaning.

### 3.3 `is None` and narrowing

Agents write `if x is None: return default` and then use `x` as a `T`. The checker
already has flow-sensitive definite assignment; narrowing `Option[T]` to `T` on the
`is not None` branch is the same analysis. Cheaper alternatives that still remove the
four-line `match`: `x.unwrap_or(default)` and `x.is_none()`.

### 3.4 Number formatting

`f"{x:.2f}"` is the way every Python programmer rounds for display. Today the route is:
add a `module` header that matches the file name, `import strings`, call
`strings.format_float(x, 2)` and match a `Result[str, str]` — three tiers for one
operation. Support `.Nf`, width and alignment specs in f-strings, and `round(x, n)`.

### 3.5 Methods on records

`class Point: def __init__ ... def norm1(self)` is the first thing an agent writes for a
data type with behaviour (a38). The language already has type-scoped functions for
`domain` and calls them as `Type.name(value)`. Allow `def name(self, ...)` inside a
`record`/`class` body as sugar for a top-level function whose first parameter is the
receiver, called as `value.name(...)`. No inheritance, no dynamic dispatch, no `self`
outside the body. This resolves the 14 September audit's open decision (§2.5 there) and
the `store.get(key)` failure of 15 September at once.

## 4. Diagnostics that point the wrong way

Beyond the parser fallbacks in §3, four messages actively mislead:

- `text.splitlines()` on a `Result[str, str]` local: `E_UNKNOWN_TYPE: type is not
  declared` (the local is being read as a module path).
- `d.get("b")` on a dictionary: `E_ARITY: list method argument count does not match its
  signature`.
- `"""text"""`: `E_BYTE_LITERAL: unterminated byte literal`.
- `a & b`: `E_REMOVED_SPELLING: \`&\` was removed and has no replacement`, while
  `bit_and` exists and is documented.

Type names in messages use the internal spelling (`Option<i64>`, `List<i64>`,
`def(i64)->i64 effects(0)`) rather than the surface one (`Option[int]`, `list[int]`).
An agent that copies a diagnostic's type into source produces a second error.

An unknown or malformed command-line flag prints the entire usage block with no line
naming the flag; `run` accepts only `--cache-dir=DIR` while `test` accepts
`--cache-dir DIR`. A check failure inside `mylang test` is wrapped as
`mylang: host failure: NativeToolFailed` and exits 2, so the runner cannot be told apart
from a broken toolchain.

## 5. Large-codebase seams

### 5.1 Tests

- **`print` inside a test aborts the run** with `mylang: host failure:
  InvalidNativeTestResponse` (exit 2). The child's stdout is the runner's protocol
  channel. `eprint` works. A debug print is the first thing an agent adds to a failing
  test; this must not take down the runner.
- **A failing boolean test reports `actual value does not match expected value`** with
  no values and no line; a failing `assert` reports `R_ASSERT` and a location but drops
  the message (`"x should be two"` never appears). Show the assertion text or message
  and, for typed expectations, both values.
- **Only an entry with `main` can be a test entry.** `mylang test inventory.my` on a
  library module: `E_MAIN: the program requires an entry point`. Tests therefore cannot
  live beside the module they test unless that module has a `main`, and there is no
  `*_test.my` convention.
- **Directory runs treat every `.my` file as a program.** On the three-module probe
  `mylang test .` reported `E_MODULE_NAME` for `shared/geometry.my` (loaded relative to
  its own directory) and `E_MAIN` for the library module, then `0 passed … across 3
  programs`. A directory run should discover project roots, not files.
- Tests need `export` and an explicit ceiling (§2.1, §2.5) before any of the above.

### 5.2 Budgets stop honest programs

`mylang run` bounds every program to 10,000,000 instructions and 1,024 frames. A
2,000,000-iteration loop (`e01`) traps `R_STEP_LIMIT` at roughly 660,000 iterations,
after about 18 ms of work, and a 5,000-deep recursion (`e07`) traps `R_FRAME_LIMIT`. The
messages name the flag, which helps, but the default is wrong for a development loop:
a program that parses a one-megabyte input will trip it, and the agent then learns to
paste `--max-steps=4000000000` everywhere. The memory ceiling already contains a runaway
allocation. Make `run`, `build --run` and built binaries unbounded by default, keep a
wall-clock `--timeout`, and keep the instruction budget for `mylang test` where it is a
useful guard.

### 5.3 Hard caps

`src/project.zig:36` caps a project at 256 modules, 4,096 import edges, 4 MiB per file
and 16 MiB of source. The schematic application is 14 modules; a large codebase is not.
Raise the module cap by an order of magnitude or remove it, and make the limits a
`mylang.json` setting.

### 5.4 The edit loop, measured

Measured on a copy of the 14-module, 2,186-line schematic guest with a fresh cache
directory. The machine's load average was 12 to 32 during the runs, so ranges are
reported; the ordering was stable across passes.

| Step | Wall time |
| --- | --- |
| `check-project` cold | 460–635 ms |
| `check-project` warm, unchanged | 95–170 ms |
| one-line body edit in `layout.my` | 230–415 ms (work report: 1 body checked, 113 reused) |
| new function added to `text.my` | 295–405 ms |
| signature change used by three modules | 266–336 ms |
| project with a type error, rerun unchanged | 226–294 ms every time |
| `check-session` in-process: unchanged / body edit / with error | 47–58 / 295–343 / 447 ms |
| `check` on a 20-line file, cold or warm | 25–39 ms |
| `run examples/factorial.my` cold / warm | 262–381 / 30–43 ms |
| `test examples/testing` cold / warm / one-line edit | 606–1,033 / 58–129 / 478–709 ms |

Reuse works — 113 of 114 bodies are reused after a one-line edit — but a fixed
per-invocation cost of roughly 300 ms (source load, dependency-key preparation,
retention-store I/O) makes every edit → check round the same price regardless of edit
size, and an edit → test round on a two-test project costs half a second or more.
While the project is red, nothing is reused: a failing verdict is never cached, which
is exactly the state an agent iterates in. Target a one-line edit under 100 ms, cache
failing verdicts, and expose `check-session` as a watch mode.

Other findings from the same probe:

- **No "did you mean" anywhere.** `E_UNKNOWN_FUNCTION` and `E_UNKNOWN_NAME` offer no
  candidate; `E_UNKNOWN_FIELD` names neither the record type nor its fields;
  `E_UNKNOWN_SYMBOL` does not list the module's exports; `E_LIST_METHOD` is the same
  code for `str`, `list` and `dict` and lists no methods; `E_ARITY` gives no
  expected/got counts. Only the first error per function is reported. There are 209
  distinct diagnostic codes and no catalogue page or `explain` command.
- **`--help` per subcommand exists only for `build` and `test`.** `run --help` dumps
  the usage and exits 2, an unknown subcommand is not named, and the usage opens with
  `test` and `bench-promote` rather than `run` and `check`.
- **`mylang fmt` cannot write.** It reformats correctly and preserves comments, but
  writes only to stdout, `fmt-project` only checks, and 13 of the 14 shipped schematic
  modules fail `fmt-project --check` because the formatter joins multi-line constructor
  calls into 170-character lines. An agent cannot format the repo's own code without a
  13-file diff.
- `--diagnostics=json` works for `check` and `check-project` and is rejected by `test`.
- **Imports resolve only beneath the entry file's directory.** A sibling `lib/` is
  `E_MODULE_READ: … NotFound`, and `mylang.json` configures only the import-direction
  policy — no source paths, no dependencies. A second-party package goes through
  `scripts/packages.py` (Python), which snapshots per invocation and does not support
  `mylang test`, so a dependent project cannot test against a locked package.
- No LSP, no watch mode, no `mylang init`, no `mylang explain`. `dump-bytecode` still
  exists although there is no bytecode runtime. Entry filenames must be identifiers.

## 6. What to remove or hide

The 14 September audit's deletion list was accepted in the simplification plan but has
not been executed: the lexer's keyword table still reserves every spelling that audit
listed for deletion, including the 15 `f64_*` words, `__float_sqrt`, `filesystem_cap`/`clock_cap`/`random_cap`/`environment_cap`/
`network_cap`, `codec_encode`/`codec_decode`, `acquire_resource`/`complete_resource`/
`restrict_resource`/`read_resource`/`write_resource`, `environment_get`, `clock_now`,
`random_u64`, `wrap`/`unwrap`/`private`/`domain` (`src/lexer.zig:160–255`). Top-level
declaration forms number fifteen (`module`, `import`, `export`, `const`, `type`,
`record`/`class`, `union`, `enum`, `domain`, `def`, `host def`, `extern def`, `codec`,
`result`, `constraint`). An agent reading the grammar has to decide which half is for
it.

Recommended removals or demotions, in order of how much surface they retire:

1. The `f64_*` family, `__float_sqrt` and the `*_cap` spellings (zero uses; Python
   spellings exist for every one).
2. The `result Name:` declaration form — `Result[T, E]` covers it and
   `docs/match-expressions.md` still teaches the old form with `-> i64`.
3. The resource and capability-read keyword tier (`acquire_resource` …
   `random_u64`): keep for hosts behind a documented host page, out of the language
   guide and the keyword table.
4. `domain`/`wrap`/`unwrap`/`private` and `codec`: either promote to documented features
   with a `features.json` slug (they have none) or fold into records with methods (§3.5)
   and typed JSON.
5. `constraint`, composite structural signatures and const-length generics: keep the
   implementation, but move them to an "advanced generics" page so the guide's generic
   section is `def f[T](x: T)` and nothing else.
6. Subcommands an agent will never call from a development loop and that crowd
   `--help`: `bench-promote`, `check-policy`, `discover-duplicates`,
   `discover-project-duplicates`, `report-quality`, `report-project-quality`,
   `schema-project`, `input-module`, `list-interfaces`, `fmt-module`, `emit-project-qbe`.
   Group them under `mylang tool …` or hide them from the default usage.
7. Documentation: `docs/` holds 315 pages and 46,150 lines, of which 126 are experiment
   records and 60 are legacy; the current guide (`python-syntax.md`) is good, but the
   reader has to find it. Keep one language page and one tooling page in the reader's
   path, move experiments and legacy under `docs/history/`, and make `mylang explain
   E_CODE` print the paragraph for a diagnostic so the agent never needs the tree.
8. The 144 Python files under `scripts/` and `tests/` that no gate runs, and the
   `tests/idiom_probes.py` harness (59 fixtures) that overlaps this audit's probe set:
   either wire the harness into the gate so idiom regressions are caught, or delete it.

## 7. Escape hatches

What exists and is measured (`docs/performance.md`): ReleaseFast by default, `noalloc`
as a checked bound, `with arena()` for bulk release, `extern def` for scalar C calls,
`--max-steps`, fixed-width integers, `bytes`. What an agent hits when a measurement
says a hot loop is too slow:

| Escape hatch | State | Gap |
| --- | --- | --- |
| `list[T]` in a `noalloc` loop | works; documented as the fast path | none — this is the right default |
| `[N]T` fixed arrays | O(N) copy per element access (26× slower than `list` on a 4,096 scan) | pass by reference (W6b in the simplification plan, still open) or say plainly that `[N]T` is wire data only and stop offering it as a buffer |
| `extern def` | scalars only; `mylang run` cannot link C | accept `bytes`/`list[u8]` as pointer + length so a C kernel can see guest data |
| `with arena()` | works; "not a speed tool" by its own docs | fine as a lifetime tool; do not sell it as performance |
| parallelism | one process per task, by design | fine for agents; document the pattern with an example that fans out `mylang run` children |
| unboxed records in lists / struct-of-arrays | absent | do not add until a workload asks |

The performance page is the model the rest of the docs should follow: numbers, the
commands that produced them, and no promises.

## 8. Recommended order

Ranked by turns saved per unit of implementation work, with the probe evidence each
rests on:

1. **Silent wrong answers** (§1): `items()` yields keys; dead-write warning on record
   copies; decide `class` = reference type. Evidence: a20, d01, d02, d06, p2c.
2. **Delete the annotation tax** (§2): infer exported and callback ceilings; literals are
   not allocation; overlap checks only under a declared `mutates`; tests discovered
   without `export`. Evidence: project probe, p1d, q12, p8b/p8c, a27.
3. **Test runner** (§5.1): `print` in tests; assertion messages and values; library
   modules and `*_test.my` as entries; directory runs by project root.
4. **Budgets off for `run`/`build`** (§5.2) and the 256-module cap raised (§5.3).
5. **Expression idioms batch** (§3 "Add" rows without tuples): ternary, chained
   comparison, `**`, bit operators, docstrings, module constants, f-string specs,
   `round(x, n)`, `split()`, `str * int`, `str < str`, literal `match`, `del`, nested
   generators, generator arguments, triple-quoted and raw strings, `assert` with any
   `str`, record defaults, record `==`, `str(record)`, `set[T]`.
6. **Tuples and destructuring** (§3.2), then `is None` narrowing (§3.3).
7. **Methods on records** (§3.5).
8. **Module and project ergonomics** (§2.5, §5.4): optional header, `check`
   auto-detect, export by default or a declaration prefix, `from … import` message,
   source paths and packages in `mylang.json` resolved by the binary (no Python), so a
   sibling directory or a second-party library can be imported and tested.
9. **Diagnostics** (§4, §5.4): "did you mean" plus the record's fields, the module's
   exports and the type's methods on every name-resolution error; expected/got counts
   on `E_ARITY`; surface type spellings; flag and subcommand names in usage errors;
   per-subcommand `--help`; `mylang explain E_CODE`.
10. **Edit-loop fixed cost** (§5.4): a one-line edit under 100 ms, failing verdicts
    cached, `check-session` as a watch mode; `fmt --write` and the repo's own guest
    code formatter-clean.
11. **Surface removal and docs consolidation** (§6), then the `[N]T` and `extern def`
    escape-hatch gaps (§7) when a workload needs them.

Items 1–4 and 9–10 need no new language design and would have removed most of the repair turns
seen in this audit's project and realistic-program probes. Items 5–7 are the language
catching up to the Python an agent already knows. Nothing here claims a measured
productivity gain; the comparative trial the plan calls for remains the only way to
confirm one.

## Appendix A — idiom probe results

Each row is one program from the evidence file, run as `mylang run FILE --print-result`.
An exit of 1 is a check error or trap; 2 is a usage or host failure; any other value is
the program's own return.

| Probe | Exit | First diagnostic (or output) |
| --- | ---: | --- |
| `a01_ternary.my` | 1 | error[E_SYNTAX]: unexpected token; expected a newline |
| `a02_chained_cmp.my` | 1 | error[E_TYPE]: expected bool, found i64 |
| `a03_tuple_swap.my` | 1 | error[E_SYNTAX]: unexpected token; expected a newline |
| `a04_tuple_return.my` | 1 | error[E_SYNTAX]: unexpected token; expected a newline |
| `a05_is_none.my` | 1 | error[E_SYNTAX]: unexpected token; expected an indented block |
| `a06_eq_none.my` | 1 | error[E_TYPE]: expected Option<i64>, found unit |
| `a07_option_unwrap.my` | 42 | 42 |
| `a08_aug_subscript.my` | 43 | 43 |
| `a09_aug_str_list.my` | 44 | 44 |
| `a10_chained_assign.my` | 1 | error[E_SYNTAX]: unexpected token; expected a newline |
| `a11_truthiness.my` | 1 | error[E_TYPE]: expected bool, found List<i64> |
| `a12_docstring.my` | 1 | error[E_SYNTAX]: unexpected token; expected def |
| `a13_nested_def.my` | 1 | error[E_EXPRESSION]: expected an expression |
| `a14_lambda_capture.my` | 1 | error[E_CALLBACK_EFFECTS]: callback types require an explicit effects ceiling |
| `a15_lambda_nocapture.my` | 1 | error[E_CALLBACK_EFFECTS]: callback types require an explicit effects ceiling |
| `a16_fstring_spec.my` | 1 | error[E_FORMAT_STRING]: format specifications are not supported; convert the value before interpolating it |
| `a17_percent_format.my` | 1 | error[E_TYPE]: expected str, found i64 |
| `a18_str_format.my` | 1 | error[E_COLLECTION_METHOD]: unknown managed collection method |
| `a19_str_repeat.my` | 1 | error[E_TYPE]: expected str, found i64 |
| `a20_dict_items.my` | 45 | 301 |
| `a21_set.my` | 1 | error[E_UNKNOWN_TYPE]: type is not declared |
| `a22_set_literal.my` | 1 | error[E_SYNTAX]: unexpected token; expected : |
| `a23_optional_annot.my` | 1 | error[E_TOKEN]: unexpected character in source |
| `a24_optional_typing.my` | 1 | error[E_SYNTAX]: unexpected token; expected def |
| `a25_nested_list.my` | 42 | 42 |
| `a26_sort_key.my` | 1 | error[E_CALL_ARGUMENT]: keyword arguments require a declared function or record constructor |
| `a27_sorted_key.my` | 1 | error[E_CALLBACK_EFFECTS]: function values require a declared effect ceiling |
| `a28_sorted_reverse.my` | 1 | error[E_CALL_ARGUMENT]: sorted accepts only the named argument key=callback |
| `a29_max_two_args.my` | 42 | 42 |
| `a30_range_step.my` | 1 | error[E_ARITY]: range requires end or start, end |
| `a31_slice_neg.my` | 44 | 44 |
| `a32_join_map.my` | 42 | 1, 2, 3 ⏎ 42 |
| `a33_round2.my` | 1 | error[E_ARITY]: round requires exactly one argument |
| `a34_power.my` | 1 | error[E_EXPRESSION]: expected an expression |
| `a35_div.my` | 42 | 3.5 ⏎ -4 1 ⏎ 42 |
| `a36_module_global.my` | 1 | error[E_SYNTAX]: unexpected token; expected def |
| `a37_const.my` | 1 | error[E_SYNTAX]: unexpected token; expected def |
| `a38_class_methods.my` | 1 | error[E_SYNTAX]: unexpected token; expected a name |
| `a39_dataclass.my` | 1 | error[E_TOKEN]: unexpected character in source |
| `a40_try_except.my` | 1 | error[E_SYNTAX]: unexpected token; expected a newline |
| `a41_import_os.my` | 1 | error[E_MODULE_HEADER]: file must begin with a module declaration |
| `a42_open_python.my` | 1 | error[E_ARITY]: this file operation's argument count does not match its signature |
| `a43_len_dict.my` | 42 | 42 |
| `a44_enumerate_start.my` | 1 | error[E_ARITY]: enumerate requires one iterable and two iteration names |
| `a45_record_default.my` | 1 | error[E_SYNTAX]: unexpected token; expected a dedent |
| `a46_record_eq.my` | 1 | error[E_TYPE]: aggregate equality is not defined; compare the relevant elements explicitly |
| `a47_print_record.my` | 1 | error[E_TEXT_CONVERSION]: str conversion requires a scalar or str value |
| `a48_for_else.my` | 1 | error[E_EXPRESSION]: expected an expression |
| `a49_match_literal.my` | 1 | error[E_SYNTAX]: unexpected token; expected a name |
| `a50_match_str.my` | 1 | error[E_SYNTAX]: unexpected token; expected a name |
| `a51_del.my` | 1 | error[E_SYNTAX]: unexpected token; expected a newline |
| `a52_pop_insert.my` | 42 | 42 |
| `a53_multiline_str.my` | 1 | error[E_BYTE_LITERAL]: unterminated byte literal; escape newlines with \n |
| `a54_bitops.my` | 1 | error[E_REMOVED_SPELLING]: `&` was removed and has no replacement |
| `a55_chr_ord_hex.my` | 1 | error[E_UNKNOWN_FUNCTION]: no function has this qualified name |
| `a56_divmod_pow.my` | 1 | error[E_SYNTAX]: unexpected token; expected a newline |
| `a57_assert_fstring.my` | 1 | error[E_SYNTAX]: unexpected token; expected a string |
| `a58_main_guard.my` | 1 | error[E_SYNTAX]: unexpected token; expected def |
| `a59_reassign_annot.my` | 42 | 42 |
| `a60_overflow.my` | 1 | error[R_OVERFLOW]: native execution failed (add: left 9223372036854775807, right 1, width 64) |
| `a61_result_unwrap.my` | 1 | error[E_SYNTAX]: unexpected token; expected a name |
| `a62_option_or.my` | 1 | error[E_ARITY]: list method argument count does not match its signature |
| `a63_dict_get_option.my` | 1 | error[E_ARITY]: list method argument count does not match its signature |
| `a64_split_noargs.my` | 1 | error[E_ARITY]: collection method argument count differs from its signature |
| `a65_str_cmp.my` | 1 | error[E_TEXT_OPERATOR]: managed collections support equality and str/bytes support concatenation |
| `a66_nested_comp.my` | 1 | error[E_SYNTAX]: unexpected token; expected ] |
| `a67_dict_comp.my` | 1 | error[E_SYNTAX]: unexpected token; expected } |
| `a68_genexp.my` | 1 | error[E_SYNTAX]: unexpected token; expected ) |
| `a69_print_end.my` | 42 | ab ⏎ 42 |
| `a70_int_from_float.my` | 1 | error[E_SYNTAX]: unexpected token; expected ) |
| `a71_type_alias.my` | 1 | error[E_SYNTAX]: unexpected token; expected def |
| `a72_type_alias_kw.my` | 42 | 42 |
| `a73_while_else_walrus.my` | 1 | error[E_SYNTAX]: unexpected token; expected ) |
| `a74_str_in_list.my` | 42 | 42 |
| `a75_list_of_records_mutate.my` | 1 | error[E_ASSIGNMENT_TARGET]: augmented assignment to a record field is not supported; write the field out in fu |
| `a76_record_in_dict.my` | 42 | 42 |
| `a77_dict_record_key.my` | 1 | error[E_DICT_KEY]: dictionary keys must be integers or str |
| `a78_multiple_return_record.my` | 42 | 42 |
| `a79_str_methods.my` | 1 | error[E_LIST_METHOD]: unknown managed collection method |
| `a80_none_return_call.my` | 42 | warning[W_UNUSED_BINDING]: binding is never read; use it or remove it, preserving initializer effects with `_  |
| `c01_option_q.my` | 0 | 0 |
| `c02_result_err_convert.my` | 1 | error[E_TYPE]: expected i64, found str |
| `c03_main_result_str.my` | 1 | not a number: zz |
| `c04_option_default.my` | 42 | 42 |
| `c05_option_field.my` | 26 | warning[W_UNUSED_BINDING]: binding is never read; use it or remove it, preserving initializer effects with `_  |
| `c06_result_record_err.my` | 1 | empty ⏎ 1 |
| `c07_if_let_style.my` | 1 | error[E_OPTION_INFERENCE]: Some requires an expected Option type |
| `c08_match_expr.my` | 1 | error[E_EXPRESSION]: expected an expression |
| `d01_loop_record_copy.my` | 0 | visited: 0 ⏎ 0 |
| `d02_alias_record_copy.my` | 1 | nodes[0].value = 1 ⏎ 1 |
| `d03_record_param_mutate.my` | 1 | error[E_ASSIGNMENT_TARGET]: augmented assignment to a record field is not supported; write the field out in fu |
| `d04_dict_items_keys.my` | 0 | 0 1 ⏎ 1 2 ⏎ 0 |
| `d05_round_half.my` | 0 | 3.0 1.0 -3.0 ⏎ 0 |
| `d06_record_field_in_dict_loop.my` | 0 | 0 ⏎ 0 |
| `d07_str_index_assign.my` | 1 | error[E_COLLECTION_METHOD]: operation is not supported by this collection |
| `d08_int_float_mix.my` | 0 | 4.5 4.5 ⏎ 2.0 ⏎ 0 |
| `d09_shadow_builtin.my` | 1 | error[E_SHADOWING]: binding shadows an active local or top-level function |
| `d10_unused_result.my` | 1 | error[E_EXPLICIT_DISCARD_REQUIRED]: a standalone non-unit value requires `_ =` or result handling |
| `e01_step_budget.my` | 1 | error[R_STEP_LIMIT]: instruction budget exhausted; raise it with --max-steps=N |
| `e02_bitops_each.my` | 1 | error[E_TOKEN]: unexpected character in source |
| `e03_shift.my` | 1 | error[E_EXPRESSION]: expected an expression |
| `e04_generic.my` | 42 | 42 |
| `e05_str_concat_perf.my` | 0 | 0 |
| `e06_list_of_lists_build.my` | 1 | 1 |
| `e07_recursion_depth.my` | 1 | pth.my:4:16 |
| `e08_format_float.my` | 1 | error[E_MODULE_NAME]: declared module name does not match its requested path |
| `e09_walk_dict_sorted.my` | 0 | a 1 ⏎ b 2 ⏎ 0 |
| `e10_while_assign_after_loop.my` | 1 | error[E_UNBOUND]: name may be read before it is assigned; some control-flow path reaching here leaves it unbou |
| `e11_if_no_else_bind.my` | 0 | big ⏎ 0 |
| `e12_none_default_param.my` | 0 | x ⏎ 0 |
