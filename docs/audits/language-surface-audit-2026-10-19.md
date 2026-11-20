# Language surface audit (19 October 2026)

A read-only measurement of what the current `mylang` asks a reader to learn,
and a ranked list of what can be removed or consolidated. No source was
changed, no gate was run; every number below was measured against the tree at
`719975b8f3` with a freshly built `zig-out/bin/mylang` (the installed binary
predated the `def` → `func` rename and could not be used for probes).

The audit's starting point is
[the surface-simplification design of 13 October](../design/surface-simplification-2026-10-13.md),
which already decides the direction: user types keep no methods, scalar domains
are gone, the effect system is deleted, and waves 1–3 are removing
comprehensions, lambdas, tuples, `in` on lists, sequence repetition, negative
indexes, `str`-as-bytes and copy-slices. This document does not revisit those
decisions. It answers a narrower question: **what does the surface still cost
that the wave programme has not yet touched?**

## 1. The budget

| Surface | Count | Where it lives |
| --- | ---: | --- |
| Reserved words | 94 | `src/lexer.zig` (`keyword_words` 80 + `keyword_aliases` 14) |
| — live | 41 | |
| — **dead, still reserved** | **41** | |
| — reserved for one position only | 4 | `union`, `replace`, `unwrap`, `len` — see §2.1 |
| — internal | 8 | 5 `__` spellings, plus `clock_now`, `random_u64`, `environment_get` |
| Feature registry entries | 232 implemented (155 language, 77 tooling) + 57 removed + 23 limits | `src/features.json` |
| Diagnostic codes | 338 (272 `E_`, 27 `L_`, 36 `R_`, 3 `W_`) | `src/diagnostic_codes.zig` |
| Standard-library modules | 23 | `src/stdlib/*.my` |
| Standard-library public functions | 219 | `src/stdlib/*.my` |
| Built-in method spellings | 65 (over 113 operation kinds) | `src/buffer_operations.zig` |
| Type spellings | 8 integer widths + `int` + `float` + `str` + `bytes` + `T[]` + `T?` + `FixedArray[T, N]` + `Result[T, E]` + `Unit` | `list[T]`, `Option[T]` and `[N]T` are already refused — §6 |
| Declaration forms | `func`, `const`, `type`, `record`, `enum`, `result`, `resource`, `import`, `extern func` | `union`, `domain` and `export` are refused as declarations |
| Attribute kinds | 7: `@deprecated`, `@noalloc`, `@test`, `@allow`, `@requires`, `@ensures`, `@invariant` | `src/ast.zig` |

Corpus sizes, split the way the gate splits them:

| Corpus | Files | Lines | In the gate? |
| --- | ---: | ---: | --- |
| `examples`, `src/stdlib`, `bench`, `benchmarks`, `selfhost/components` | 188 | 11,876 | yes (`test-program-check`) |
| `selfhost/` | 48 | — | **no** |
| `velocity/` | 125 | — | **no** |
| `experiments/` | 12,485 | 1,271,192 | **no** (generated history, 4,992 distinct files) |
| `tests/`, `test/` (guest) | 751 | 51,985 | yes (`test-lang`, `test-cli`) |
| `src/`, `src/core/` (Zig) | — | 253,045 / 111,439 | |
| Zig tests | 368 files | 106,046 | |
| `docs/` | 880 files | 163,377 (50 language-facing pages) | `doc-coverage` gate |

## 2. Finding 1 — the reserved-word namespace is 44 % dead

41 of 94 reserved words name something that no longer exists. They cannot be
used as identifiers, they must each keep a diagnostic, and 14 of them have no
migration path at all.

| Group | Words | Count | Migration today |
| --- | --- | ---: | --- |
| Old binary64 operations | `f64_add` `f64_sub` `f64_mul` `f64_div` `f64_eq` `f64_lt` `f64_le` `f64_sqrt` `f64_floor` `f64_ceil` `f64_trunc` `f64_abs` `f64_neg` `f64_from_u64` `f64_to_u64` | 15 | `E_REMOVED_SPELLING` |
| Old `u64` bit / wrapping / saturating operations | `bit_and` `bit_or` `bit_xor` `shift_left` `shift_right` `wrapping_add` `wrapping_sub` `wrapping_mul` `saturating_add` `saturating_sub` `saturating_mul` | 11 | **none** — raw "unexpected token" |
| Old capability names | `filesystem_cap` `network_cap` `clock_cap` `random_cap` `environment_cap` `restrict_resource` | 6 | `E_REMOVED_SPELLING` |
| Old codec names | `codec_encode` `codec_decode` | 2 | `E_REMOVED_SPELLING` |
| Domain era | `domain` `wrap` `conversion` `private` `arena` | 5 | `arena` → `E_ARENA_REMOVED`, `wrap` → `E_DOMAIN_REMOVED`; `domain`, `conversion` and `private` are raw |
| Declaration aliases | `def` `class` | 2 | `def` names `func`; `class` explains why it is refused |

Every one of these is a word a user might reasonably want: `wrap`, `private`,
`domain`, `conversion`, `shift_left`, `def`. Each is a permanent tax on the
identifier namespace for no benefit.

**Recommendation.** Unreserve all 41. Fourteen of them (the 11 bit/wrapping
words, `domain`, `conversion`, `private`) need a `mylang fix` rewrite from the
removed spelling; the other 27 already say something useful — 23 with
`E_REMOVED_SPELLING`, and `arena`, `wrap`, `def` and `class` with a removal or
rejection message of their own — so they need only the "reserved" check
dropped. This is the cheapest surface reduction in the language: no working
program changes, and the only migration is for code that already fails to
compile.

