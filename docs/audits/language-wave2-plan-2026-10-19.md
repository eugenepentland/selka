# Language wave 2: one home, one spelling, owned parameters (plan, 2026-10-19)

Status: written on 19 October 2026 and revised after reviewing the
[wave 3 fixes](language-wave3-fixes-plan-2026-10-19.md) run, which landed in full
(`experiments/language-wave3-fixes-20261019/REPORT.md`). The user decided L1 to L5
(§9) on 19 October. L6 to L19 are the reviews' recommendations, taken as accepted
when the user launches the run. Codex implements it. Written against `main` at
`bc2736f26d`. The first batch, W, closes what that review found left over (§3.W).

This wave widens the "wave 2" of the
[surface-simplification design](../design/surface-simplification-2026-10-13.md)
(proposals 1, 2, 3, 6, 7, 8, 9, 18, 19 and 20) with what three measurements of 19
October found:
- a census of the 22,345 lines agents wrote in `~/ai/canopy/selka-projects`;
- that repository's friction ledger (85 items);
- the surface audit `docs/audits/language-surface-audit-2026-10-19.md`.

The goal is the one the user set: code that an agent or a person can read and
understand from the line in front of them. That means each operation has one home
and one name, each meaning has one spelling, a line shows what it changes, gives
away or can fail with, and nothing a reader sees varies without meaning something.

## 1. Summary

| Stage | What changes for a program |
| --- | --- |
| **W. Wave 3 leftovers** | Fixes a `mylang fix` repair that changes results, and a list merge that checks but does not build. One slice rule binds whether or not the slice is bound to a name, for lists as for text. The text guide stops calling slices copies |
| **0. Cleanup** | Nothing that compiles today. It drops dead reserved words and the `def` alias, fixes stale messages, gives the tuple removal its fix, retires two unenforced attributes, and stops agents from grepping retired dialects |
| **1. Formatter** | Layout only: double quotes, one argument per line in multi-line calls, sorted imports |
| **2. One home per operation** | Methods on built-in types become functions. Each operation has exactly one home, a module named after its type or a short fixed prelude, under the compiler's own names. Duplicate homes, same-name-different-meaning pairs and second spellings go. Bit operations are functions. A call has one shape. `fails` is the one fallible signature. Output buffers |
| **3. Options and `match`** | A missing value is checked with `is None` and defaulted with `unwrap_or`. `match` is for enums and results; patterns use short case names, field-name bindings and literal arms |
| **4. Owned parameters** | `own` marks a parameter that takes its argument, at the declaration and at the call. A `mut` resource is borrowed, not transferred |
| **5. Size limits** | `release check` blocks very long functions, long parameter lists, deep nesting, nested calls, hand-counted loops, double dictionary lookups, unnamed public dictionaries and discarded failures, each with a waiver |

Every refusal carries its certain `mylang fix` repair and a `FIX-MIGRATION-1`-style
test. Every corpus migration is a generated commit, as in waves 1 and 3.

## 2. What a program looks like after

```text
import dicts
import strings

enum Side:
    left
    right

record Pin:
    name: bytes
    side: Side

func file_pin(own pin: Pin, mut on_left: Pin[], mut on_right: Pin[]):
    match pin.side:
        case left:                                  # short case names
            append(mut on_left, own pin)            # pin is given away on this line
        case right:
            append(mut on_right, own pin)

func label(status: int) -> str:
    match status:                                   # literal arms
        case 200:
            return "ok"
        case 404 | 410:
            return "gone"
        case _:
            return "error"

func port_of(values: dict[str, str]) -> int:
    const text = dicts.find(values, "port")         # one probe, an option back
    if text is None:                                # the one missing-value check
        return 8080
    const port = parse_int(strings.strip(text))     # one home per operation
    return unwrap_or(port, 8080)

func main(out: Stream) -> int:
    const flags: u64 = 300
    print(out, label(200), bit_and(flags, 255))    # print and bit operations are functions
    return 0
```

Every operation has one home: `dicts.find`, `strings.strip`, and the prelude's
`append`, `parse_int`, `unwrap_or`, `print` and `bit_and`. A line shows what it
changes (`mut`) and what it gives away (`own`).

## 3. Design

### 3.W Batch W: what the wave 3 fixes left over

Each item was found by re-running the earlier repros on the install of `main`'s
compiler (`~/.cache/selka-projects/compilers/832d29b785`, no `src/` change since).
Each becomes a named test.

1. **A `mylang fix` repair that changes the result.** The negative-position repair
   inside a scalar helper (`negative_index.helperCall`) rewrites
   `strings.char_find(t, "b", -1)` to `strings.char_find(t, "b", max(len(t) - 1, 0))`.
   `len` is octets but the helper's window is in scalars, so on `t = "λλb"` the
   answer goes from `2` to `-1`.
   - The repair must spell `strings.char_count(t)` inside every scalar helper, as
     C1's `scalar_text_helpers.argumentText` already does (F19's gap).
   - Add a test that runs the fixed program on non-ASCII text and compares the value.
2. **A list merge that checks but does not build.**
   - **Shape:** `const v: int[]`, then `v = xs[0:2]` in one branch and `v = xs[1:3]`
     in the other, with `xs` an immutable list.
   - **Today:** `check` passes, then `build` fails with
     `E_CORE_UNSUPPORTED: the ownership pass cannot place a ownership in main`,
     which names no line.
   - **Expected:** it prints `1` and `1`, as the pre-wave-3 compiler and the text
     form (`R3`) do.
   - Fix the case, and make `E_CORE_UNSUPPORTED` name the source line, with
     corrected wording.
3. **One slice rule, whether or not the slice is bound.**
   - **Today:** `parts.append(t[0:2])` is `E_SLICE_ESCAPES` with the `.copy()` fix,
     but `const v = t[0:2]` followed by `parts.append(v)` is accepted and copies.
     The same holds for lists.
   - **Required:** a bound view that is stored, returned outside the one-parameter
     rule, or invalidated while live gets the same refusal and fix as the inline
     slice, for text, bytes and lists.
   - The materialization added for R1 (a view at a merge into an owned binding)
     stays for merges only.
4. **Lists follow text on invalidation.**
   - **Today:** `mut xs = [1, 2, 3]; const v = xs[0:2]; xs.append(4); print(v)` is
     accepted and silently copies the slice, while the same program over text is
     `E_SLICE_ESCAPES`.
   - **Required:** the rule a reader sees is the text rule, refused with the
     `(…).copy()` fix, whatever the list's representation underneath.
   - Census the corpus first. Migrate with `mylang fix` as a generated commit.
