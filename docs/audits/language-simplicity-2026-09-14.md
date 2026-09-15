**Language simplicity audit — 14 September 2026**

The language now reads like statically typed Python for a surprising amount of ordinary
code, and the escape hatch for performance work exists and works. What is left is mostly
*not* syntax. It is (1) everyday vocabulary that Python programmers reach for and mylang
does not have, (2) the same operation offered by three different tiers with different
shapes, (3) a tail of reserved words and declaration forms that no ordinary program uses,
and (4) an escape hatch that is undiscoverable from the guide and has two dead ends in it.

This is the successor to the [12 September audit](language-simplicity-2026-09-12.md).
Almost everything that audit asked for has since landed: one Python-shaped surface,
managed lists/strings/dicts with GC, `int`, `float`, unit procedures, record constructors,
`Ok`/`Err`/`Some`/`None` patterns, a ten-module standard library, `with arena()`. That is
why this audit does not repeat its recommendations and instead asks the next question:
**what is still not simple, in a language that already has the right shape?**

Nothing in the implementation was changed. No build or Guardian gate was run. Every claim
below is either a source citation or a probe that was executed against
`zig-out/bin/mylang` on 14 September 2026; the probe log is in Appendix B.

---

## Summary of recommendations

| # | Recommendation | Kind | Effort | Payoff |
| --- | --- | --- | --- | --- |
| 1 | Finish the everyday collection and builtin vocabulary (list methods, `dict.items`, `sorted`/`sum`/`min`/`max`/`abs(int)`/`round`/`any`/`all`/`zip`, slice step, `x[i] += v`) | add | medium | highest |
| 2 | Fix, then freeze, one placement rule for the three tiers (prelude / method / stdlib) and delete the duplicates | simplify | small-medium | high |
| 3 | One `run` command: accept `module`/`import` in `run` so a single file can use `math`, `sort`, `strings` | simplify | small | high |
| 4 | Fix the three consistency defects a beginner meets first: `len(x)` vs `x.len()`, `len`/`replace` ignoring declarations, and prelude types selected by scanning source text for the spelling of a name | fix | small | high |
| 5 | Delete the 15 `f64_*` reserved words (and the `float`-as-a-private-domain bridge); expose `float`↔bits only if something needs it | remove | small | high |
| 6 | Let `main` return a renderable `Result`, so a capability program stops needing a helper function plus a `match` pyramid | add | small | high |
| 7 | Add a `lambda` spelling for non-capturing callbacks (no new closure semantics needed) | add | small | high |
| 8 | Add a performance page: when native, `--mode ReleaseFast`, `--max-steps=`, and say so in the `R_STEP_LIMIT` message | document | small | high |
| 9 | Let `?` work on `Option` inside an `Option`-returning function, so unwrapping is not always a four-line `match` | add | small | medium |
| 10 | Let `const` hold `bytes` and `str` literals (it removes 23 wrapper functions and a 16-line ladder from the schematic alone) | add | small | medium |
| 11 | Fix `math` to call the prelude intrinsics (`math.sqrt` is 11.6× slower than the `sqrt` it shadows) and decide the `Result`-for-impossible-errors policy | fix | small | medium |
| 12 | Decide `domain`'s fate: document it, and decide whether a domain may *declare* its representation conversion | decide | small-medium | medium |
| 13 | Replace `export NAME` directive lists with a prefix on the declaration (the current corpus spends 242 lines on directives) | simplify | small | medium |
| 14 | Decide whether classes get methods (or at least `Type.func(value)` namespacing like domains have) | decide | large | highest, long term |
| 15 | Consolidate documentation: one guide, one reference, history out of `docs/`, refresh the 25 brace-era experiment pages and the 61 example files that still teach `-> i64` | simplify | medium | medium |

The rest of this document justifies each of these.

---

## 1. What is already simple

Worth stating plainly, because it is the majority of the language and it works. Probed
directly, with the exact results in Appendix B:

- **Printing matches Python value-for-value.** `print(P(x=1, items=[1, 2]))` → `P(x=1, items=[1, 2])`; a dict → `{'a': 1}`; bytes → `b'AB'`; floats → `3.0`, `0.30000000000000004`. `sep=`/`end=` work.
- **Text is real Unicode text.** `len("héllo")` is `5` and `"héllo"[1] == "é"`.
- **Collections share storage like Python objects.** `ys = xs; ys.append(2)` is visible through `xs`; slices copy; nested indexing and expression receivers work; `xs[i] = v` evaluates once.
- **Comprehensions, f-strings, `elif`, `for ... in`, `enumerate`, `range`, `assert`, `not in`, `while True` + `break`** all read exactly as Python.
- **Value records** with named/positional construction, exhaustive `match`, `Result`/`Option` with `?`, `with open(fs, path, "rb") as f:`.
- **Diagnostics** carry a stable code, a caret at the offending column, and a specific sentence (`E_MISSING_RETURN`, `E_EXPLICIT_DISCARD_REQUIRED`, `E_DICT_INFERENCE`).
- **Managed arenas** are one concept with one syntax (`with arena() as scratch:`) and no annotations to thread. This is the model the rest of the language should be measured against: one idea, one spelling, no ceremony.
- **Native compilation of ordinary Python-shaped code is fast** — 20–34× the VM on managed collections (Appendix A).

The remaining problems are therefore *not* "the language is too weird". They are missing
vocabulary and duplicated vocabulary.

---

## 2. The remaining distance to "statically typed Python"

### 2.1 Collections: one mutating method, no builtins

`docs/managed-memory.md:108` documents this deliberately: "A list answers one method by
name, `append(value)`; there is no `insert`, `pop`, `remove`, `extend` or `sort`".

Probed, against the current binary:

```text
xs.append(2)        works
xs.push(2)          works (undocumented legacy alias)
len(xs)             works, returns int
xs.len()            works, returns u64      <-- different type from len(xs)
xs.extend([2])      E_LIST_METHOD: unknown managed collection method
xs.insert(1, 2)     E_LIST_METHOD
xs.pop()            E_LIST_METHOD
xs.remove(2)        E_LIST_METHOD
xs.index(2)         E_LIST_METHOD
xs.reverse()        E_LIST_METHOD
xs.sort()           E_LIST_METHOD
xs.copy()           E_LIST_METHOD
xs[0] += 5          E_SYNTAX
a, b = b, a         E_SYNTAX (no tuples)
d.items()           E_ITERATION: two iteration names require enumerate
d["a"] += 1         E_SYNTAX
x += 1.0            E_TYPE: operation requires an integer type
s += "b"            E_TYPE: operation requires an integer type
xs[0:4:2]           E_SYNTAX (slices have no step)
```

A programmer coming from Python writes `xs.pop()`, `sorted(xs)`, `total += x` and
`d.items()` as reflexes. Each failure above is a turn spent discovering that the language
is not Python, and the fix is not a design change: it is finishing a small, bounded
vocabulary in the VM and the QBE backend.