Three of the dead words are missed by a naive reading of
`src/removed_names.zig`, which holds 28 entries but only 23 reserved words —
`len` is in it and is *live*, and `restrict_resource` is not in it but is a
lexer keyword with its own `E_REMOVED_SPELLING` at `src/parser.zig:2440`.

### 2.1 Words reserved for one position only

Four more words are reserved globally but are only meaningful in a single
syntactic position. The parser already contains the special case; the lexer
only has to stop reserving the word.

| Word | Needed only as | Where the special case lives |
| --- | --- | --- |
| `union` | `s.union(t)`, a set method | `src/parser.zig` `memberName` and `parseMemberSuffix` already accept it after a dot; the *declaration* form is already refused ("declare all non-result variants with `enum`") |
| `replace` | `s.replace(a, b)` (a string method) and the record-update `record { x = 1 }` form | `src/parser.zig:1961` and `:2630` already special-case `kw_replace` |
| `unwrap` | nothing — but `x.unwrap` earns a *hint* | `src/parser.zig:2204` refuses `x.unwrap` with "extract with `match`" rather than letting it become a method name; the global use is the retired domain form |
| `len` | `len(xs)` (a prelude builtin), `for x in len(xs)`, and the removed `xs.len()` | `src/parser.zig:2610` and `:2616` already special-case `kw_len` |

**Recommendation.** Make `union`, `replace` and `unwrap` contextual keywords:
the lexer emits an ordinary identifier, and the member-name path keeps
matching the text for `union` and `replace`. For `unwrap` the member path
deliberately does *not* match — it turns `x.unwrap` into a hint — so making
the word contextual would cost that hint, and the hint's text would have to
move into the checker. `len` becomes a soft builtin name like `int`, which also
removes the last inconsistency in Finding 5's "soft versus hard type names".
This frees four more ordinary words at the cost of four one-line parser
checks.

## 3. Finding 2 — `selfhost/` and `velocity/` are outside the language

`scripts/check_programs.py` sweeps `bench`, `benchmarks`, `examples`,
`src/stdlib` and `selfhost/components`. It does not sweep `selfhost/` or
`velocity/`. Those two trees are 173 files of Python-era code that the current
compiler rejects:

```
selfhost     files=48    FAILING=36
velocity     files=125   FAILING=125
tests/lang   files=362   FAILING=0
examples     files=93    FAILING=0
src/stdlib   files=36    FAILING=0
```

Every one of the 125 `velocity/` files fails, and 36 of 48 `selfhost/` files
fail. They use `def`, `module X` headers, `pass` blocks and other spellings
that were removed months ago. `selfhost/` and `velocity/` hold 220 of the
repository's `def` sites — **all** of the live ones; every other `def` in the
tree is a deliberate migration fixture.

This matters for the audit in two ways:

1. **Any measurement taken over "the repository" is wrong.** The first pass of
   this audit measured production usage over
   `examples src/stdlib selfhost bench benchmarks velocity` and concluded that
   `base64` and `hashes` were unused. They are called 24 and 14 times
   respectively in the corpus that actually compiles. The two stale trees hold
   173 files against the checked corpus's 188, so a naive measurement is
   dominated by code that does not run. The corrected numbers
   below use only checked code.

2. **A measurement taken over the standard library counts the library using
   itself.** The same first pass counted 1,004 calls from `src/stdlib` into
   `src/stdlib` alongside 106 from application code, and concluded that the
   library was healthy. Splitting the callers apart changes the verdict
   entirely — see Finding 8.
3. **The self-hosting claim is currently unbacked.** 173 files of
   self-hosting code that no gate compiles cannot support a statement that the
   language can implement itself.

There is a third tree, and it is far larger than the other two. `experiments/`
holds **12,485 `.my` files and 1,271,192 lines** — 82 % of all guest code in
the repository, and more than the checked corpus and the test suite combined
by a factor of 22. It is generated experiment output, not source:

- **Only 4,992 of the 12,485 files have distinct content.** 140 of the 260
  directories holding 50 or more files are byte-identical copies of an
  earlier one; `experiments/fu-port-20261009/fuzz50-port-migrated3/` alone
  has 14 identical copies of four separate 50-file directories.
- **It is written in a retired dialect.** 60,343 `def` against 24,688 `func`;
  17,060 `case Some(...)` / `case None:` match arms; 52,996 `dict[` / `list[`
  type spellings. 7,914 of the 12,485 files use `def` and cannot compile at
  all.
- A minority — the `micro-ownership-20261012/parity/original/` files, for
  instance — still checks cleanly, so the tree is a mix of eras.

`experiments/` is process history and belongs with `docs/audits/` and
`docs/experiments/` (Finding 9), not in the source tree, where it is the
single largest source of measurement distortion in the repository.

**Recommendation.** Decide whether `selfhost/` is still live. If it is, make it
compile and add it to the swept roots — that is a large, visible job and it
belongs to a wave, not to a cleanup. If it is not, delete it (or move it
under `docs/legacy/`) so it stops distorting every corpus measurement. Either
way the gate's root list and the tree should agree.

`experiments/` is the easier half of the same problem and can be settled
first: it is generated output, not source, and moving it out of the source
tree (or under `docs/`) removes 82 % of the repository's guest code from
every future measurement without touching the language at all. The archive
policy for generated experiment output is already written down in
`docs/tooling/cache-retention.md`; this tree just has not been placed under
it.

## 4. Finding 3 — the `def` alias

`def` is lexed to the same tag as `func` and then rejected by the parser with
`E_FRONTEND_SYNTAX: declare a function or callable type with 'func'`. It is
therefore **not an alias**: it is a reserved word that always fails.