5. **The matrix covers these shapes.** Add generated cells for:
   - bound-view stores;
   - list views of a `mut` source, invalidated and not;
   - list deferred-`const` merges;
   - a negative position inside a scalar helper.

   Review the `OMISSIONS` list of F9 against those cells.
6. **The text guide.** `docs/text.md` still says `text[a:b]` "copies the octets"
   (around lines 15, 21 and 104) and keeps a section titled "Slices are new strings"
   (around line 193). It also mentions the removed `managed_allocation` effect.
   - Rewrite those passages for views, each claim with a `# doc: expect` example.
   - Grep every live guide for "copies its octets", "managed_allocation" and
     "effect" used in the old sense.
7. **The parity baseline.** The wave 3 fixes did not re-run `zig build bench-parity`.
   Run it now through `scripts/build-slot.sh timing …`, and keep the result as G7's
   "before" for this wave.

### 3.0 Stage 0: cleanup with no behaviour change

1. **Unreserve the dead reserved words.**
   - The audit's §2 lists 41. **Eleven of them are live built-in functions** that
     agents call: `bit_and`, `bit_or`, `bit_xor`, `shift_left`, `shift_right`,
     `wrapping_add`, `wrapping_sub`, `wrapping_mul`, `saturating_add`,
     `saturating_sub`, `saturating_mul` (`src/integers.zig:45`; 13 calls in the
     projects). They stay.
   - Unreserve the other 30, with a `mylang fix` rewrite for every one that has no
     removal message today.
   - Make `union`, `replace` and `unwrap` contextual where the audit's §2.1 shows the
     parser already special-cases them.
2. **Delete the `def` alias.** Its only users are the stale trees and 13 deliberate
   fixtures.
3. **Fix the messages that name removed forms:**
   - `List` points at `T[]`;
   - `codec_encode` and `codec_decode` point at `base64` and `hex`;
   - the `@invariant` target message stops naming `domain`.
4. **`E_TUPLE_REMOVED` gets its certain fix:** a named record for a returned tuple,
   and two-name loops stay. That is CLAUDE.md's rule. If a site has no certain fix,
   log it, and give the message the exact manual repair.
5. **Retire `@deprecated` and `@test`,** which nothing enforces. The fix deletes the
   attribute line. There is one site each.