**The `sort` module is the wrong shape for the common case.** `sort.sort_ints(values)`
returns a *new* list and requires `import sort` in project mode; Python's `sorted(xs)` is a
builtin and `xs.sort()` mutates. `sort.sort_by_key(values, key)` requires a *named*
function with an explicit `def(T) -> int effects()` signature, because the language has no
lambda (see §2.3). Sorting a list of records is therefore a three-part ritual: import a
module, declare a function, call a function.

### 2.2 Missing prelude builtins

Only `len`, `str`, `int`, `float`, `print`, `enumerate` and (loop-only) `range` exist as
prelude operations. Probed one by one:

```text
abs(0 - 42)   E_TYPE: this prelude operation requires a float argument   # float-only!
min(1, 2)     E_UNKNOWN_FUNCTION
max(1, 2)     E_UNKNOWN_FUNCTION
sum([1, 2])   E_UNKNOWN_FUNCTION
sorted([2,1]) E_UNKNOWN_FUNCTION
reversed(xs)  E_UNKNOWN_FUNCTION
round(1.6)    E_UNKNOWN_FUNCTION
all([...])    E_UNKNOWN_FUNCTION
any([...])    E_UNKNOWN_FUNCTION
pow(2, 3)     E_UNKNOWN_FUNCTION
divmod(7, 2)  E_UNKNOWN_FUNCTION
chr(65) ord("A") hex(255) bin(5) repr(x) format(x, "d") isinstance(x, int)  E_UNKNOWN_FUNCTION
zip(a, b)     E_ITERATION: two iteration names require enumerate
list(range(3)) E_UNKNOWN_FUNCTION (range is a loop source, not a value)
```

Every one of those has an obvious, total, side-effect-free meaning; none needs new
machinery. Several already exist in the standard library under a different shape:
`math.min/max` (generic over `integer`), `math.abs(value: int) -> Result[int, str]`,
`sort.min_int(values) -> Option[int]`, `strings.repeat`, `strings.pad_left`. So the
language already knows how to compute them — it just does not let you write them the way
Python does.

**`abs` is the clearest single wart**: `abs` exists, is a prelude operation, and rejects an
`int`. `math.abs(0 - 42)` works but returns `Result[int, str]` because `-9223372036854775808`
has no positive counterpart. Python's `abs` is total in practice; making the common call
site handle a `Result` for a value that occurs approximately never is a bad trade (see §5.5).

### 2.3 Expression-level Pythonisms

| Written as Python | Today | Note |
| --- | --- | --- |
| `42 if x > 0 else 0` | `E_SYNTAX` | parser sugar |
| `0 < x < 10` | `E_TYPE: expected bool, found i64` | parser sugar |
| `a, b = b, a` / `(1, 2)` | `E_SYNTAX` | no tuples (deliberate; see §9) |
| `if xs:` / `if n:` | `E_TYPE: expected bool` | truthiness excluded by design (keep) |
| `if x is None:` | `E_SYNTAX` | `is` does not exist |
| `x == None` on an `Option` | `E_TYPE: expected Option<i64>, found unit` | `None` is unit; `Option` must be matched |
| `None == None` | `E_TYPE: aggregate equality is not defined` | even unit has no equality |
| `lambda` / nested `def` | `E_SYNTAX` / `E_EXPRESSION` | see below |
| `"""docstring"""`, `r"raw"` | `E_SYNTAX` | single-quoted strings only |
| `p1 == p2` for two records | `E_TYPE: aggregate equality is not defined` | field-wise compare by hand |

Two of these are cheap and high-frequency: the **conditional expression** and **`lambda`
over non-capturing callbacks**. The language already has first-class values of type
`def(T) -> U effects(...)` (`examples/callbacks.my`), and references forbid captures, so
`lambda p: p.score` introduces *no* new semantics — it is a spelling for an existing
value. It removes the "declare a module-level function to sort by a field" ritual
described in §2.1 without touching the closure design.

Record equality deserves a decision too. Records are *values* — assignment copies them —
yet `a == b` is rejected and the diagnostic tells you to compare the fields yourself.
Value semantics without value equality is an inconsistent pair; the domain tier already
proves the implementation exists (domains support `==` by backing value, `SPEC.md`
`[DOMAIN-EQUALITY-1]`).

### 2.4 The module boundary has no single entry command

```text
$ mylang run main.my                      # a file with `module main` + `import math`
main.my:1:1: error[E_SYNTAX]: unexpected token; expected def
$ mylang run-project main.my              # same file
42
```

`mylang run` rejects `module`, `import` and `export` outright. The guide says "A single-file
program needs no `module` header at all" (`docs/modules.md:130`), which is true but hides
the consequence: **the standard library is unreachable from a single file.** The first time
a user types `import math` above `def main` they get `expected def` at line 1, and the fix
is to move the file into a directory and change the command. That is a language-layer
promise ("import a module by name") broken by a CLI-layer distinction.

This is the cheapest high-value simplification in the list: one command that detects
whether the entry file has a module header and does the right thing. `mylang run` and
`mylang run-project` collapsing into one command (with `--project` retained as an override)
removes a whole concept from the user's model.

### 2.5 Nominal types without methods, and one that has them

`class` has no methods and no `self` — a deliberate, documented choice
(`docs/records-and-unions.md:11`) that keeps records as values. But `domain` *does* allow
functions in its body, and they are called with qualified syntax:

```text
domain Document: int:
    def id(document: Document) -> int noalloc:
        return unwrap(document)

Document.id(document)      works
document.id()              E_UNKNOWN_TYPE
```

So the language has a type-scoped function namespace — but only for the type kind that most
programs never declare, and even there the receiver is not implicit. `src/schematic/guest/io.my`
and `examples/corpus/invoice/*.my` use domains; ordinary application records cannot.

Whatever is decided about methods (see §8), the *asymmetry* is the current complexity: two
nominal forms, one with namespacing and one without, and the one with namespacing is the
undocumented one.

### 2.6 What the shipped corpus says

Counting over the de-duplicated corpus of real mylang code (121 files, 7,475 lines:
`find examples src/schematic/guest src/stdlib test tests -name '*.my'`, minus 13 files under
`test/fixtures` that are byte-identical copies of `examples/` files) gives a more useful
picture than the probe tables above, because it shows where the language is already enough:

```text
top-level def                                 530       export directives         242
class / enum / result / domain       58 / 13 / 28 / 10   host def                   10
if / while / for / match       802 / 162 / 42 / 136      match arms                295
casts of any width                             81  (0.76% of all lines)
explicit `_ =` discards                        88  (35 of them `_ = 0` arm fillers)
assert / todo[ / break / continue / comprehension   0 / 0 / 0 / 0 / 0
```

Four conclusions follow, and they matter for prioritising the recommendations:

- **Inside a function body, mylang costs essentially nothing over Python.** Measured on
  three tasks — read a file and count its lines, build a dictionary of counts, accumulate
  records into a totals map — the mylang version is the Python version plus one annotation
  on an empty dictionary (`counts: dict[str, int] = {}`, required because `{}` has no
  element type to infer). Everything else matched, including `int * float`.