- Working code using `def`: **0** (the 220 sites are the stale `selfhost/` and
  `velocity/` trees of Finding 2).
- Deliberate migration fixtures using `def`: 13 files under `test/` and
  `tests/fixtures/`.
- Cost today: one lexer alias, one parser error, one diagnostic row, one
  `features.json` entry, and the word `def` permanently unavailable as an
  identifier.

**Recommendation.** Delete the alias outright. It is the clearest case in the
language of a spelling kept for a compatibility window whose only remaining
users are broken.

## 5. Finding 4 — eight integer widths for four of them

Measured over the checked production corpus:

| Type | Production sites | Test sites |
| --- | ---: | ---: |
| `i8` | 0 | 139 |
| `i16` | 0 | 128 |
| `i32` | 2 | 120 |
| `i64` | 28 | 693 |
| `u8` | 44 | 209 |
| `u16` | 8 | 82 |
| `u32` | 24 | 127 |
| `u64` | 59 | 207 |
| `int` (the `i64` alias) | 1,143 | 5,977 |

`int` is by far the dominant spelling, and `u8`/`u32`/`u64` carry the byte and
word work. `i8`, `i16` and `i32` have **no** production use; their 387 test
sites are the only thing keeping them alive.

Each width costs a type identity, a conversion path, a set of arithmetic
operations, an overflow rule, a literal form and a diagnostic. Eight widths
where the corpus needs four is four widths of pure surface.

**Recommendation.** Keep `int` (= `i64`), `u8`, `u32`, `u64`; retire `i8`,
`i16`, `i32` and `u16`. That is four widths to remove, not eight, and it is
the version of the change that the corpus supports. The unsigned *and* signed
pairing also goes away: `u8`/`i8` → `u8`, `u32`/`i32` → `u32`.

**Related, and cheaper.** `int` is *not* a reserved word: `const int = 5`
compiles (with only an unused-binding warning), while `const bool = 5` is a
syntax error. `float`, `str` and `bytes` are shadowable only because they
collide with prelude conversion functions (`E_SHADOWING`). The type vocabulary
is therefore half hard-keyword and half soft-name, which is harder to explain
than either policy alone. Making `int`, `float`, `str` and `bytes` keywords
would cost four reserved words and buy a uniform rule — or, if the soft names
are preferred, `bool` should stop being a keyword.

## 6. Finding 5 — the duplicate type spellings are already gone

| Operation | Spelling A | Spelling B | Status of B |
| --- | --- | --- | --- |
| Sequence | `T[]` | `list[T]` | **already refused** |
| Absence | `T?` | `Option[T]` | **already refused** |
| Fallible | `Result[T, E]` | `result T` decl | a genuine distinction |
| Fixed array | `FixedArray[T, N]` | `[N]T` | **already refused** |

A grep census suggested three live duplicate spellings (`list[T]` at 18
production and 40 test sites, `Option[T]` at 11 test sites). The compiler says
otherwise — all three losers are already refused:

```
mut xs: list[int] = [1, 2]
      ^ error[E_FRONTEND_SYNTAX]: use the canonical array, optional or Unit type spelling
```

`Option[T]` and `[N]T` report the same error. `src/features.json:447` names
the surviving set — `T[]`, `T?`, `FixedArray[T, N]`, `Unit` and
`Result[T, E]` — and `list[T]` is not in it.

The 18 production `list[` hits are all inside comments:

```
bench/parity/suite/sieve.my:3:# sieve: Eratosthenes over a list[bool] of n + 1 flags
bench/parity/suite/matmul.my:1:# matmul: n x n float matrices as list[list[float]]
```

and every test-side hit is inside `test/fixtures/fix-migration/`, which
deliberately holds pre-migration code. **There is no duplicate spelling left
to retire**; the census was reading comments and fixtures.

`Result[T, E]` versus the `result` declaration stays a genuine *distinction*:
one is a value type, the other a named declaration.

**What remains is one broken message.** `src/removed_names.zig` maps the
removed `List` onto `list[`:

```
`List[T]` was removed; use `list[T]`
```

but `list[T]` is itself refused, so the message sends a user to a spelling the
compiler rejects. The *fix machinery* is sound — `mylang fix` runs two rounds
and lands on `int[]`:

```
$ mylang fix prog.my
fixed prog.my: 2 edits (E_REMOVED_SPELLING, E_FRONTEND_SYNTAX)
```

**Recommendation.** Change the `List` message to name `T[]`. One string, no
migration.

## 7. Finding 6 — three tiers of callable, two of them duplicating

The language currently offers the same operation in up to three places:

1. a **prelude builtin** (unqualified, compiler-implemented),
2. a **method** on a built-in type (`xs.append(x)`, `s.strip()`),
3. a **standard-library function** (`strings.strip(s)`, `lists.append(mut xs, x)`).

The design of 13 October already settles the method/stdlib question — "no
methods on built-in types either" — so the method tier is scheduled to
disappear into the module tier. The **prelude tier is not covered by any
wave**, and it is where the semantic conflicts live.