6. **What agents read.**
   - Add a repository `.ignore` (ripgrep and Claude's grep honour it) listing
     `experiments/` and `velocity/`. These hold 1.27 million lines in retired
     dialects, 82% of the guest code in the tree.
   - Put a one-line "historical, not the current language" banner in
     `experiments/README.md` and `velocity/README.md`.
   - Moving the trees out is a separate decision for the user (§8). `selfhost/` stays
     as it is (§7).
7. **Not in this stage:**
   - **Integer widths.** `extern func` passes `i32`, and binary formats use `u16`,
     so a width is not a certain rewrite.
   - **Chained comparisons.** Agents use them, 22 times, and they read well.

### 3.1 Stage 1: the formatter decides what carries no meaning

`mylang fmt` canonicalizes three things:
- **String quotes:** double quotes, unless the text contains a double quote and no
  single one. Agents already write 100% double quotes.
- **Multi-line calls, constructors, collection literals and parameter lists:** one
  item per line, with a trailing comma (§7.2's proposal 6).
- **Imports:** sorted, one per line.

The corpus is reformatted in one generated commit (`migration (generated): fmt`).
`fmt --check` is already in every gate, so the rules stick.

### 3.2 Stage 2: one home per operation

**The rule.** Every operation on a built-in value has exactly one home:
- **The prelude** is a fixed, short list. It needs no import and holds:
  - conversions: `str`, `int`, `float`, `bytes`, `bool`, `ord`, `chr`, `repr`,
    `parse_int`, `parse_float`;
  - operations over any sequence: `len`, `range`, `enumerate`, `zip`, `reversed`,
    `min`, `max`, `sum`, `any`, `all`, `sorted`;
  - the most common writes: `append`, and `sort` (in place);
  - optional values: `unwrap_or`;
  - output: `print`, `write`, `flush`;
  - the bit and integer family: `bit_*`, `shift_*`, `wrapping_*`, `saturating_*`.
  The run may move an entry between the prelude and a module, and logs the reason.
  The list stays under about 40 names.
- **A type's module** holds everything else that is specific to one type: `strings`,
  `bytes` (byte strings), `lists`, `dicts`, `sets`, `math` (every numeric operation,
  including `abs`, `round`, `sqrt` and `floor`), and the byte-buffer module.
- **Names are the compiler's own.** Each function takes its internal `Kind` name from
  `src/buffer_operations.zig` (`starts_with`, `is_digit`, `symmetric_difference`),
  never a Python spelling. Twelve operations have no native name yet (audit §7.1);
  name them and log the names.
- **Imports: one rule everywhere (L18).**
  - **What landed (wave 3 fixes B2, F21):** `E_MODULE_NOT_IMPORTED` with the
    `import` fix, for the scalar helpers only, and only in a module graph. A program
    that is one import-free file keeps using them without an import.
  - **Two problems with that today:**
    - A line's validity depends on an unrelated line: `strings.char_count("aλ")`
      compiles in a file with no imports and fails as soon as `import math` is added.
    - `strings.pad_left` without its import still reports `E_UNKNOWN_TYPE: type is
      not declared`.
  - **This wave makes it one rule.** Every module function needs its module's
    `import` in every file, single-file programs included. A prelude name needs
    none. `E_MODULE_NOT_IMPORTED`, with the `import` fix, covers every module
    function. The single-file exemption goes, and so does whatever
    "single-unit grammar" cannot hold an `import` (F21). F15's fixture populations
    are handled in the test harness, not by exempting files.
  - Keep `interfaces.Index.noteImportUse`, so the fixer does not oscillate.
- **A generated reference.** `mylang docs operations` prints the table, every
  operation once, with its home, generated from the compiler's own table. A test
  fails if an operation has two homes, or if one name means two things.

**What it removes, with the measured cases:**

| Today | After |
| --- | --- |
| 65 method spellings on built-in values (`xs.append(x)`, `s.strip()`, `out.print(a)`, `buf.append_byte(b)`); about 6,700 method calls in the checked corpus | functions: `append(mut xs, x)`, `strings.strip(s)`, `print(out, a)`, and the byte-buffer module's `append_byte(mut buf, b)` |
| `s.startswith(p)` and `strings.starts_with(s, p)`; `s.strip()` and `strings.strip(s)` | `strings.starts_with(s, p)`, `strings.strip(s)` |
| `parse_int("12")`, `"12".parse_int()`, `strings.to_int("12")` | `parse_int("12")` |
| `s.find("b")` is a byte offset with `-1` for absent (`4` on `"λλb"`), but `strings.find(s, "b")` is a scalar position in an option (`Some(2)`), because C1 made the stdlib's `find` wrap `char_find` | one `strings.find`, byte offsets, with one absence convention (L19). The scalar reading is `strings.char_find`. Existing `strings.find` callers migrate to `char_find` first, by a certain fix, so nothing changes meaning silently. Audit every stdlib function that wraps a `char_*` helper (`strings.my`, `http.my`) the same way |
| `ord("a")` is `97` but `strings.ord("a")` is `Ok(97)`; `abs` is a number but `math.abs` a `Result`; `sum` adds a list but `time.sum` two durations | one `ord` (the prelude's), one `abs` (`math.abs`, the prelude's semantics, trapping on overflow like all arithmetic), `time.add` |
| `sort.sort_ints`, `sort.min_int`, `math.fabs`, `math.fmin`, `math.fmax` beside `sorted`, `min` and `math.abs` | the general forms only |
| `byte_builder.Builder` (a record wrapping `byte_buffer`, 463 calls) and `byte_buffer` with methods (14) | one type, `byte_buffer`, and one module for its operations; `byte_builder` becomes a fix rewrite |
| `parallel` (a sequential stub), `durable` and `persistent_memo` (no application caller) | removed, with tests moved or retired and listed |
| `a & b`, `a \| b`, `a ^ b`, `~a`, `a << n`, `a >> n` | `bit_and(a, b)`, `bit_or`, `bit_xor`, `bit_not(a)` (new), `shift_left(a, n)`, `shift_right(a, n)`; the operators and their `op=` forms are refused with the rewrite |
| `-> Result[T, E]` with `return Ok(x)` / `return Err(e)` (9 sites in the projects) | `-> T fails E` with `return x` / `fail e`; `Result[T, E]` stays as a value type |
| `area(2, 3)`, `area(height=3, width=2)`, `area(2, height=3)`; a default passed by position or by name | a parameter is positional or `named` (keyword-only). Only `named` parameters take defaults, so a call shows every value it overrides by name. Agents passed a positional parameter by keyword 0 times in 5,200 calls |
| `d.get(k, d0)`, `if k in d: d[k]` | `dicts.find(d, k) -> V?`, `dicts.add(mut d, k, delta)`, `dicts.append_to(mut d, k, item)` on one probe (proposal 18) |
| `strings.split(strings.lower(strings.strip(text)))` | `strings.words(strings.lower(text))` (proposal 2's vocabulary) |
| `_ = buf.append_byte(x)` (53), `_ = out.write(b)` (21): writes that return values nobody wants | the new functions return nothing, so `_ =` appears only where something real is dropped (§3.5's lint covers dropped failures) |
| `write` flushes on every call; `print` buffers | `write` buffers like `print`; `flush(out)`; `err` unbuffered; a trap flushes `out` first (proposal 20) |

**The `set` type stays** (2 project uses, 31 tests). Its nine operations move to
`sets` like every other type's.

**Two phases**, because the self-hosted components are type-checked by the current
compiler (`test-program-check`) but built by a pinned seed (§7):
1. **Phase 1 (additive):** every new home exists; nothing is refused.
2. **Re-seed:** pin a seed compiler that has the new homes, through the self-hosting
   plan's re-seed procedure. Migrate `selfhost/components` with `mylang fix`, as a
   generated commit.
3. **Phase 2:** refuse the old forms with their fixes. Migrate the corpus, the
   embedded standard library, guide examples, docstring `>>>` examples and
   selka-projects.

### 3.3 Stage 3: options and `match`

1. **One check for a missing value.**
   - `x is None` and `x is not None` narrow. `unwrap_or(x, d)` supplies a default.
   - `x == None`, `x != None`, `.is_none()`, `.is_some()` and `match` on an option
     are refused.
   - The fix rewrites a two-arm `match` over `Some`/`None` to an `is None` test with
     narrowing:

```text
# before
match find_user(id):
    case Some(user):
        greet(out, user)
    case None:
        print(out, "no user")

# after
const user = find_user(id)
if user is None:
    print(out, "no user")
else:
    greet(out, user)
```

   - Where the match is not that shape, for example a nested pattern inside
     `Some(...)`, the fix binds first and nests the second `match`. A site with no
     certain rewrite is logged and migrated by hand.
2. **Short case names in patterns.** `case circle(radius=r)` replaces
   `case Shape.circle(radius=r)`. The scrutinee's type is known, so a qualified
   pattern is refused with the fix. A bare name in a pattern always names a case
   of the scrutinee's type, never a local or a new binding; `case _` is the only
   catch-all. An unknown case name is an error that lists the type's cases. **Construction stays qualified**
   (`Shape.circle(radius=1.0)`): the reader sees the type where the value is made,
   and there is one spelling, independent of inference.
3. **Field names as bindings in patterns.** `case circle(radius)` binds `radius`.
   `radius=r` stays the way to rename. Construction does not gain punning:
   `Point(x, y)` would look positional to a reader.
4. **Literal arms.**
   - `match` on an `int`, `bytes`, `str` or `bool` with literal or named-constant
     arms, `|` alternatives, and a required `case _`.
   - The `if`/`elif` chains over one value that agents wrote for status codes
     (FR-218) become a candidate fix only where certain: one scrutinee, literal
     comparisons, no side effects. Otherwise a lint suggests it.
5. **Not in this stage:** matching several values at once (`match a, b:`).

### 3.4 Stage 4: owned parameters

1. **Spelling (L1).** `own` before a parameter, and `own` before the argument at
   every call. Each parameter has one of three modes, visible at both ends:
   - **plain:** reads;
   - **`mut`:** changes the caller's value;
   - **`own`:** takes the value; the caller's binding is moved and unusable after the
     line.

```text
public func order_by_key(own keys: float[]) -> int[]:
    mut s = State(keys=keys, perm=perm)          # stored without a copy

const order = order_by_key(own samples)         # samples is gone after this line
const order = order_by_key(samples.copy())      # keep samples: the copy is visible here
```

2. **Rules.**
   - **At the call, `own` means exactly one thing: a named binding is given away on
     this line and is unusable afterwards.** It is required when the argument names
     a binding, or a place of a managed type: `own samples`, `own node`. It is
     refused, with a fix that removes it, on a fresh value (a call result, a
     constructor, a literal, `x.copy()`) or a scalar, where nothing is lost. So
     `append(mut xs, 1)` and `push(Node(...))` carry no marker, and
     `append(mut left, own pin)` does.
   - An `own` parameter may be stored, returned or moved by the callee, and is
     destroyed at the callee's scope end otherwise.
   - `own` and `mut` do not combine.
   - Function types spell the mode, `func(own Node) -> int`.
   - Generics accept `own T`. The standard library's storing functions take their
     element `own`: `append`, `dicts.add`, `dicts.append_to`, the `sets` insertions.
   - Stores and constructors (`xs[i] = s`, `R(field=s)`) keep their implicit move.
     The marker belongs to calls, as `mut` does.
3. **Resources (L16).** With transfer spelled `own`, a `mut` resource parameter is an
   exclusive **borrow**, as for every other type. That fixes FR-203: an accept loop
   can pass its listener `mut`.
   - Existing code that relied on `mut` transferring a resource fails to compile at
     the later use.
   - The certain fix changes that parameter to `own` and its call sites to
     `own arg`, when the callee stores or consumes the resource.
4. **Reserving `own`** breaks no identifier in the checked corpus or the projects (it
   appears only in comments). Give it a rename fix for any site the census finds.
5. **Migration of today's copies.**
   - Nothing changes meaning, so there is no forced migration.
   - A lint, `copy-for-store` (`L_COPY_FOR_STORE`, report only), points at a
     parameter that is `.copy()`-ed into storage and suggests `own`. That is FR-003's
     forms 2 and 3: `State(keys=keys.copy(), ...)`, `push_node(mut st, node)`,
     `hub.conns[id] = state`.
   - Apply `own` by hand in the stdlib and the projects where the lint fires and
     every caller can give the value up. Log each site.
6. **Not in this stage:**
   - `for own x in xs` (consuming iteration, FR-003's form 1);
   - field-level moves and borrows (FR-107, FR-350);
   - borrowed returns of a parameter's parts (`return Some(text.copy())` accessors).

   Each of these is a follow-on (§8).

### 3.5 Stage 5: size limits in `release check`

New lint rules. Each is waivable with a reason and reports in a plain `mylang lint`
under `strict` and `safety`. `release check` blocks on them under every profile,
beside the docs rules. A file marked generated (a first-line `# generated by …`
comment, or `release.exclude`) is exempt.

| Rule | Code | Default limit, to be calibrated on the corpus and logged | Fix |
| --- | --- | --- | --- |
| function length | `L_FUNCTION_LENGTH` | 60 body lines (median today 7, p90 34, 23 functions over 50) | none |
| parameter count | `L_PARAMETER_COUNT` | more than 5 non-capability parameters (17 functions today) | none (`W_DATA_CLUMP`'s fix where it applies) |
| data clump | `L_DATA_CLUMP` | proposal 9's rule | introduce a record, as proposal 9 describes |
| nesting depth | `L_NESTING_DEPTH` | 4 levels of blocks | none |
| nested calls | `L_CALL_NESTING` | more than 2 calls in one expression (proposal 2) | none |
| counting `while` | `L_COUNTING_WHILE` | proposal 19's exact shape (27 range-shaped loops in the projects) | `for i in range(...)` |
| double lookup | `L_DOUBLE_LOOKUP` | proposal 18's shapes | `dicts.find`, `dicts.add`, `dicts.append_to` |
| unnamed public dictionary | `L_PUBLIC_DICT` | a bare `dict[...]` in a public signature (proposal 7) | a `type` alias |
| discarded failure | `L_DISCARDED_FAILURE` | `_ = f()` where `f` fails, e.g. 26 `_ = fs.mkdir(...)` in the projects | none; handle it, or waive it with a reason |

`L_` lint codes, not `W_` warnings, because they live in the lint registry with its
waivers and profiles.

## 4. Order and batches

| Batch | Contents | Lands when |
| --- | --- | --- |
| W | §3.W (wave 3 leftovers) and the parity baseline | every §3.W repro is a named test with the required result; complete verification passes |
| 0 | §3.0 | complete verification passes |
| 1 | §3.1 and its generated `fmt` commit | complete verification passes |
| 2a | §3.2 phase 1 (new homes, `mylang docs operations`, `bit_not`, `dicts`, `strings.words`, buffered `write`) | complete verification passes |
| 2s | the re-seed script and re-seed, run inside 2b after the families the components do not use (§7, amendment of 20 October) | the components build with the new seed, and complete verification passes |
| 2b | §3.2 phase 2 (refusals, fixes, generated migrations) | an audit query finds zero old forms outside fixtures and `experiments/`; complete verification passes |
| 3 | §3.3 | the same |
| 4 | §3.4 | the same |
| 5 | §3.5 | the same |
| P | selka-projects: a `wave2` branch carrying every migration, `check.sh` green, `COMPILER` bumped, merged into its `main`, the checkout left on `main` | every project is green on the new pin |
| R | §4c: the performance re-baseline, comparing the projects' old pin with batch P's pin | §4c's E1 to E5 hold, and the tables are recorded |

Batches 2b to 4 each regenerate the corpus migration after merging `main`. Lanes in
their own worktrees are allowed where files do not overlap, as wave 3's were. List
them in `status.md`.

### 4a. Amendment, 20 October (evening): what remains, in order

A review of the run on 20 October found three things.
- **2b is not complete.** Round 12's audit checked the named items (the `Result`
  form, option comparisons, bit operators, `copy`, duplicate homes) and called 2b
  done. But §3.2's central change is still open: the method spellings on lists,
  dictionaries, sets, streams and byte buffers.
  - The function homes exist: `append(mut xs, x)`, `sort(mut xs)`,
    `print(out, …)`, `write(out, …)`, `flush(out)`, the `lists`, `dicts` and
    `buffers` words. But `xs.append(1)`, `xs.pop()`, `out.print(…)` and
    `d.keys()` all still check clean.
  - About 3,300 such calls remain in tracked source outside `experiments/`:
    `append` 1,346, `print` 793, then `get`, `append_byte`, `clear`, `pop` and
    others. That is a rough grep count.
  - `selfhost/components` uses 86 of them. The current seed (`27a72bfa96`)
    already has those homes, so these families need no further re-seed. A new
    compiler-side home the components need would still need one.
- **F57's ordering repair cannot be certain.** Options have no ordering:
  `p < two` is `E_TYPE: operation requires an integer type`, and `p < Some(2)` is
  `E_OPTION_INFERENCE`. Only `==` against `Some(N)` checks.
- **F54 kept the byte buffer's methods.** That reverses §3.2's "one module for its
  operations" for the buffer's own writes (`append_byte` and the others). F54's
  evidence covers only the read-only `bytes` words refusing a buffer. Reconsider it
  in this order's step 4 and log the outcome.

The remaining order, chosen so the two runs waiting on this one unblock early (the
performance-feedback run's B6 needs the list homes; its B7 and B8 need stage 4):

1. **F57,** with this repair table:

   | Call shape | Repair |
   | --- | --- |
   | `== -1`, `< 0`, `<= -1` | `is None` |
   | `!= -1`, `>= 0`, `> -1` | `is not None` |
   | `== N` | `== Some(N)` |
   | any other comparison, or a bare use as an `int` | the refusal names the convention, with no edit; logged as a hand migration |

2. **The list family.**
   - Refuse `append`, `pop`, `extend`, `insert`, `remove`, `index`, `clear`, `sort`
     and `reverse` onto their homes, with generated migrations of the corpus and
     of `selfhost/components`.
   - Build the compiler-side homes for `lists.index_of` and `lists.remove`, and
     the native `insert` and `pop_at` kinds that the performance-feedback run's
     B6 waits for.
3. **Stage 4** (`own` parameters and `L_COPY_FOR_STORE`).
4. **The remaining families:**
   - streams (`print`, `write`, `flush`);
   - dictionaries (`get`, `keys`, `values`, `items`, `setdefault`, `update`, `pop`);
   - sets (after F27's naming question);
   - the byte buffer's writes (see F54 above);
   - the view words, through their compiler-side homes.
5. **Stage 3's pattern forms:** short case names, field-name bindings and literal
   arms.
6. **Batch P.**
   - The only changes in `~/ai/canopy/selka-projects` on 20 October were
     `friction/2026-10-20.jsonl` lines appended by `mylang lint` probe runs at
     19:59, plus an untracked `__pycache__`. They are generated telemetry, not
     another run's work.
   - Batch P discards them with `git checkout -- '*/friction/2026-10-20.jsonl'`
     before cutting its branch. If other changes appear, that is still a hard stop.

The checked-docs follow-up runs its F1 and F2 beside this run (its §5 amendment).
Its F3 starts after step 6.

### 4b. Amendment, 21 October: nothing taken or copied without being written

A review of rounds 23 to 27 found §4a's steps 1 to 3 on `main` and sound. The
complete verification passed on `1c2b27207d`, and every escape probe of `own` and of
the `mut` resource borrow was refused. It found six issues, recorded in `status.md`
round 28. After reading them, the user decided two rules for the rest of the wave:
- nothing is taken without being written;
- nothing is copied without being written.

**From here Claude runs the wave.** Haiku agents implement lanes in their own
worktrees, branched from `wave2/integration`. Claude reviews each lane's diff, merges
it into `wave2/integration`, runs the complete verification and lands it on `main`.
§10's rules are unchanged, except that the lanes report to Claude instead of
stopping.

#### Rule T: no hidden transfers

A plain parameter reads, for every type. Today a plain parameter of a resource or
other move-only type takes its argument silently: `func keep(l: network.Listener)`
called as `keep(live)` consumes `live` with no marker. After T:
- such a parameter is refused at its declaration with the certain fix `own`, which
  is its meaning today;
- the call sites then take `own arg` through `E_OWN_ARGUMENT`'s existing fix, so
  `mylang fix` converges in two rounds;
- the consuming standard library functions (`network.close`, `read`, `write`, the
  `Poller` wrappers, the file and process resources) migrate by the same fix, with a
  `FIX-MIGRATION-1`-style corpus.

T also carries the review's two smaller `own` items:
- **A callee may write a parameter it owns.** Today `append(mut keys, x)` on
  `own keys` is refused, with advice to declare `mut keys`, which would change the
  function's contract.
- **A function type prints its `own` positions.** `nominal_catalog.appendCallbackName`
  drops them, so a mismatch reads "expected func(list[str]) -> int, found
  func(list[str]) -> int".

The docs keep the `append` marker accurate until step 3 below requires it.

#### Rule C: no hidden copies

A copy is **written** when the source spells `copy(value)`. Any other run-time
duplication of storage that already exists is a **hidden copy**. Making a new value
is not a copy: `+`, an f-string, `upper`, `sorted`, a literal, a constructor.

Each hidden copy is either made free (a view, a borrow or a move) or refused with a
certain fix that writes the `copy(...)`. The measurements below are on `main`
`1c2b27207d`, at release, with the counters. The probes are in
`experiments/language-wave2-20261019/hidden-copies/`.

| # | Shape | Today | Treatment |
| --- | --- | --- | --- |
| C1 | `mut x = text[a:b]`, the same for bytes and list slices, `mut x = piece` for a view binding, and assigning a view to an owned `mut` local | one copy each time it runs, with no diagnostic | refused; the fix writes `copy(...)` |
| C2 | `return source[a:b]` for `bytes` | a copy per call (`str` returns a free view; a list slice return is already refused) | refused like the list slice; the fix writes `copy(...)` |
| C3 | a `str` function where some returns are views (the parameter, a slice of it or a view binding) and the others are not: a new value, a literal, a second managed parameter, `Some(view)`, a `fails` success | every view return is copied | each view return refused; the fix writes `copy(...)` |
| C4 | a view-returning function used as a function value | `clearValueUsedViewReturns` drops the view result everywhere, so even its direct calls copy, and the value copies on every call | direct calls keep the view; the value use is refused, with a fix that writes a copying wrapper when its name is free |
| C5 | a view-returning `str` function called from another module, which covers every library function | a copy per call; the same function in the caller's file is free | made free: the view result crosses the module boundary |
| C6 | a view or a borrowed value passed to a storing library function (`sets.add(mut seen, piece)`) | the library body copies it | the storing functions take `own` (step 3), so the argument is refused with the `copy(...)` fix that `own` already gives |
| C7 | a library function that returns a contiguous part of its `str` argument (`strings.strip`, `lstrip`, `rstrip` and their kin) | allocates a new string | it returns a slice, so after C5 the call is a free view |
| C8 | the result of a view-returning call stored directly into owned storage (a field, an append, a dictionary, an owned local) or returned from a function that is not a view return | a copy per execution, with no diagnostic (found during the run) | refused; the fix writes `copy(...)` |

**C0, the guarantee.** After C1 to C7, the Core marks each copy instruction that
comes from `copy(value)`, together with the child copies a recursive copy makes.
`verify_ir` then refuses any unmarked copy in the final module whenever facts are
verified, which includes the gate's `--release --verify-facts` pass over every
guest test. `cost --sites` reports `written` on each copy row. Any other place that
emits a copy is listed in `DECISIONS.md`, and is either shown to be unreachable or
removed.

**Out of this amendment.** Library functions return copies of what a caller passes
or stores in four places:
- `dicts.find`, 21 allocations per lookup;
- `pool.get`, 10;
- `lists.last`;
- `dicts.setdefault`.

They need borrowed returns. That is the
[borrowed results plan](borrowed-returns-plan-2026-10-20.md), whose R1 to R4 were
unblocked by stage 4 and whose R3 makes C3's refusals free again later. C0's census
lists their sites so that plan starts from a list.

#### Order

1. **Three lanes in parallel:**
   - **T** (rule T and its two `own` items);
   - **C-a** (C1, C2 and C3: refusals, fixes and the corpus migrations);
   - **C-b** (C5, C4 and C7).
2. **Batch 2s**, the re-seed, then **C-c** (C0's marking, verifier and `cost` field).
3. `append`, `dicts.add`, `dicts.append_to` and the `sets` insertions take their
   element `own` (F71). C6 follows from it.
4. §4a's step 4 families, then step 5's pattern forms, batch P, batch R (§4c) and
   `REPORT.md`. `REPORT.md` also covers T, C0 to C9, the census and batch R's tables.

### 4c. Amendment, 21 October (night): batch R, the performance re-baseline

The user asked for this batch on 21 October, after C9 and batch P and before
`REPORT.md`.

**Why.** The last full measurements predate this wave's code-generation changes:
- the parity suite's reference batches in `bench/parity/thresholds.json`, from
  22 September and 17 October;
- the Lox and EDA comparisons in `~/ai/canopy/eda-bench`, from 9 to 12 October;
- the HTTP benchmark in `selka-projects/http-bench/RESULTS.md`, from 18 October.

Since then, wave 2 has changed:
- which copies a program makes (rules T and C, `own`);
- the calling convention of every plain `str`, `bytes` and list parameter (C9);
- the runtime text helpers, which now take spans.

The method families moved onto their homes with identical LLVM (G7), but no project
has run on them yet.

The performance-feedback run's B2 showed that the counters can miss a 4.4×
instruction regression inside a runtime helper. So this batch measures instructions,
not only allocations.

**What is compared.** Each side uses its own commit's sources, because wave 2 changed
the spellings.
- **Old:** the selka-projects pin `832d29b785`, the compiler every project runs today.
  Its built prefix is `~/.cache/selka-projects/compilers/832d29b785`. That is a
  pre-rewrite id; resolve it through `docs/history/commit-map-2026-10-21.txt`.
- **New:** batch P's pin (the final `main`), built ReleaseFast.

Both run inside the same `scripts/build-slot.sh timing` windows, with the same CPU
pinning. The reference arms (Zig, Rust, Go, C) are built once and shared by both
sides.

**Suites**, each measured old against new, and against the reference arms where the
suite has them:
1. **`bench/parity`**, suite and micro.
   - Run `bench_parity.py run` against `thresholds.json`.
   - Then add a wave 2 reference batch (`bench_parity.py rebaseline` from the new
     result JSONs), so later runs compare with wave 2's final state.
2. **`eda-bench`: Lox (tree and VM) and the EDA port.**
   - Release runtime and peak memory.
   - The development-build rows: empty cache, clean, unchanged, local edit and
     test-only edit.
   - The mylang ports migrate with `mylang fix` on an `eda-bench` branch, as batch P
     does for selka-projects.
   - **Amended 21 October (lane R).** Both ports date from early October, so the old
     pin cannot build them, and the old pin's `fix` corrupts the EDA port. For these
     two suites batch R therefore compares the **ratio to the reference arms** (Zig,
     Rust, Go): the new pin, measured now, against the ratios in the October reports.
     Lane R2 ports both to the current language. It keeps the algorithms and counts
     every repair by class, which is evidence of what migrating October code costs.
3. **selka-projects.**
   - `http-bench`: C=1, and the event loop at C=8 to 1,000.
   - `markdown`: the 652 spec examples and the 260 KB scaling input.
   - `kicad-convert` over its corpus.
   - Each project's `release check` time.
4. **This wave's probes:** `hidden-copies/count.sh` and `bench-c9/perf.sh`, as
   allocation and instruction rows.
5. **The compiler**, on the largest project (the EDA port) and on selka-projects:
   - per-edit check, warm debug build, cold debug build and release build;
   - the complete verification on an unchanged tree and after a compiler edit, three
     samples each.

**Metrics:**
- `perf stat -e instructions:u` on a pinned CPU, with argv input so nothing folds
  (the primary runtime metric);
- the wall-time median under timing admission;
- allocations and copies from `--counters`;
- peak RSS.

**Exit criteria:**

| # | Criterion |
| --- | --- |
| E1 | `bench/parity` passes `thresholds.json` |
| E2 | No runtime row's instructions rise by more than 5% from old to new without a cause named in `DECISIONS.md`. A rise above 10% is a regression: fix it before `REPORT.md` (a lane with a test, then a re-measurement) or put it to the user |
| E3 | Allocations and copies never rise. Rule C points one way, so a rise is a defect |
| E4 | Check and debug-build latency stay within 10% of old, or the cause is named |
| E5 | The tables are in `experiments/language-wave2-20261019/perf-rebaseline/README.md` and the data in the evidence archive. `REPORT.md` quotes the summary table |

**Who runs it.** A lane prepares it:
- migrate `eda-bench`'s mylang ports;
- write one driver script per suite;
- check that both compilers build every program.

Claude then runs the timing windows, which must be exclusive. The batch changes no
compiler code. A regression found here gets its own lane and is measured again.

## 5. Gates and done criteria

| # | Criterion |
| --- | --- |
| GW | §3.W: the negative-position repair keeps the value on non-ASCII text; the list merge builds and prints `1`; bound and inline slices get one rule for text, bytes and lists; list invalidation is refused like text; the matrix holds those cells; `docs/text.md` describes views |
| G1 | Every new refusal has its certain fix and a `FIX-MIGRATION-1`-style test proving `mylang fix` takes a pre-change file to a clean check |
| G2 | The corpus migrates through generated commits only. Hand edits are listed (the stdlib bodies, sites logged as uncertain, tests whose subject is a removed form) |
| G3 | Behaviour is preserved: every existing test passes under its old name after each batch, and the view-shape matrix of the wave 3 fixes stays green |
| G4 | After 2b and 3, the audit queries find zero methods on built-in values, zero duplicate homes, zero bit operators, zero option `==`/`.is_none()`/`match`, zero `-> Result[` signatures, zero keyword-passed positional parameters and zero qualified patterns |
| G5 | `mylang docs operations` lists every operation exactly once, and its test fails on a second home or a reused name |
| G6 | `own`: tests for a named argument moved, the marker refused on fresh values and scalars, `own` with generics and function types, `append` of a named managed value requiring `own`, resources borrowed through `mut` and transferred through `own`, the FR-203 accept loop, and `L_COPY_FOR_STORE` |
| G7 | The parity and runtime suites stay within their thresholds. Method-to-function lowering must not change the emitted code |
| G8 | Edit-loop latency (check plus two tests after a helper edit, warm) is within 5% of its median before the run |
| G9 | `CLAUDE.md`'s "Where the language differs from Python", `docs/python-syntax.md`, `docs/text.md`, `docs/standard-library.md` and every live guide describe only the surviving forms. `doctest .` and `doc-coverage .` pass |
| G10 | selka-projects: kicad-convert's oracle comparisons, markdown's 652 spec examples and `http-server`'s guest and concurrency tests pass on the new pin; `release check` passes where the checked-docs pilots ran |
| G11 | The complete verification and formatting pass for each batch |

## 6. Risks

- **Size.** Batch 2b touches most of the corpus: about 6,700 method calls in checked
  code. The fixes are mechanical, but the migration must be generated and
  regenerated, never hand-merged (wave 1's rule).
- **The prelude list will be argued.** The rule (conversions, any-sequence
  operations, the two most common writes, output, the integer family) decides
  cases. A change goes in `DECISIONS.md` with the counts.
- **Imports for every moved operation** are F15's problem at full scale. Solve it
  once in 2a, for every module function, before 2b refuses anything.
- **`own` and `mut` resources** change one existing rule (MUT-PARAM-2). The fix is
  certain where the callee consumes the resource. Everywhere else the new borrow is
  what the code wanted (FR-203).
- **Option rewrites** can be less certain than they look, for nested patterns. Log
  every hand migration.
- **Wave interactions.** The wave 3 fixes' C1 and C2 add `strings.char_find` and
  friends; this wave gives them their one home. The checked-docs run's docstring
  examples are migrated with everything else.

## 7. How it fits with the other work

- **The wave 3 fixes run has landed** (`bc2736f26d`). What it left is batch W (§3.W)
  and the import rule (§3.2, L18). selka-projects' `main` now holds the wave 3
  migrations (`58f4b33`), and its `COMPILER` pins `832d29b785`.
- **The checked-docs run.** Its batch P migration of selka-projects waits until that
  run's D5 pilots have finished, so the two never rewrite the same branch. Read its
  `status.md` to know.
- **Self-hosting.** `selfhost/components` is type-checked by the current compiler and
  built by the pinned seed.
  - Batch 2s re-seeds through the self-hosting plan's procedure (its lane C), then
    migrates the components by `mylang fix`. These are the only `selfhost/` edits
    this run may make: `selfhost/component-seed.json` and the generated component
    migration.
  - **If the self-hosting run is active on those files, stop and ask** (hard stop 5).
  - Its lane P (Core performance) and this run do not share files, except for
    `own`'s Core changes. Run batch 4 when lane P is not editing `src/core/own.zig`.
- **Amendment, 20 October: batch 2s writes the re-seed script.** The first session
  found that S7 is specified but not written (`DECISIONS.md` F39). The self-hosting
  run has not started, so the user authorizes this run to write it. That is a
  delivery of the self-hosting plan's lane C, and lane C adopts the script rather
  than writing its own.
  - **What it does.** A script under `selfhost/tools/` follows S7:
    1. Tag the candidate commit locally.
    2. Build the seed from it. The builder already provisions a seed from the pin's
       commit and archive digest (`zig-out/tools/selka-components --seed-only`).
    3. Record the seed's receipt.
    4. Build every component with the old seed and with the new one.
    5. Run the component tests and `selfhost/tests/run_test_index_component.py`
       with each, and require identical outputs.
    6. Only then rewrite `selfhost/component-seed.json`.
  - **What it may touch.** Besides that pin, 2s may add the script, a test of it, a
    "Re-seeding" section in `docs/tooling/selfhost-components.md`, and the generated
    component migration. If the builder needs a way to read a candidate pin, it may
    also get a pin-path option in `selfhost/components.zig`, with a test.
    `docs/bootstrap-v1.md` and everything else under `selfhost/` and
    `bench/selfhost/` stay untouched.
  - **Order within 2b.**
    1. First the families `selfhost/components` do not use. On 20 October the 10
       component files held no `Result[`, no bit operator and no option comparison.
    2. Then the re-seed, to a commit on `main` that already has phase 1's homes.
    3. Then the method families and `.copy()`. Each family's component migration
       is generated in the batch that adds its refusal, so the components
       type-check with the current compiler and build with the new seed at every
       commit.
- **Wave 3's position rule** (byte offsets, after the fixes run's C2) is unaffected.

## 8. Follow-ons, not in this plan

- `for own x in xs`, a consuming loop (FR-003's form 1).
- Field-level moves and borrows (FR-107, FR-350).
- Borrowed returns of a parameter's parts, which remove accessor copies.
- `match` on several values (`match a, b:`).
- Folding `result` declarations into `Result[T, E]` once a resource can travel in a
  generic `Result`.
- Moving `experiments/` and `velocity/` out of the repository, and deciding
  `selfhost/`'s stale files (audit §3). Those are the user's decisions.
- Integer widths, if C interop ever stops needing `i32`.

## 9. Decisions

Decided by the user on 19 October:
1. **L1. Owned parameters are spelled `own`**, at the declaration and at the call. At a call the marker appears exactly when a named binding is given away (§3.4).
2. **L2. Standard library policy 1:** every operation has exactly one home, named
   with the compiler's own names. Duplicates go, and domain modules stay.
3. **L3. Bit operations are functions** (`bit_and`, …, `bit_not`). The operators are
   refused.
4. **L4. Options do not use `match`:** `is None` narrows, and `unwrap_or` defaults.
5. **L5. `match` patterns** use short case names, field-name bindings and literal
   arms.

Recommended, and taken as accepted when the run is launched:
6. **L6. One call shape:** positional or `named` parameters, with defaults only on
   `named`.
7. **L7. `fails` is the one fallible signature.** `Result[T, E]` stays as a value type.
8. **L8. One missing-value check:** `is None`. `== None` and `.is_none()` go.
9. **L9. One byte-building type,** `byte_buffer`, with one module.
10. **L10. The new writing functions return nothing,** and dropped failures get a
    lint.
11. **L11. Formatter rules:** quotes, one item per line, sorted imports.
12. **L12. The size limits** of §3.5 block in `release check`.
13. **L13. Stage 0's cleanup,** keeping the eleven live integer builtins reserved.
14. **L14. Construction stays qualified,** and construction gains no punning.
15. **L15. Integer widths stay.**
16. **L16. A `mut` resource is borrowed; transfer is spelled `own`.**
17. **L17. `write` buffers like `print`,** with `flush` (proposal 20).
18. **L18. One import rule:** every module function needs its `import` in every file.
    The single-file exemption of the wave 3 fixes (F21) goes.
19. **L19. One `strings.find`,** answering byte offsets with one absence convention.
    Prefer `int?` (checked with `is None`) if the method-to-function fix can rewrite
    `== -1`, `!= -1`, `< 0` and `>= 0` certainly; otherwise keep `-1` and log it.
    The scalar reading is `strings.char_find`.

## 10. Operating rules and launch instruction for Codex

The default is **decide, log, continue**. Write every decision to
`experiments/language-wave2-20261019/DECISIONS.md`: the question, the options, the
evidence, the choice, and whether it can be reversed. Commit at every step, with a
progress section in `experiments/language-wave2-20261019/status.md`. Investigate and
fix a gate failure within the run, for up to about 6 to 8 h. Early measurements are
checkpoints; only the final ones bind.

**Hard stops.** Stop and ask only for:

1. **A language change beyond L1 to L19 and §3.** For example:
   - a different meaning for an operation;
   - a refusal with no certain fix that is not logged as a hand migration;
   - a prelude of more than about 40 names.
2. **Relaxing a gate on `main`, or any of G1 to G11.**
3. **A broken premise.** For example, the re-seed cannot produce a seed with the new
   homes, or `own` cannot be checked without lifetime annotations.
4. **A failure that cannot be fixed within the bound.**
5. **Anything outside this plan's branches.** The exceptions are §7's `selfhost`
   edits, made only while the self-hosting run is inactive on those files, and
   batch P's selka-projects `wave2` branch, `COMPILER` and `main`. Never touch:
   - pushes and `origin`;
   - `claude/*`, `docs-gate/*`, `wave3-fixes/*`, `projects/*` and `selfhost/*`
     branches;
   - selka-projects' `release-docs`;
   - another run's worktree;
   - `../guardian-zig`.
6. **Resources:** free space on `/` under 25 GB, or the machine swapping.

**Files.**
- `CLAUDE.md` may be edited only in its "Where the language differs from Python"
  section.
- `SPEC.md` is frozen.
- `selfhost/` and `bench/selfhost/` are limited to §7.
- Do not touch `src/syntax_dump.zig` or `docs/bootstrap-v1.md`. §7's amendment of
  20 October lists the only `selfhost/` files batch 2s may touch.
- **Sessions.** When a session's context runs low, it commits a "Session handoff"
  section in `status.md` and stops. The next session starts from that handoff.
  Running out of context is not a reason to mark the run blocked.

**Branches and landing.**
- Integration happens on `wave2/integration` in the worktree
  `~/ai/canopy/mylang-wave2`, branched from `main`.
- Land each batch of §4 by fast-forward from the primary checkout,
  `git -C ~/ai/canopy/mylang merge --ff-only wave2/integration`, after
  `python3 scripts/verify_cache.py --zig "$ZIG" --profile complete` passes. Do this
  only when `git -C ~/ai/canopy/mylang status --porcelain` lists no tracked change.
  Untracked files there belong to other sessions; leave them alone.
- If `main` has moved, merge it, verify again, then fast-forward.
- Corpus migrations are generated commits (`migration (generated): …`), regenerated
  after every merge of `main`.

**Machine rules from `CLAUDE.md`.**
- **Environment:** run `source ~/.config/mylang/dev-env.sh` in every compiler tree.
- **Admission:** builds and focused tests go through `scripts/build-slot.sh build …`,
  and timing through `scripts/build-slot.sh timing …`. `verify_cache.py` owns its own
  admission. At most four agents build the compiler on this machine.
- **The lane check:** `python3 scripts/patch_gate.py --parallel`.
- **Paths:** caches, `TMPDIR` and install prefixes go under `~/.cache/`, never `/tmp`.
- **Tests:** a behavioural change under `src/` ships with a test change in the same
  diff. Guest behaviour goes in `tests/lang/*.my`. Every breaking change carries its
  `mylang fix` migration and a `FIX-MIGRATION-1`-style test.
- **Evidence:** keep committed evidence under 10 MB.
- **Processes:** never kill a process this run did not start.

**Finish** with `experiments/language-wave2-20261019/REPORT.md`. It covers:
- GW and G1 to G11 with their evidence;
- the final prelude list and the operations table;
- every new code, rule and fix, with its migration counts;
- the re-seed;
- the selka-projects pin, merge commit and `check.sh` results;
- the hand-migrated sites;
- the decisions logged.

```text
You are implementing docs/audits/language-wave2-plan-2026-10-19.md on main in
~/ai/canopy/mylang: language wave 2, which closes what the wave 3 fixes left over,
then gives every operation one home, every meaning one spelling, adds owned
parameters, simplifies match and adds size limits. Read the plan fully, then
CLAUDE.md, experiments/language-wave3-fixes-20261019/REPORT.md and DECISIONS.md
(F9, F15, F18 to F21), docs/design/surface-simplification-2026-10-13.md (section
7.1), docs/audits/language-wave1-10-agent-plan-2026-10-14.md (the migration
pattern) and the surface audit, which is an untracked file in the primary
checkout: read ~/ai/canopy/mylang/docs/audits/language-surface-audit-2026-10-19.md
there, and never move, edit or commit it. Decide, log in
experiments/language-wave2-20261019/DECISIONS.md, and continue; stop only for the
hard stops in section 10. Create the worktree ~/ai/canopy/mylang-wave2 on branch
wave2/integration from main. Run the batches of section 4 in order: W (the wave 3
leftovers of section 3.W and the bench-parity baseline), 0, 1, 2a, 2s (re-seed and
the generated selfhost/components migration, only while the self-hosting run is
inactive on those files), 2b, 3, 4, 5, then P (selka-projects on a wave2 branch,
after the checked-docs run's D5 pilots have finished). Every refusal carries its
certain mylang fix repair and a FIX-MIGRATION-1-style test; no repair may change a
program's result; corpus migrations are generated commits. Land each batch on main
after a green complete verification, fast-forwarding only from the primary
checkout as section 10 says; leave untracked files there alone. Never push. Edit
CLAUDE.md only in "Where the language differs from Python"; do not touch SPEC.md,
../guardian-zig, any docs-gate/*, wave3-fixes/* or claude/* branch, or
selka-projects' release-docs. Commit at every step with a progress section in
status.md. Finish with REPORT.md.
```