- **The tax is at the program edge, not in the language core.** The file-reading task grows
  from 5 lines to 11 because of the `Filesystem` parameter, a `Result[int, str]` return, and
  a helper function plus a `match` in `main` (§5.7). That is the shape worth attacking.
- **Casts are no longer a problem.** 81 in 7,475 lines, 10 of them from one fixture that
  probes integer extrema. The `i64(...)`-everywhere era that the 12 September audit measured
  is over; the remaining 33 `i64(` uses are width changes at ABI boundaries.
- **Two hand-written idioms are pure noise**, both authorial rather than language-forced:
  39 of 68 single-condition `while i < len(seq)` loops use the index only to subscript a
  sequence they never mutate (78 scaffolding lines, plus 154 manual `i += 1`), and 35 `_ = 0`
  match arms could be `pass`. Worth a documentation note, not a language change.
  (Three loops in `layout_graph.my` genuinely need the index, because a record read out of a
  list is a copy: `for item in nets: item.group = 9` has no effect, while
  `nets[0].group = 9` does.)

---

## 3. One operation, three spellings

This is the core simplicity finding. mylang now has three tiers that can each express the
same operation, and the tiers disagree about names, types, failure shape and location.

| Operation | Tier 1: prelude / keyword | Tier 2: intrinsic method | Tier 3: standard library |
| --- | --- | --- | --- |
| append | — | `xs.append(v)` / `xs.push(v)` | — |
| length | `len(xs)` → `int` | `xs.len()` → `u64` | — |
| text case | — | `"a".upper()` | `strings.upper("a")` |
| prefix test | — | `"ab".startswith("a")` | `strings.starts_with("ab", "a")` |
| substring search | — | `"abc".find("z")` → `-1` | `strings.find("abc", "z")` → `Option[int]` |
| parse int | `int("42")` → `Option[int]` | `"42".parse_int()` | `strings.to_int("42")` → `Option[int]` |
| replace | — (reserved word) | `s.replace(a, b)` | `strings.substitute(s, a, b)` → `Result` |
| pad | — | — (no `ljust`) | `strings.pad_left(s, w, f)` → `Result[str, str]` |
| sort | — | — (no `xs.sort()`) | `sort.sort_ints(xs)` → new list |
| minimum | — | — | `sort.min_int(xs)` → `Option[int]`, `math.min(a, b)` |
| absolute value | `abs(float)` → `float` | — | `math.abs(int)` → `Result[int, str]` |
| square root | `sqrt(float)` → `float` | — | `math.sqrt(float)` → `float` (Newton loop, 11.6× slower) |
| dictionary read | — | `d[k]`, `d.get(k, fallback)`, `k in d`, `d.contains(k)` | — |
| dictionary keys | — | `d.keys()`, `d.values()` | — |
| dict iteration | — | `for k in d:` | — (no `items()`) |
| bitwise and | `bit_and(a, b)` | — | — (`&` is lexed and unparseable) |
| truncating divide | `divtrunc(a, b)` | — | — |
| raw float op | `f64_sqrt(u64)` | — | `math.sqrt(float)` |

Holding that table in your head is the actual learning cost of the language right now. The
fix is not to add a fourth tier; it is to state the rule and delete what breaks it.

**Proposed rule** (one sentence per tier, in the guide):

1. **Prelude builtins** are the operations every program expects and that cannot fail:
   `len`, `str`, `int`, `float`, `print`, `range`, `enumerate`, plus the builtins of §2.2.
   They are total; none returns `Result`.
2. **Methods** are the operations of one value kind: list mutation and indexing, dict
   access, string manipulation. One spelling each, no aliases. A method that cannot fail
   returns its value; a method that can fail returns `Result`/`Option`, never a sentinel
   (`find` returning `-1` is the one current exception and should go).
3. **The standard library** holds what needs a namespace: `math` for transcendental and
   classification functions, `sort` for ordering helpers over *new* lists, `json`, `path`,
   `hex`, `base64`, `pool`, `random`, `time`. **Nothing in the library may duplicate a
   builtin or a method**; when it must exist for a reason (the `effects`-free, allocator-free
   variant, the ABI shape), it delegates.