The method tier is large: 65 spellings over 113 operation kinds
(`src/buffer_operations.zig`), and 1,843 method calls in the checked
production corpus. 22 of the 65 spellings also name a standard-library
function (`append`, `count`, `encode`, `decode`, `find`, `get`, `insert`,
`join`, `lower`, `lstrip`, `remove`, `replace`, `reserve`, `rstrip`, `strip`,
`upper`, `clear`, `difference`, `append_array`, `append_byte`, `append_float`,
`append_int`, `append_range`) — a name collision is not always a semantic
duplicate (`pool.get` and a dictionary's `get` differ), but each one is a
second thing a reader has to disambiguate by tier.

| Operation | Prelude | Standard library | Conflict |
| --- | --- | --- | --- |
| `abs` | `abs(x)` — infallible, integer or float | `math.abs(x: int) -> Result[int, str]` | **different types and failure modes for one name** |
| `sqrt`, `floor`, `ceil`, `trunc` | `sqrt(x)`, `floor(x)`, … (unqualified, no import) | `math.sqrt(x)`, `math.floor(x)`, … | the same operation at two tiers; `math.my` says it "shadows the prelude helper" |
| `round` | `round(x)` / `round(x, n)` | `math.round(x: float)` | the two-argument form has no module twin |
| `min` / `max` | `min(a, b)` or `min(xs)` | `math.min[T: integer](a, b)` | near-duplicate; the module form is generic and the prelude form folds a list |
| `sum` | `sum(xs)` — a list of numbers | `time.sum(a, b)` — two `Duration`s | **unrelated meanings under one name** |

`abs` is the sharp case, and it is verified: `abs(-5)` binds an `int`, while
`math.abs(-5)` binds a `Result[int, str]` that the compiler then rejects with
`E_RESULT_UNHANDLED` if the program does not handle it. The same name means
"a number" in one tier and "a number or a failure" in the other. A reader has
to know which tier they are in to know what a call means.

`time.sum` is the other sharp case: the prelude's `sum` adds a list of
numbers, `time.sum` adds two durations, and the only thing they share is the
word.

### 7.1 The method tier is a Python API clone, and the compiler already knows better

The method tier's 65 user-facing spellings are not mylang-designed. **56 of
them are exactly the name Python's `list`/`str`/`set`/`dict`/`bytes` API
uses**, and the 22 most distinctly Python of those are compound or
Python-specific: `startswith`, `endswith`, `isdisjoint`, `issubset`,
`issuperset`, `symmetric_difference`, `setdefault`, `find_any`, `to_list`,
`scalar_count`, `zfill`, `splitlines`, `isalpha`, `isdigit`, `isspace`,
`exchange`, `encode`, `decode`, `hex`, `view`, `borrow`, `pop`, `items`.
Those 22 account for 111 calls in the checked production corpus and 401 in
the tests.

This matters more for wave 2 than it first appears, because of something the
source already contains. `src/buffer_operations.zig` keeps two vocabularies:
a `Kind` enum of 113 internal operation names, and a table mapping user-facing
spellings onto them. **For 23 of the 65 spellings the two differ, and the
internal name is always the mylang-native one:**

| User-facing (Python) | Internal `Kind` | User-facing (Python) | Internal `Kind` |
| --- | --- | --- | --- |
| `startswith` | `starts_with` | `issubset` | `set_subset` |
| `endswith` | `ends_with` | `issuperset` | `set_superset` |
| `isalpha` | `is_alpha` | `isdisjoint` | `set_disjoint` |
| `isdigit` | `is_digit` | `symmetric_difference` | `set_symmetric_difference` |
| `isspace` | `is_space` | `union` / `intersection` / `difference` | `set_union` / `set_intersection` / `set_difference` |
| `index` | `index_of` | `add` / `discard` | `set_add` / `set_discard` |
| `borrow` | `borrow_view` | `append_*`, `reserve` | `buffer_append_*`, `buffer_reserve` |

So the compiler already dispatches on mylang-native names and merely accepts
Python spellings as a second front door. That has two consequences:

1. **Wave 2 is cheaper than it looks.** The module function that replaces
   `xs.append(x)` does not need a new name designed for it — the `Kind` name
   is the name the compiler already uses. Ten of the 22 Python-isms
   (`startswith`, `endswith`, `isalpha`, `isdigit`, `isspace`, `isdisjoint`,
   `issubset`, `issuperset`, `symmetric_difference`, `borrow`) have their
   native alternative already written down in the source, covering 20
   production and 99 test call sites. The other 12 need a name chosen, over
   91 production and 302 test call sites.
2. **The Python spellings are a removable layer, not a migration.** Because
   the native name is already the dispatch name, dropping the Python spelling
   is a table deletion, not a rewrite of the operation.

**Recommendation.** When wave 2 retires the method tier, name each module
function after its `Kind`, not after its Python spelling — and retire the
Python spellings in the same change rather than carrying them into the module
tier. This also removes the one thing that most makes the method tier look
foreign: a reader who knows Python sees `startswith` and expects it to mean
what CPython means.

### 7.2 The set type is a nine-operation surface with one use

`set[T]` appears **once** in the checked production corpus
(`benchmarks/runtime/expanded/collections/main.my:145`, `mut dedup: set[int]
= set()`) and 31 times in the tests. Against that single use the compiler
carries:

- 9 `set_*` operation kinds (`set_add`, `set_discard`, `set_union`,
  `set_intersection`, `set_difference`, `set_symmetric_difference`,
  `set_subset`, `set_superset`, `set_disjoint`),
- 9 user-facing method spellings for them,
- and two dedicated API helpers, `setMethodSpellings()` and
  `unionMethodSpellings()`, in `src/buffer_operations.zig`.

The other set spellings the census found are not the set *type* — `public
func set[T: copy + storable](...)` in `src/stdlib/pool.my` is a function
*named* `set`, and `set()` in the benchmark is the constructor.

**Recommendation.** This is the clearest case for the "used or gone" policy in
Finding 8, and it should be settled by name rather than by principle: either
the set type gets a real place in the language, with a module tier that earns
its nine operations, or it is retired with the rest of the collection tier.
What should not happen is wave 2 creating a `set` module of nine functions
for one call site.

**Recommendation.** Give the two tiers different names, and let one tier own
each operation. The cheap shape is: the prelude keeps the operations that have
no module home (`len`, `range`, `sum`, `any`, `all`, `min`, `max`, `abs`,
`round`, `sorted`, `repr`, `ord`, `chr`) and the *numeric* operations move
fully to `math` — so `math.abs` becomes the only `abs` and the prelude keeps
nothing `math` also names. `time.sum` needs a different name (`time.add`),
which is a two-line change in one module.

## 8. Finding 7 — two attributes with no users, and one that cannot be reached

The contract attributes turned out better than expected. All three of
`@requires`, `@ensures` and `@invariant` are **enforced at run time**:

```
@ensures(result > 0)          -> R_ENSURES: postcondition violated
@requires(value > 100)        -> R_REQUIRES: precondition violated
@invariant(self.value > 0)    -> R_INVARIANT: invariant violated
```

(`@invariant` takes a `self.field` form and attaches to a `record`.) They are
rarely used, but they are real, and the design's proposal 7 (public signatures
name their dictionaries) expects more of them. They stay.