Applying that rule to today's tree deletes: `push`, `xs.len()`, `d.contains`, `strings.upper`,
`strings.lower`, `strings.strip`/`lstrip`/`rstrip`, `strings.count`, `strings.find`,
`strings.starts_with`, `strings.ends_with`, `strings.is_digit`/`is_alpha`/`is_space`,
`strings.to_int`, `strings.lines`, `strings.substitute` (15 of the string module's 25
exports), `math.trunc`/`floor`/`ceil`/`sqrt`/`abs` (5 of math's 25), and the `List` alias.
That is surface a reader currently has to *choose between*.

---

## 4. Reserved words and declaration forms nobody uses

The lexer recognizes **86 reserved word spellings** (`src/lexer.zig:160-255`: 78 in `words`,
5 aliases, 3 operator words). Counting how many of them appear anywhere in the shipped guest
code (78 `.my` example files, the 10 stdlib modules, the 14-file schematic application, and
the test fixtures) gives a stark split:

```text
used by at least one current .my source:  51
used by none:                             27
   f64_add f64_sub f64_mul f64_div f64_eq f64_lt f64_le f64_sqrt
   f64_floor f64_ceil f64_trunc f64_abs f64_neg f64_from_u64 f64_to_u64
   bit_and bit_or shift_left saturating_add saturating_sub saturating_mul
   network_cap codec_encode codec_decode todo continue assert
```

`continue` and `assert` are documented features that simply have no current call site, so
they stay. The rest are a legitimate deletion list:

| Candidate | Evidence | Proposal |
| --- | --- | --- |
| 15 `f64_*` words | Zero uses. They accept and return `u64`, and the only bridge to them is `f64_from_u64`/`f64_to_u64`, which convert *integers*, so no fractional value can enter or leave: `f64_add(1.5, 2.5)` → `E_FLOAT_OPERATION`; `f64_sqrt(f64_from_u64(16))` → `4`. `docs/floating-point.md:64` admits guest code cannot reach the intrinsic from an ordinary `float`; `float` is registered as a private domain over `u64` (`src/nominal_templates.zig:129-135`) | Delete the family. If a bit-level bridge is wanted later, add two ordinary library functions (`float.bits(x)` / `float.from_bits(u)`) rather than 15 keywords |
| `codec_encode`, `codec_decode` | Zero uses in shipped source | Move behind the domain-codec tooling they serve, or delete with the codec declarations |
| `todo[...]` | Zero uses; kept as an agent-facing typed-hole tool | Keep if agents use it, but it should not appear in the beginner guide's first 50 lines (it currently does) |
| `bit_and`, `bit_or`, `bit_xor`, `shift_left`, `shift_right` | 2 of 5 used once each. `&` is lexed but has no reader (`src/lexer.zig:116,294`), so the *operator* spelling is dead | Either wire `& | ^ << >>` (5 words become operators, no new words) or drop the dead `&` token |
| `wrapping_*`, `saturating_*` | 3 of 6 used once each | Keep: this is the integer overflow escape hatch, and the names earn their length |
| `*_cap` (`filesystem_cap`, `clock_cap`, `random_cap`, `environment_cap`, `network_cap`) | The Python spellings `Filesystem`, `Clock`, `Entropy`, `Environment`, `Network` are accepted for the same types (`src/prelude.zig:45-58`), and the standard library *signatures* still use `clock_cap`/`random_cap` (`src/stdlib/time.my:109`, `random.my:45`). Both compile | Keep the Python spellings only; fix the two stdlib signatures and the three examples that teach `*_cap` |
| `acquire_resource`, `complete_resource`, `restrict_resource`, `read_resource`, `write_resource`, `environment_get`, `clock_now`, `random_u64` | The external-resource and capability-read tier. It is the reason `examples/environment.my` needs a `class Entry { bytes: [64]u8, length: u64, present: bool }` and a `result Lookup` to read one environment variable | Keep for hosts, but give the ordinary path an API: `environment.get(env, name) -> Option[str]`. That one function removes an ABI-shaped declaration from every program that reads an env var |
| `domain`, `private`, `wrap`, `unwrap` | Used by 8 example/fixture files and the schematic, but **absent from `src/features.json` entirely** (no feature slug, no doc-coverage entry) and documented only in `docs/experiments/domains.md`, which is still written in the removed brace dialect | Decide: either promote to a first-class documented feature (and fix §2.5's asymmetry), or remove with the rest of the A2 tier |
| `List` (capital) | A live alias of `list` and residue of the removed storage tier (`src/nominal_templates.zig:109-110`). `x: List[int] = [1,2,3]` compiles; `mylang fmt` leaves it unchanged, so it keeps propagating | Delete the alias; emit a rename hint |
| `push` | Alias of `append` (`src/buffer_operations.zig:75`), undocumented | Delete |
| dead `std_result` lookup | `src/nominal_templates.zig:72` still looks up `std_result::Result`; `grep -rn std_result src/` matches only that line and `import std_result` fails with `E_MODULE_READ: cannot load std_result.my: NotFound` | Delete the branch |

Two **dead tokens** are worth a one-line cleanup while the last traces of the old dialect
are removed: `.ampersand` (`&`) and `.fat_arrow` (`=>`) are lexed and have no reader.

The capability-read row is worth seeing in full, because it is the clearest case of an ABI
shape leaking into ordinary code. This is what reading one environment variable costs today
(`examples/environment.my`, abbreviated to the declarations):

```text
class Entry:
    bytes: [64]u8
    length: u64
    present: bool

result Lookup:
    ok: Entry,
    err: i64

def lookup(env: environment_cap) -> Lookup effects(environment):
    return environment_get[Lookup](env, [75u8])
```

Two type declarations, a fixed 64-byte buffer, a boolean and an integer error code, all
written by the *caller*, to answer "what is the value of this variable". The `Clock`,
`Entropy` and `Environment` capabilities are spelled with reserved-word type names in the
standard library and in three examples, but as `Filesystem`/`Clock`/`Entropy` in the guide,
and both spellings compile.

**Declaration forms.** A file can now open with `module`, `import`, `export`, `const`,
`type`, `class`, `union`, `enum`, `domain`, `def`, `host def`, `extern def`, `codec`, and
`result` — thirteen top-level forms, of which `domain`, `codec`, `host def` and `extern def`
are the specialist half. `host def` (call into the embedding host) and `extern def` (call a C
symbol) are two mechanisms for "a function whose body is elsewhere"; the difference is real
(VM providers vs. native linkage) but a user choosing between them has no guidance in the
guide.

---

## 5. Consistency defects that are also simplifications

These are small, local, and each one is a place where the language contradicts itself. They
are listed first because they are cheap to fix and because they are exactly the ones a
beginner meets in the first hour.

### 5.1 `len(x)` and `x.len()` disagree about the answer's type

```text
n: int = len(items)      # 3
n: int = items.len()     # E_TYPE: expected i64, found u64
n: u64 = items.len()     # 3
```

`len(x)` is the documented spelling (`docs/managed-memory.md:108`) and returns `int`; the
undocumented method returns `u64`. Since only one of the two can be returned from a
`def main() -> int`, this bites immediately. Fix: one spelling (`len(x)`), one type (`int`).

### 5.2 `len` and `replace` ignore a user declaration; `sqrt` does not

```text
def len(value: int) -> int: ...   then len(42)   ->  E_TYPE: operation requires a fixed array value
def sqrt(value: float) -> float: ... then sqrt(4.0) -> 0.0  (the declaration wins)
```

Both behaviours are defensible; having both is not. Pick one rule — the `sqrt` rule (a
declared function shadows the prelude) is the one that matches every other name in the
language.

### 5.3 Whether a prelude type exists is decided by scanning the source text for its name

This is the most surprising defect found. `src/nominal_type_syntax.zig:86-111` decides
whether `str`, `dict`, `bytes` and `float` are registered by **searching the file's raw bytes
for those words**, and line 100 skips `//` to end of line because `//` used to be a comment.
`//` is now floor division. Consequences, probed:

```text
raw = "hi".encode()                      # no `bytes` token in the file
  -> E_COLLECTION_METHOD: operation is not supported by this collection

raw: bytes = "hi".encode()               # the token is present
  -> 4

n = 4 // 2; raw: bytes = "hi".encode()   # one line, `bytes` after the `//`
  -> E_UNKNOWN_TYPE: type is not declared

raw: bytes = "hi".encode(); n = 4 // 2   # same program, other order
  -> 4
```

Moving an operator changes whether the program compiles. Fix: register the prelude types
unconditionally (`src/nominal_templates.zig:108-119`) and delete the scanner. This is a
correctness bug *and* a simplification — a whole source-scanning subsystem disappears.

### 5.4 `Option`/`Result`: construction and pattern spelling are not symmetric

```text
case Ok(v):          works              Result.ok(42)        E_UNKNOWN_TYPE
case Result.ok(v):   works              Option.some(42)      E_UNKNOWN_TYPE
case Some(v):        works
case None:           works
```

Qualified *patterns* are accepted and qualified *construction* is not; a declared
`result Outcome:` requires the qualified form in both. One rule (`Type.case` with bare
`Ok`/`Err`/`Some`/`None` as prelude sugar) and the two mapping tables in `src/prelude.zig:6`
and `src/io_render.zig:41` can go.

### 5.5 `Result` for errors that cannot happen at the call site

`math.abs`, `math.gcd`, `math.lcm`, `math.isqrt`, `strings.pad_left`, `strings.pad_right`,
`strings.repeat`, `strings.substitute`, `strings.format_int`, `strings.format_float`,
`time.seconds`, `time.sum`, `time.difference` — 40 of 189 standard-library functions return
`Result`. Some are genuinely fallible (parsing, allocation, overflow on user-sized input).
Others exist because one input in 2^63 is an edge case:

```text
match strings.pad_left("ab", 5, " "):     # five lines to left-pad a string
    case Ok(v): ...
    case Err(e): ...

match math.abs(0 - 42):                   # `abs` is total in every language that has it
    case Ok(v): ...
    case Err(e): ...
```

Recommendation: a `Result` return should mean "this fails for reasons the caller can act
on". Where the only failure is a domain edge (the minimum integer, a negative width, a
multi-character fill), prefer a total function with a documented, checked precondition
(`assert`) or a `panic`-style trap — and keep a `Result` variant in the library for callers
who need to handle it. Padding a string should not cost an error path.

### 5.6 Smaller asymmetries

- `int(x)`/`float(x)` are overloaded: `int(41.9)` converts, `int("42")` parses and returns
  `Option[int]` (`src/sema.zig:541-585`). The name does two jobs with two return shapes.
- `str(bytes)` and `bytes("hi")` are both rejected, while `str(42)`/`str(True)`/`str(1.5)`
  work and `"hi".encode()` works. `bytes.decode()` returns `Result[str, str]`, so
  `back: str = raw.decode()` fails and needs unwrapping.
- `find` is a sentinel (`-1`) as a method and an `Option` in the library.
- `divtrunc`/`remtrunc` exist besides `/`, `//` and `%`; their own source comment
  (`src/truncating_math.zig:3-5`) cites "binary formats, C interfaces and migrated legacy
  code". That is a library, not a reserved word.
- `examples/*.my` still teach the previous numeric surface: 61 of 78 example files declare
  `-> i64` and only 9 declare `-> int`; 28 `i64(...)` conversions and 81 suffixed literals
  (`200u8`) remain. The guide teaches `int`.

### 5.7 The program edge: four rules that cost more than they return

Everything in §2 is about writing a line of code. These four are about *wrapping a program*,
and each one costs a helper function or a match pyramid in ordinary applications.

**`main` cannot propagate an error.** `def main(...) -> Result[None, str]` is rejected
("main must return int, None, or Result<None/int,int>"), and `?` in an `int`-returning `main`
is `E_TRY_RETURN`. So every program that touches a capability writes a helper whose only
purpose is to be fallible, then a `match` in `main` to turn the failure into an integer:

```text
def work(fs: filesystem_cap) -> Status effects(filesystem):
    ...
    return acquire_resource[Open](fs, request)?
```

That is the *entire* difference between the 5-line Python "read a file and count its lines"
and the 11-line mylang version. Proposal: accept `def main(...) -> Result[None, E]` for any
renderable `E`, print the `Err` payload to stderr, and exit non-zero — the compiler already
renders `Err(...)` values.

**`Option` has no shorthand.** A `Result` propagates with `?`; an `Option` cannot
(`E_TRY_TYPE`), `is None` is a syntax error and `== None` is a type error. So every optional
value costs a four-line `match`: the corpus contains **30 `match` statements on `Option`**,
and `src/stdlib/json.my:495-505` spends ten lines on two conversions that a `?` would write
in two. Proposal: let `?` work on an `Option` inside a function that returns an `Option`.

**`const` accepts only integers and booleans.** `const IMPORT: bytes = b"import"` is
`E_CONSTANT_EXPRESSION`. The consequence is visible in the schematic: 23 one-line wrapper
functions whose body is a single `s.form(nodes, i, b"...")` call, plus a 16-line
`metadata` ladder, exist only to name byte literals (`src/schematic/guest/validate.my:11`,
`circuit.my:31-52`, `ports.my:18-36`). It is also why `math.pi()` and `math.e()` are
functions rather than constants. A literal initializer is static and allocates nothing, so
allowing it breaks no existing rule. (The 23 wrappers can be deleted today with no language
change — `circuit.my:75` already passes a byte literal directly — which means this is
partly an example-cleanup task.)

**A `domain` cannot declare its representation conversion.** Domains are the units/identity
type, and their whole point is that `unwrap` is inaccessible outside the domain. But there
is no way to say "this domain converts to its representation here", so callers must invoke
an accessor by hand every time. `examples/corpus/invoice/pricing.my:46` is a 340-character
line that repeats `money.Cents.number(totals.gross)` seven times, and `:69` repeats
`money.Cents.make(u64(...))` seven times; the corpus has 15 `.number(` unwraps and 18
`.make(` factories. There is a `conversion` declaration form in the language, but it is a
record-to-record complete-field-accounting construct, not a coercion (`SPEC.md:516`,
`[PY-CONVERSION-1]`). Proposal: let a domain declare which method is its representation
conversion so target-typed positions accept the wrapper — a change that shrinks the two
least readable lines in the corpus to ordinary field reads.

**`export` is a separate directive list, not a modifier.** The corpus spends 242 lines on
`export NAME` lines (`397` module/import/export header lines in total). An `export def` /
`export class` prefix would delete one concept (the directive list, with its duplicate and
unknown-export diagnostics) and a sixth of the header lines. The 12 September audit raised
this; it is still the cheapest remaining declaration-surface simplification.

---

## 6. The performance escape hatch

### 6.1 What exists, and what it is worth

The escape hatch is real and measurable (Appendix A, all on this machine, ReleaseFast):

| Workload | VM | Native | Ratio |
| --- | --- | --- | --- |
| 1,000,000-iteration integer loop (add + modulo) | 0.62 s | 0.023 s | 27× |
| 200,000 list appends + sum | 0.345 s | 0.017 s | 20× |
| 20,000 dict writes with `str` keys | 1.56 s | 0.046 s | 34× |
| 2,500,000 list appends (50k × 50 elements), peak RSS | — | 0.05 s, 1.8 MB | GC keeps up |

So: **ordinary Python-shaped code compiled natively is fast**, memory is reclaimed, and
`mylang build` is the performance story. `with arena()` does *not* make that faster
(0.07 s vs 0.06 s on an allocation-heavy loop) — it buys predictable bulk release, not
allocation speed, exactly as `docs/arenas.md:211-228` says. That page is the one place in
the documentation that correctly separates a guarantee from a speed claim.

The rest of the hatch: `[N]T` fixed arrays and `[Enum]T` tables (value types, wire-shaped),
`bytes`, fixed-width integers with wrapping/saturating/bit operations, effect ceilings
(`noalloc`, `noio`, `effects(...)`), `extern def` for direct C calls (`examples/c-ffi`),
`mylang test` for typed guest tests, and `mylang build --report` for build timings.
`noalloc` is genuinely orthogonal — `print`, `list`, `str`, records and ordinary calls all
keep working under it — which is what an escape hatch should feel like.

### 6.2 The sharp edges

1. **The default native mode is Debug.** A plain `mylang build prog.my -o prog` reports
   `"mode":"Debug"`; the same program with `--mode ReleaseFast` runs 3× faster (0.064 s →
   0.023 s on the loop above). A user who asked for speed gets a debug build unless they
   know the flag. Either default to ReleaseFast for `build`, or print the mode in the
   build summary.
2. **The instruction budget stops real programs, in both runtimes.** Both the VM
   (`src/vm.zig:64`) and the native runtime (`src/qbe_runtime.c:273`) default to
   10,000,000 steps, and a 1,000,000-iteration loop exceeds it:

   ```text
   $ mylang run bench.my --print-result
   bench.my:4:18: error[R_STEP_LIMIT]: instruction budget exhausted
   $ mylang run bench.my --print-result --max-steps=500000000      # works
   $ ./bench --max-steps=500000000                                 # native binary, same flag
   ```

   The flag exists (`src/main.zig:560`), but neither `docs/python-syntax.md` nor the README
   mentions budgets, and the diagnostic does not mention the flag. Minimum fix: add
   "raise it with --max-steps=N" to the `R_STEP_LIMIT` message. Better: document budgets as
   a first-class part of running a program, and consider an unbounded default for `run`.
3. **The `f64_*` family is a dead end.** It cannot carry a fractional value (see §4), so
   guest code cannot implement `exp`, `log` or the trigonometric functions that
   `docs/floating-point.md:74` says are missing — the language has no way to reach a float's
   exponent or mantissa. `math.sqrt` is a hand-written Newton loop for exactly this reason,
   as `docs/standard-library.md:72-74` states ("the virtual machine exposes no bit accessor
   for `float` that would reach the `f64_sqrt` intrinsic"). Two consequences: `math.sqrt`
   is **11.6× slower** than the `sqrt` prelude intrinsic it shadows (1.15 s vs 0.099 s for
   300,000 calls, native), and its result is "within one unit in the last place" rather than
   correctly rounded. Fix: give `float` a bits bridge (two functions) or make `math.sqrt`
   call the intrinsic through a non-shadowed name.
4. **Fixed arrays are copied on every call, and native builds make them slower.** The emitted
   QBE for `def touch(values: [8]int) -> int noalloc` starts with `blit %a0, %l0, 64` and the
   call site blits the whole array back in, so an `[N]T` parameter costs a copy per call.
   Measured with 100,000 calls passing a `[1024]int`: native 0.166 s against the VM's
   0.125 s — the "fast path" is the slow one. (A helper measured a 12× native *regression* at
   `[4096]int`, and a `list[int]` over the same loop 25× *faster* than the VM, so the
   managed list is the fast reference type and the fixed array is the slow one.) Nothing
   says this anywhere.
   There is also **no writable, runtime-sized, heap-backed numeric buffer** at all: the
   explicit storage tier was removed on 13 September (`docs/legacy/README.md:8-16`), `[N]T`
   cannot be written in place (`a[0] = 9` → `E_LIST_TYPE`), cannot be sized at runtime
   (`[n]int` → `E_UNKNOWN_TYPE`), and cannot be built from a `list` or `bytes` (`E_TYPE`).
   So a hot numeric kernel has exactly two homes today: a managed `list` (fast natively, GC
   memory) or C. Proposal: pass `[N]T` by reference in QBE (or warn), and state in the guide
   that the managed list is the mutable buffer, `[N]T` is wire data.
5. **`nogc` does not exist, but the design notes tell you to use it.** `def f() -> int nogc:`
   is `E_SYNTAX: unexpected token; expected an indented block`, and `effects(nogc)` is
   `E_UNKNOWN_EFFECT`. `docs/audits/memory-concurrency-2026-09-13.md:43,88-90` recommends
   "keep `nogc` and `noalloc` as the way to *prove* a hot function does not touch the heap".
   Either implement it or correct the note; a documented-but-absent escape hatch is worse
   than an absent one.
6. **C interop cannot see guest data.** `extern def sum_i64(values: [8]int, n: i64) -> i64
   effects(host)` is `E_EXTERN_SIGNATURE: pointers, aggregates and variadic calls are not
   supported`, and the same for `list[int]` (`docs/c-ffi.md:77-80`). Scalar in, scalar out.
   So "move the hot loop into C over my array" — the obvious fallback when the language's
   own buffer story is missing — is not available; the kernel can only be called with
   scalars, one element at a time. C sources linked with `--link` are also compiled by the
   same driver in the same mode, so a `Debug` build's C is unoptimized too.
7. **Measurement is half-built.** `mylang run … --timings` prints real VM nanoseconds and
   `--dispatch=optimized|generic` is a 4.5× A/B switch, but neither flag appears in any doc.
   `mylang build --report` reports *build* phases (frontend, codegen, link) and never run
   time, and a built binary reports nothing about itself, so timing native code means
   `/usr/bin/time`. A performance story needs the second half.
8. **`+=` works only for integers.** `x += 2.0` and `s += "b"` are
   `E_TYPE: operation requires an integer type`; `xs += [2]` and `d[k] += 1` are syntax
   errors. Half a feature is worse than none: either complete augmented assignment for
   floats, strings, lists and subscripts, or document the integer-only rule in the guide.
9. **The escape hatch has no front door.** There is no page that says: write Python-shaped
   code; the VM checks it and runs it; when a function is hot, build it natively for 20–30×
   with `--mode ReleaseFast`; raise the budget with `--max-steps=`; keep `[N]T` off the
   native hot path; call C with `extern def` when you need a library; measure with
   `mylang run --timings` and `/usr/bin/time`. Every fact needed to write that page is in
   this section — a reader currently has to assemble it from `docs/tooling/native-build.md`,
   `docs/c-ffi.md` and the build flags. `docs/python-syntax.md` (the beginner guide) does not
   mention `noalloc`, `nogc`, `noio`, `extern` or `f64_` at all, and `docs/tooling/timings.md`
   disclaims performance thresholds, so nothing in the documentation currently answers
   "when do I reach for the escape hatch?".

---

## 7. Documentation and examples

Documentation is now larger than the compiler it describes and is organized by development
history rather than by reader:

```text
docs/**.md                 236 files   31,644 lines
  docs/*.md (top level)     35 files   11,623 lines   (plan.md + progress.md are 6,667)
  docs/experiments/        125 files   13,701 lines
  docs/legacy/              60 files    4,740 lines
  docs/tooling/             12 files      795 lines
src/**/*.zig                             63,484 lines
```

Specific, verified problems:

- **25 of the 125 `docs/experiments/*.md` pages still contain the removed brace dialect**
  (`fn`, `let`, `T { … }`, `cast<T>`, `::`). One of them, `docs/experiments/domains.md`, is
  the *only* description of `domain` — a feature with no `features.json` entry, no
  doc-coverage gate, and current users (the schematic and the invoice corpus).
- **`features.json` has one stale summary**: `direct-c-scalar-imports-qbe` says "`extern fn`
  declarations", but the surface has been `extern def` since 13 September.
- **The examples teach the previous generation.** 61 of 78 declare `-> i64`; the guide
  teaches `int`. `examples/arrays.my` and `examples/callbacks.my` are the ones a reader is
  most likely to copy.
- **`docs/python-syntax.md` front-loads advanced surface.** The first 50 lines mention
  `todo[int]()`, `wrap[Metres](n)`, `f[T](x)` and eight fixed-width integer names before the
  reader has seen an `if`, a `while`, a `match`, a `Result` or a string method.
- The **formatter cannot help**: `fmt` validates and returns source unchanged
  (`SPEC.md [TOOL-5]`), so old spellings in examples and docs are never rewritten.

Recommendation: three reader-facing documents (guide, reference, performance/tooling), a
`docs/history/` (or `docs/archive/`) holding `plan.md`, `progress.md`, `legacy/` and the
dated experiment pages, and a gate that fails when a *current* page contains a removed
spelling. That last one is cheap: the removed-feature list already exists in
`src/features.json` `removed`.

---

## 8. Recommended sequence

**Step 0 — one-day fixes (no design decisions).** §5.1 one `len`; §5.2 one shadowing rule;
§5.3 delete the source-text scanner and register prelude types unconditionally; §5.4 one
case-spelling rule; §5.5 `math.sqrt` calls the intrinsic; the `R_STEP_LIMIT` message names
`--max-steps=`; `features.json` says `extern def`; delete `push`, the `List` alias, the dead
`std_result` branch, the `&` and `=>` tokens.

**Step 1 — finish the everyday vocabulary (§2.1, §2.2).** List `extend`/`insert`/`pop`/
`remove`/`index`/`reverse`/`sort`/`copy`; `dict.items`/`pop`; prelude `sum`, `min`, `max`,
`sorted`, `abs(int)`, `round`, `any`, `all`, `zip`, `reversed`; slice step; `x[i] += v` and
`d[k] += v`; complete `+=` for float/str/list. This is the recommendation with the largest
effect on "does it feel like Python", and it introduces no new concepts.

**Step 1b — the four program-edge rules (§5.7).** A `main` that returns a renderable
`Result`; `?` on `Option`; `const` for `bytes`/`str` literals; a declared domain
representation conversion. Each is small, each deletes a helper function or a match pyramid
from ordinary application code, and none changes the type system's shape.

**Step 2 — collapse the tiers (§3).** Publish the placement rule in
`docs/python-syntax.md`, then delete the standard-library duplicates and the aliases it
forbids. Expect the string module to lose more than half of its exports.

**Step 3 — one entry command (§2.4).** `mylang run file.my` accepts `module`/`import`/
`export`; `--project` remains for explicit roots.

**Step 4 — the performance story (§6).** Write the page, then make the three claims on it
true: default `build` to ReleaseFast and print the mode; put the escape hatch in the
`R_STEP_LIMIT` message; fix or remove `nogc`; and decide the two structural questions —
whether `[N]T` parameters are passed by reference in QBE (today they are blitted per call,
so native can be *slower* than the VM), and whether `extern def` may take a buffer (today it
is scalar-only, so C cannot be handed the hot array). Document `mylang run --timings` while
you are there, and state plainly that the mutable buffer in this language is a managed
`list`.

**Step 5 — the two design decisions.**
(a) *Methods on classes.* The largest remaining gap to "statically typed Python" is that
`p.norm()` cannot be written. Two options: full methods (receiver binding, resolution
order, and the question of what `self` means for a value record), or the cheap half —
allow `def` inside `class` exactly as inside `domain`, so `Point.norm(p)` namespaces a
function without changing the value model. The cheap half removes the §2.5 asymmetry and
costs a parser/checker change; the full version is a language-design project.
(b) *`lambda` for non-capturing callbacks* (§2.3). No new semantics: the callback type
`def(T) -> U effects()` already exists, and captures are already rejected. `sorted(xs, key=lambda p: p.age)`
is then expressible without touching the closure design.

**Step 6 — documentation consolidation (§7).** One guide, one reference, one performance
page; history out of `docs/`; refresh the 25 brace-era pages and the example corpus to the
`int` surface.

---

## 9. What to keep excluded

Simplicity is also what you refuse to add. These are excluded today and should stay
excluded, with one recommendation each:

- **Exceptions / `try`/`except`/`raise`.** `Result`, `Option` and `?` are the checked path;
  adding exceptions would give the language two error models.
- **Truthiness (`if xs:`).** Conditions requiring `bool` is what makes the static checking
  useful. Document it in the guide's "differences from Python" list (it is there already)
  and keep it.
- **Capturing closures.** Rejected; nested functions and captures would bring lifetimes and
  escaping state. A non-capturing `lambda` (Step 5b) covers the common use.
- **Inheritance, method tables, open extension.** Value records plus unions are what makes
  copying and matching predictable.
- **The dynamic object model** (already in `unsupported`): keep.
- **An implicit filesystem/clock.** Capabilities are the reason `--restrict` means
  something, and the measured cost is small: 17 capability parameters across 7,475 lines,
  never threaded deeper than two calls, and `--restrict` refuses before the first guest
  instruction executes.
- **Block-scoped locals.** The measured cost is one dead initializer in 7,475 lines and zero
  `if`/`else`-assigns-then-read sites, and it removes Python's unassigned-variable bug class.
  Keep, and keep it documented.
- **`E_EXPLICIT_DISCARD_REQUIRED`.** Four characters at 88 sites, in exchange for making a
  silently dropped `Result` impossible. Keep.
- **`domain`** is the one item on this list I would *not* keep in its current limbo: either
  it becomes a documented feature (with the `wrap`/`unwrap`/`private` spelling decided, a
  `features.json` entry, and the §5.7 conversion rule) or it goes with the A2 tier. A feature
  that only the fixtures use and only a brace-era page describes is exactly the sort of thing
  this audit exists to find.

---

## Appendix A — measurements

All timings on the development machine, 14 September 2026, `zig-out/bin/mylang`, native
builds with `--mode ReleaseFast` unless noted. Loop budget raised with `--max-steps=`.

| Program | VM | Native Debug | Native ReleaseFast |
| --- | --- | --- | --- |
| 1M iterations: `total = (total + i) % 1000003` | 0.62 s | 0.064 s | 0.023 s |
| 200k `list.append` + sum | 0.345 s | — | 0.017 s |
| 20k `dict[str,int]` read-modify-write with `str(i % 997)` | 1.56 s | — | 0.046 s |
| 50k × (build a 50-element list) | — | — | 0.05 s, 1.8 MB peak RSS |
| 200k × (build a 10-element list) inside `with arena()` | — | — | 0.07 s, 1.8 MB |
| 200k × (build a 10-element list) without arena | — | — | 0.06 s, 1.8 MB |
| 300k `math.sqrt(float(i % 1000) + 1.0)` | — | — | 1.15 s |
| 300k prelude `sqrt(float(i % 1000) + 1.0)` | — | — | 0.099 s |
| 100k calls passing a `[1024]int` by value | 0.125 s | — | 0.166 s (VM is *faster*) |
| 100k iterations reading `data[i]` from a `[4096]int` parameter (reported) | 0.058 s | — | 0.706 s (12× regression) |

Build cost: a cold native build of a one-function program took 11.1 s
(`codegen 1.09 s`, `link 9.98 s`); the checkout's own tooling reports warm rebuilds in the
0.09 s range once objects are content-addressed in `.mylang-cache/qbe`.

Surface counts: 86 reserved word spellings (78 `words` + 5 aliases + 3 operator words);
27 of the 78 words appear in zero current `.my` sources; 102 implemented features (75
language, 27 tooling) and 5 unsupported; 10 standard-library modules with 189 top-level
`def`s, 40 of which return `Result`; 78 example files; 23 compiler subcommands besides
`test`, `build` and `doc-coverage`.

---

## Appendix B — probe log

Every row is one file under `/tmp/audit/`, run as
`zig-out/bin/mylang run FILE.my --print-result` (or `check`/`check-project` where noted)
against the build of 14 September 2026. Quoted text is the first line of the diagnostic.

**Python idioms that work.** `xs.append(2)`; `len(xs)`; `xs[-1]`; `xs[0:2]` (copies);
`rows[1][0]`; `rows[0][0] = 9`; `2 in xs`; `3 not in xs`; `d["b"]`; `"a" in d`;
`d.get(k, 0) + 1`; `"," .join(parts)`; `"a,b".split(",")`; `"ab".upper().lower()`;
`s[0] == "a"`; `len("héllo") == 5`; `s[1] == "é"`; `[value * 7 for value in source if value > 2]`;
`for i, v in enumerate(xs)`; `range(len(xs))`; `while True: ... break`; `42` from
`match int("42")`; `x = checked(42)?`; `print("a", 1, True, sep="-")`; `assert 1 == 1, "ok"`;
`print(P(x=1, items=[1,2]))` → `P(x=1, items=[1, 2])`; `print({"a": 1})` → `{'a': 1}`;
`print(b"AB")` → `b'AB'`; `print(True, False, None)`; `print(0.1 + 0.2)` → `0.30000000000000004`;
`elif`; `pass`; `_ = Marker()`; a record updated through a list slot.

**Python idioms that fail** (with the exact diagnostic): `xs.extend/pop/insert/remove/index/reverse/sort/copy`;
`xs.push` works but is undocumented; `xs[0] += 5` (E_SYNTAX); `xs[0:4:2]` (E_SYNTAX);
`a, b = b, a` (E_SYNTAX); `d.items()` (E_ITERATION); `d["a"] += 1` (E_SYNTAX);
`x += 1.0` (E_TYPE); `s += "b"` (E_TYPE); `min/max/sum/sorted/reversed/round/any/all/pow/divmod/chr/ord/hex/bin/isinstance/map/filter/zip/repr/format/hash` (E_UNKNOWN_FUNCTION);
`abs(0 - 42)` (E_TYPE: requires a float argument); `list(range(3))` (E_UNKNOWN_FUNCTION);
`x is None` (E_SYNTAX); `x == None` (E_TYPE); `None == None` (E_TYPE: aggregate equality is
not defined); `42 if x > 0 else 0` (E_SYNTAX); `0 < x < 10` (E_TYPE); `if xs:` (E_TYPE);
`lambda x: x + 1` (E_SYNTAX); nested `def` (E_EXPRESSION); `"""doc"""` (E_SYNTAX);
`r"..."` (E_SYNTAX); `s.ljust(5)` / `s.rjust(5, ".")` (E_COLLECTION_METHOD);
`"ab" * 3` (E_TYPE); `[1] + [2]` (E_TEXT_OPERATOR); `str(b"hi")` (E_TEXT_CONVERSION);
`bytes("hi")` (E_BYTES_CONVERSION); `back: str = raw.decode()` (E_TYPE: expected str, found
Result<str,str>); `try`/`except`/`raise` (E_SYNTAX); `p1 == p2` for records (E_TYPE);
`class C: def m(self)` (E_SYNTAX); `class C(Base)` (E_SYNTAX); `class C: x: int = 3` (E_SYNTAX);
`import math` in a file run with `mylang run` (E_SYNTAX at 1:1); `LIMIT = 5` at top level
(E_SYNTAX; `const LIMIT: int = 5` works); `range(0, 10, 2)` (E_ARITY);
`{K.a: 1}` as a `dict` (E_DICT_KEY: keys must be int or str; `[K]T` tables are the spelling).

**Consistency probes.** `len(items)` → `3` vs `n: int = items.len()` → `E_TYPE: expected
i64, found u64`; declared `len` ignored, declared `sqrt` wins; `List[int]` accepted;
`x = ()` accepted; `Option.some(42)` / `Result.ok(42)` rejected while `case Result.ok(v)` /
`case Option.some(v)` are accepted; `4 // 2; raw: bytes = "hi".encode()` →
`E_UNKNOWN_TYPE` in one line order and `4` in the other; `raw = "hi".encode()` without a
`bytes` token → `E_COLLECTION_METHOD`; `import std_result` → `E_MODULE_READ ... NotFound`;
`6 & 3` → `E_TOKEN: unexpected character in source`; `bit_and(6, 3) + bit_or(1, 2) +
shift_left(1, 3)` → `13`; `f64_add(1.5, 2.5)` → `E_FLOAT_OPERATION`;
`f64_to_u64(f64_sqrt(f64_from_u64(16)))` → `4`; `f64_to_u64(4.0)` → `E_TYPE: expected u64,
found float`; `domain Document: int:` + `Document.id(document)` works while
`document.id()` → `E_UNKNOWN_TYPE`.

**Runtime probes.** `mylang run bench.my --print-result` → `R_STEP_LIMIT` (1M iterations);
the same with `--max-steps=500000000` → `6`; the native binary without the flag →
`R_STEP_LIMIT`, with it → `6`; `mylang build --report` reports `"mode":"Debug"` for a
default build; `mylang check-project` on a module with `import math` and a prelude `sqrt`
call succeeds and builds natively.

**Program-edge probes (§5.7).** `const IMPORT: bytes = b"import"` and
`const NAME: str = "hello"` → `E_CONSTANT_EXPRESSION`; `def main(fs: Filesystem) ->
Result[None, str]` → `E_TYPE: main must return int, None, or Result<None/int,int>`;
`v = lookup(x)?` on an `Option` → `E_TRY_TYPE: try requires a declared fallible result`;
`unwrap(c)` on a domain value outside its domain → `E_PRIVATE_DOMAIN`; `n: i64 = c` where
`c` is a domain value → `E_TYPE: expected i64, found Cents`.

**Corpus probes (§2.6).** `mylang run-project examples/corpus/invoice/main.my --print-result`
→ `7019`, and `schematic-svg --project src/schematic/guest …` reports `SCHEMATIC_17`, so the
measured corpus is live code, not dead fixtures. The three task programs (file line count,
dictionary of counts, record totals) were each run to completion and print the same values
as their Python equivalents.

---

## Appendix C — limits of this audit

- These are single-sample timings on one machine, intended to establish order of magnitude
  and relative cost, not to certify performance.
- No implementation change, build, or Guardian gate was run; the citations are to the tree
  as it stands at `5adafee`.
- The "unused keyword" counts are uses in *shipped guest source* (examples, standard
  library, schematic, fixtures). A keyword used only by compiler tests or by an embedding
  host is counted as unused here even though removing it would break that caller.
- The recommendations about methods, tuples and record equality are design opinions with
  costs I have not estimated in implementation days; the measurements, counts and
  contradictions above are the parts intended as evidence.