What is left is smaller:

| Attribute | Production | Test | Status |
| --- | ---: | ---: | --- |
| `@noalloc` | 4 | 23 | enforced mechanically in Core |
| `@requires` | 1 | 9 | enforced at run time |
| `@ensures` | 1 | 12 | enforced at run time |
| `@invariant` | 4 | 6 | enforced at run time |
| `@allow` | 0 | 15 | lint waiver; its whole purpose |
| `@deprecated` | 0 | 1 | **no checker behind it** |
| `@test` | 0 | 1 | **no checker behind it** |

`@deprecated` and `@test` have one use each and nothing enforces them. A
`@deprecated` that never warns is a comment with extra syntax.

`@invariant` has a smaller defect: its "wrong target" diagnostic says
"`@invariant` attaches to a `record` or a `domain` declaration", but `domain`
was retired in wave 1. The message names a form the language no longer has.

**Recommendation.** Give `@deprecated` and `@test` a checker or retire them
(one use each, no enforcement). Fix the `@invariant` message to name only
`record`.

The declaration forms need a decision too. Measured over the checked
production corpus:

| Form | Production | Test | Note |
| --- | ---: | ---: | --- |
| `union` declaration | 0 | 0 | **already refused**; the word survives only as the set method `s.union(t)` — see §2.1. The 19 test occurrences of the word are all method calls, not declarations |
| `type` alias | 0 | 5 | **no application code uses it at all**; the design's proposal 7 wants *more* of these, so it stays |
| `resource` declaration | 4 | 4 | 8 sites in the whole corpus |
| `with` statement | 7 | 40 | a capability-scoping form (`with try fs.open(p) as f:`) |
| `todo[T]()` hole | 0 | 1 | |
| format string `f"..."` | 32 | 181 | a real feature (`src/format_strings.zig`); one expression hole with an optional `:spec` suffix, `{{`/`}}` escapes |
| `zip(...)` | 0 | 8 | a prelude builtin; the 8 test sites include two `tests/fixtures/idioms/` migration fixtures for the retired comprehension syntax |

`enum` (16 production declarations) and `result` (25) earn their keep. `type`,
`resource`, `with` and `todo` are thin but each is coherent and each is
mentioned in the design's remaining proposals, so they are not worth
removing for size alone.

## 9. Finding 8 — the standard library is heavily used by tests, lightly by code

The first pass of this audit measured standard-library use over the whole
checked corpus and concluded that the library was fine: 219 functions, 212 in
use. That measurement was **inflated by the library using itself**. Splitting
the callers apart:

| Caller | Calls into the standard library |
| --- | ---: |
| `src/stdlib` (library-internal) | 1,004 |
| `examples/`, `bench/`, `benchmarks/`, `selfhost/components/` | 106 |
| `tests/`, `test/` | 1,359 |

**90 % of the apparent production use was the library calling itself.** With
the honest denominator — application and harness code — the picture is:

| Module | Functions | Calls from app code | Calls from tests | Functions never called from app code |
| --- | ---: | ---: | ---: | ---: |
| `json` | 21 | 33 | 272 | 11 |
| `network` | 24 | 21 | 179 | 8 |
| `time` | 16 | 22 | 68 | 6 |
| `random` | 9 | 14 | 26 | 5 |
| `byte_builder` | 13 | 6 | 105 | 9 |
| `http` | 11 | 4 | 16 | 7 |
| `strings` | 32 | 3 | 162 | 30 |
| `sort` | 12 | 2 | 9 | 11 |
| `lists` | 3 | 1 | 33 | 2 |
| `math` | 26 | 0 | 217 | 26 |
| `path` | 11 | 0 | 12 | 11 |
| `pool` | 9 | 0 | 75 | 9 |
| `memo` | 6 | 0 | 84 | 6 |
| `csv` | 5 | 0 | 0 | 5 |
| `base64` | 6 | 0 | 7 | 6 |
| `hex` | 4 | 0 | 16 | 4 |
| `hashes` | 1 | 0 | 13 | 1 |
| `cache_record` | 3 | 0 | 10 | 3 |
| `durable` | 2 | 0 | 25 | 2 |
| `persistent_memo` | 2 | 0 | 9 | 2 |
| `filesystem` | 1 | 0 | 17 | 1 |
| `environment` | 1 | 0 | 4 | 1 |
| `parallel` | 1 | 0 | 0 | 1 |

**52 of 219 functions are called from application code; 167 are not.**
Fourteen of the 23 modules are never called from application code at all.

The striking rows are the *tested but unused* modules: `math` has 217 test
calls and 0 application calls; `strings` has 162 and 3; `path` 12 and 0;
`pool` 75 and 0. These are not dead code — they are exercised — but nothing
in the corpus needs them.

That is not automatically wrong. A standard library is supposed to be wider
than its first users, and this corpus is small: 93 example files, mostly small
language demos, plus 49 benchmark files. The cost of the width is concrete
though — 219 public functions, of which 101 are named in the 1,648-line
`docs/standard-library.md`, and every one of them is a name, a signature, an
error case and a documentation obligation.

**Recommendation.** This is the one place where the wave programme's plan and
the surface audit pull in opposite directions, so it needs a decision rather
than a cleanup. Proposal 1 of the design *moves* 65 method spellings into
modules; if the module tier is not consolidated in the same wave, wave 2
relocates the method tier into a library that is already 4× wider than its
users need. The two candidate policies:

- **Consolidate while moving.** Each operation gets exactly one home. The
  method tier and the module tier merge, and the losing spellings are retired
  in the same wave. Net surface falls.
- **Adopt a "used or gone" rule for the module tier.** A function that no
  application code calls is retired with a `mylang fix` rewrite, the way the
  reserved words are. This would remove roughly 167 functions, most of them
  from `math`, `strings`, `path` and `sort`.

The first is the design's own direction and is better. The second is
available if the standard library is genuinely meant to be narrow, and it
should be decided *before* wave 2 rather than after.

`parallel` is dead under any policy — a sequential stub with no caller in
application code or tests — and can go immediately. `durable` and
`persistent_memo` have 25 and 9 test calls and no application calls; they
look like two halves of one unfinished feature and should be finished or
dropped. `filesystem` and `environment` have no function calls because they
supply capability types; they stay regardless.

## 10. Finding 9 — the documentation and registry surface

- `docs/` holds 880 files and 163,377 lines; 546 of those files are audits and
  130 are experiments. Only 50 pages are language-facing. A reader looking for
  the language finds it in `docs/current-language.md` and `docs/reference.md`;
  everything else is process history that has outlived its usefulness.
- `src/features.json` lists 57 removed features with a description each. Every
  removal leaves a permanent row here, plus a diagnostic code, plus a
  `docs/legacy/` entry, plus a `mylang fix` repair. The *record* of removal
  has become a large part of the surface.

**Recommendation.** Move `docs/audits/` and `docs/experiments/` out of the
documentation tree (they are process records, not language documentation) or
mark them non-normative in one sweep. Trim `features.json`'s `removed` section
to the entries that still have live code in the wild — the 57 rows are
individually cheap but collectively a parallel description of the language
that has to be kept in sync with the 232 live ones.

## 11. Ranked recommendations

Ordered by surface removed per unit of risk. Every item is a
non-behavioural change to a language that already rejects the old spelling.

| # | Change | Surface removed | Migration cost | Risk |
| ---: | --- | ---: | --- | --- |
| 1 | Unreserve the 14 dead words with no migration message | 14 reserved words | `mylang fix` for code that already fails | very low |
| 2 | Unreserve the 27 dead words that already have a removal message | 27 reserved words | none (they already fail) | very low |
| 3 | Delete the `def` alias | 1 reserved word, 1 lexer alias, 1 parser path | 13 fixtures stay fixtures | very low |
| 4 | Make `union`, `replace`, `unwrap` contextual; `len` a soft builtin | 4 reserved words | none | very low |
| 5 | Fix the `List` migration message to name `T[]` | 1 message | none | very low |
| 6 | Retire `i8`, `i16`, `i32`, `u16` | 4 integer widths | 469 test sites, 2 production | low |
| 7 | Remove `parallel`; decide on `durable`/`persistent_memo` | 1 module, 4 functions | small | low |
| 8 | Decide the module-tier policy *before* wave 2 (consolidate while moving, or adopt "used or gone") | up to 167 functions | large | high |
| 9 | In wave 2, name module functions after the `Kind`, and drop the 56 Python method spellings | 56 spellings | 111 prod + 401 test sites | medium |
| 10 | Retire `@deprecated` and `@test`; fix the `@invariant` message | 2 attributes, 1 message | 2 sites | low |
| 11 | Resolve the `abs` conflict; give the prelude one tier per operation | ~8 duplicated names | per-operation | medium |
| 12 | Make `int`/`float`/`str`/`bytes` keywords, or un-keyword `bool` | consistency | small | medium |
| 13 | Reconcile `selfhost/`, `velocity/` and `experiments/` with the language | 12,658 files, or their deletion | large | high |
| 14 | Move `docs/audits/` and `docs/experiments/` out of the docs tree | 676 files | none | low |

Items 1–4 are a single coherent change: **"stop reserving words that name
nothing, and reserve a word only where it is needed."** They touch
`src/lexer.zig`, `src/removed_names.zig`, `src/parser.zig`,
`src/features.json` and the diagnostics table, and they cannot break a
working program because every affected program already fails to compile.
Together they free 45 of the 94 reserved words, leaving 49: 41 live ones and
the 8 internal spellings the standard library needs.

Items 8 and 9 are two halves of one wave-2 decision: what the module tier
looks like after the method tier goes away. Item 8 says how wide it should
be; item 9 says what its functions are called. Settling them together is
cheaper than settling them one at a time, because retiring the Python method
spellings is a table deletion once the `Kind` names are known.

## 12. The decisions ledger — what is already settled

This audit does not reopen anything in this section. Every row was checked
against the compiler at `719975b8`, not read off a plan. The section exists so
that a reader implementing §11 can tell a *new* proposal from a *settled* one.

### 12.1 The fourteen retired forms

`src/diagnostic_codes.zig` carries fourteen `*_REMOVED` codes. Each one
rejects a form the language used to accept, and each names a replacement:

| Code | Rejects | The replacement it names | Design proposal |
| --- | --- | --- | --- |
| `E_ARENA_REMOVED` | `with arena():` | ordinary statements | wave 1 |
| `E_COMPREHENSION_REMOVED` | comprehensions | a typed accumulator and an explicit loop | 5 |
| `E_CONDITIONAL_EXPRESSION_REMOVED` | `a if p else b` | an `if` statement that assigns | 11 |
| `E_DOMAIN_REMOVED` | scalar domains and `wrap` | a one-field record with an invariant | 13 Oct decision |
| `E_EFFECTS_REMOVED` | source effect clauses | capability parameters | 13 Oct decision |
| `E_EXPORT_REMOVED` | plain `export NAME` | mark the declaration `public` | wave 1 |
| `E_GENERATOR_REMOVED` | generator arguments to `sum` and friends | an explicit loop | 5 |
| `E_LAMBDA_REMOVED` | lambdas | a named top-level function | 10 |
| `E_LIST_MEMBERSHIP_REMOVED` | `x in xs` on a list | `lists.contains(xs, x)` | 15 |
| `E_MATCH_EXPRESSION_REMOVED` | `match` arms with `yield` | a named result or a return | 11 |
| `E_NEGATIVE_INDEX_REMOVED` | `xs[-1]` | an explicit offset from `len(base)` | 12 |
| `E_REPETITION_REMOVED` | `"-" * 3` | `strings.repeat`, `byte_builder` | 14 |
| `E_STEPPED_SLICE_REMOVED` | `xs[a:b:c]` | a contiguous view | wave 3 |
| `E_TUPLE_REMOVED` | tuple types, values and destructuring | a record | 13 |

`src/features.json` records **57** removed features, dated: 2026-09-13 (6),
2026-09-14 (5), 2026-09-21 (1), 2026-09-24 (2), 2026-10-08 (22), 2026-10-14
(18, wave 1), 2026-10-16 (3). `docs/legacy/` holds 17 entries.

The fourteen codes break down as: **nine** that are the 13 October
proposals' own removals (5, 10, 11, 12, 13, 14, 15 and the two halves of 5),
**two** that are the 13 October *decisions* (scalar domains, the effect system),
**two** wave 1 landed on its own (`arena`, plain `export`), and **one** wave 3
landed (stepped slices).

### 12.2 The twenty proposals of 13 October, by status

`docs/design/surface-simplification-2026-10-13.md` section 7.1 lists twenty
proposals. Their status in the tree today:

| # | Proposal | Status | Evidence |
| ---: | --- | --- | --- |
| 1 | No methods on built-in types | **not implemented** | `xs.append(3)` still compiles |
| 2 | Sequencing without methods; pipe dropped | pipe **dropped**; lint pending | a pipe expression is a syntax error; no lint exists |
| 3 | Field punning | **not implemented** | `E_NAMED_FIELDS` still fires — see 12.3 |
| 4 | Empty literals keep their annotation | **withdrawn** | the document says so |
| 5 | Comprehensions removed | **implemented** | `E_COMPREHENSION_REMOVED` |
| 6 | Unqualified case names | **not implemented** | `E_FRONTEND_VARIANT` still fires — see 12.3 |
| 7 | Public signatures name their dictionaries | alias exists, lint pending | `type W = dict[str, int]` compiles; no lint |
| 8 | `match` on scalars and on two values | **not implemented** | `a case names a union, enum or result case, not a literal` |
| 9 | `W_PARAMETER_COUNT`, `W_DATA_CLUMP` | **not implemented** | neither code exists |
| 10 | Lambdas removed | **implemented** | `E_LAMBDA_REMOVED` |
| 11 | No control flow inside an expression | **implemented** | `E_CONDITIONAL_EXPRESSION_REMOVED`, `E_MATCH_EXPRESSION_REMOVED` |
| 12 | Negative indexes removed | **implemented** | `E_NEGATIVE_INDEX_REMOVED` |
| 13 | Tuples removed | **implemented**, no fix | `E_TUPLE_REMOVED` — see 12.4 |
| 14 | Sequence repetition removed | **implemented** | `E_REPETITION_REMOVED` |
| 15 | `in` on a list removed | **implemented** | `E_LIST_MEMBERSHIP_REMOVED` |
| 16 | `str` is bytes underneath | **implemented** | `len("é")` is 2, `len("€")` is 3, `"é"[0]` is 195 |
| 17 | A slice is a view | **not implemented** | `mut v = xs[0:2]; v[0] = 99` leaves `xs[0]` at 1 |
| 18 | One lookup per dictionary operation | **not implemented** | no `W_DOUBLE_LOOKUP` |
| 19 | Counting loops become `range` loops | **not implemented** | no `W_COUNTING_WHILE` |
| 20 | Output is buffered | **not implemented** | not checked here |

Only four lint codes exist in the whole tree: `W_DEPRECATED`, `W_TEST`,
`W_UNUSED_BINDING` and `W_UNUSED_IMPORT`. Proposals 9, 18 and 19 name three
that do not.

Proposal 16 deserves a note: `str` is bytes *today*. `len` counts octets, `s[i]`
yields an `int` byte value, and iterating a `str` is refused with
`E_TEXT_ITERATION`. Proposal 17 is the one that has **not** landed — a list
slice is still a copy.

### 12.3 Two proposals are blocked by existing diagnostics

Proposals 3 and 6 are not "add a syntax" tasks; they *contradict* diagnostics
the compiler already raises, so landing them means relaxing those rules:

```
record Point:
    x: int
    y: int
mut p = Point(x, y)
      ^ error[E_NAMED_FIELDS]: payload fields must be supplied by name

mut s: Shape = circle(2.0)
                   ^ error[E_FRONTEND_VARIANT]: name the enum payload field at its construction
```

Whoever picks them up should know the cost is a diagnostic change, not a
parser change.

### 12.4 Three migration defects found while checking the above

These are not in §11 because they are defects, not simplifications. All three
sit on paths the project already committed to.

1. **`List` points at a refused spelling.** `src/removed_names.zig` says
   `` `List[T]` was removed; use `list[T] ``, but `list[T]` is refused with
   `E_FRONTEND_SYNTAX`. The *fix* is fine — `mylang fix` runs two rounds and
   lands on `int[]` — but the *message* is a dead end.
2. **`codec_encode` points at a retired concept.** The message says "use the
   documented domain codec API", but `domain` was retired in wave 1 and no
   codec module exists. The live replacements are `base64.b64encode` /
   `base64.b64decode` and `hex.encode` / `hex.decode`. No `.fix` is attached,
   so the message is all the user gets.
3. **`E_TUPLE_REMOVED` has no repair.** `mylang fix` reports
   *"tuple migration is deferred until other diagnostics are repaired"* and
   edits nothing. `CLAUDE.md` requires a structured `fix` wherever a removal
   turns previously accepted code into a diagnostic. The deferral is declared
   in the message, so it is a known gap rather than an oversight — but the
   tuple removal is landed without its migration.

### 12.5 What this audit does not reopen

- **User types keep no methods**, and **scalar domains are removed**, and
  **the inferred effect system is deleted** — the three decisions taken on
  13 October (`surface-simplification-2026-10-13.md:13-58`). §11 items 8, 9
  and 11 implement them; they do not question them.
- **The `type` alias stays.** Proposal 7 depends on it, and the design wants
  more aliases, not fewer.
- **`Result[T, E]` and the `result` declaration both stay.** They are
  different things, not duplicate spellings.
- **`@requires`, `@ensures` and `@invariant` stay.** They are enforced at run
  time (`R_REQUIRES`, `R_ENSURES`, `R_INVARIANT`).
- **The removed `E_*_REMOVED` forms stay removed.** Nothing in §11 proposes
   reinstating a comprehension, a lambda, a tuple, a domain, an effect clause,
   an arena, a negative index, a repetition, a generator, a list membership
   test, a stepped slice, a conditional expression, a `match` expression or a
   plain `export`.
- **The eight internal words stay reserved.** `__float_sqrt`, `__float_sin`,
   `__float_cos`, `__stand_in` and `__clock_advance` are spelled with a
   leading `__` and rejected outside the standard library; `clock_now`,
   `random_u64` and `environment_get` are ordinary-looking but report
   `E_INTERNAL_NAME` ("reserved for compiler-internal use"). They are not part
   of the surface a user learns, so §2 counts them apart from the 41 dead
   words rather than recommending their removal.

### 12.6 Could not verify

- **Which wave-1 worker landed which line.** The plan
  (`language-wave1-cleanup-plan-2026-10-15.md:57-261`) names six workers, K1
  to K6, with per-worker ownership. The tree shows the *effects* — 57 removed
  features, fourteen codes — but the plan's own status markers were not
  cross-checked against the commits, so this report does not claim any worker
  is complete.
- **The 12 September audits' recommendation list.** They describe a language
  with a garbage collector, arenas, comprehensions, lambdas and tuples, all
  since retired. They are superseded context, and no recommendation in them
  is re-proposed here or counted as open.
- **Whether `selfhost/` ever compiled as a whole.** 12 of its 48 files check
  cleanly today; no commit was found in which all 48 did.
- **The provenance and date of `experiments/`.** It was measured (12,485
  files, 1,271,192 lines, 4,992 distinct contents) but not dated.
- **Guardian.** No gate step was run, so no Guardian claim is made.

## 13. What this audit did not measure

- **Performance.** No benchmark was run. Removing an integer width or a
  method tier has a real codegen cost that a timing run would price; the
  numbers here are surface counts only.
- **Migration experience.** The `mylang fix` cost of each removal was counted
  in *sites*, not measured in minutes. Item 1 needs fix rules for 18 words
  that have none; that is a real chunk of work even though the affected
  programs do not compile today.
- **Wave 2 interactions.** The design's proposal 1 (no methods on built-in
  types) touches 1,843 method calls in the checked production corpus. Finding 6
  argues the prelude tier should be resolved in the same wave, because
  otherwise wave 2 relocates the method tier rather than removing a tier. That
  interaction should be settled before wave 2 starts. §7.1 adds a second
  decision for the same wave: the 65 method spellings should become module
  functions named after their `Kind`, which retires the Python-shaped
  spellings at the same time. Twelve of the 22 Python-isms have no native
  `Kind` name yet, so those names still have to be chosen.
- **`selfhost/` contents.** 36 of 48 files fail to check, but whether the
  surviving 12 are worth keeping is a product decision, not a measurement.
- **The corpus as a proxy for real programs.** The "application code" in
  Finding 8 is 93 example files (mostly small language demos) and 49 benchmark
  files. It is the only non-test, non-library code in the repository, so
  "never called from application code" means "never called from *this*
  application code". A project with more real programs would give different
  numbers. The finding that survives the weakness is the ratio — the library
  calls itself 1,004 times and its users call it 106 — not the absolute
  count of unused functions.
