# Syntax for local reasoning — audit and proposals, 21 September 2026

**Question asked.** Which changes to the surface syntax would let a reader — an
agent reading one function, one call site, one signature — know what the code
does without opening anything else? "Context" here is literal: the declarations,
files and tool answers a reader must fetch before an edit is safe.

**Status.** Audit only. Nothing is implemented and no agent session was run.
Every count is a static probe over the corpus below; every behavioural claim was
run against the installed `zig-out/bin/mylang` (built 2026-09-21 20:00 from
`dcbcc2fd`, branch `perf/lever-search`). Probe sources are in the appendix.

**Corpus.** The non-test guest code in the tree: `src/schematic/guest` (14 files),
`src/stdlib` (12 files), the cascade baseline `experiments/cascade/designs/B`
(5 files) and `examples` (108 files): 139 files, 9,840 lines, 769 `def`s.

**Worked examples.** Each proposal below has a fuller before/after, with the
diagnostic it would emit, in
[local-reasoning-syntax-examples-2026-09-21.md](local-reasoning-syntax-examples-2026-09-21.md).

**Implementation plan.** Items 3.1–3.6 were selected for implementation; the
rules, decisions, files, tests and acceptance checks are in
[local-reasoning-implementation-plan-2026-09-21.md](local-reasoning-implementation-plan-2026-09-21.md).

**Sibling audit.** A separate session answered the same question the same day
in [local-reasoning-syntax-2026-09-21.md](local-reasoning-syntax-2026-09-21.md),
with its own probes under `experiments/local-reasoning-audit-20260921/`. The two
were written independently and agree on the first item (mutation visible at the
call site); this one adds the corpus counts, the unused-capability finding and
the keyword-only, tuple, conditional and `requires` items, and it does not
propose separating introduction from reassignment (see §4).

## 1. What "local reasoning" means for a reader here

A reader who has one function on screen wants six questions answered without
leaving it:

| # | Question | Answered locally today? |
| --- | --- | --- |
| Q1 | Does this call change any of the values I passed in? | **No.** `placeRows(ordered)` and `at(nodes, i)` look identical; the answer is in the callee's body, or in a `mutates(...)` clause the author was only warned to write. |
| Q2 | Can this call fail, do I/O, reach C, or depend on hidden state? | Mostly yes: `?` marks failure, capability parameters mark I/O and C, there are no globals. But 20 of the 41 `host: Host` parameters in the schematic guest are never used, so the signature over-claims. |
| Q3 | What can this value be — can it be absent, what do these integer constants mean? | **No** where the corpus uses sentinels: 24 `= -1` initialisations, 66 `== -1`/`< 0` tests, 30 `kind == 0`-style comparisons, 22 `Err(<int literal>)`. |
| Q4 | What does this argument list mean at the call site? | **No** for `io.issue(host, 13, 0, ref.span.start)`: 34 calls in the corpus pass an integer literal in a fourth-or-later position with no keyword. |
| Q5 | What shape does this call return? | Partly: a `Result`/`Option` is visible in how the value is consumed, but a two-value return is a named record the reader has to look up (`Step`, `DictItem`, `Pair`, …). |
| Q6 | Which binding is this, and could it have changed since I last looked? | Partly: loop variables are immutable and block-scoped, `E_UNBOUND` is static. But the 71 `i = 0 / while i < len(xs)` loops (against 49 `for` loops) reuse `i`, `j` across a whole function. |

Q1 is the one no tool answers at the call site, and it is the one every call
site raises. The rest are cheaper, and several are already half-landed.

## 2. What already serves local reasoning — keep it

These are the reasons the language is *closer* to the goal than Python, and
none of the proposals below should trade them away.

- **Authority is a parameter.** `def main(fs: Filesystem, out: Stream)` and
  `fs.read_text(...)`, `out.print(...)`: a body with no capability parameter
  cannot touch the outside world. There are no globals, no ambient `print`, no
  module initialiser. (`docs/io.md`, `docs/effects.md`.)
- **Failure is on the call line.** `parse(s)?` and `match parse(s): case Ok / case Err`;
  a dropped `Result` is `E_RESULT_UNHANDLED` and a dropped non-unit value is
  `E_EXPLICIT_DISCARD_REQUIRED` (probe p10). `_ = f(x)` therefore means "called
  for its effect" and nothing else.
- **`match` is exhaustive** over unions, enums, `Option` and `Result`; adding a
  case breaks every match rather than silently falling through.
- **The aliasing decision has landed.** `class` is a reference (probe p7 prints
  2), `record` is a copy, and a write to a record copy is now a hard error with a
  fix in the message (probes p1, q4). The charter answer "what is copied or shared
  at a call?" is Python's own, with one residue noted in §3.8.
- **Module-qualified names.** `s.at(nodes, i)`, `c.Pin`, `text.Span`: every
  imported name says where it lives; there is no `from x import *`.
- **`is None` narrowing already works** (probe q1, `[OPTION-FLOW-1]`), so the
  sentinel problem in §3.3 is one of adoption and of one missing method, not of a
  missing construct.
- **The loop variable is immutable** (probe p5, `E_IMMUTABLE`) and a `for`
  variable is block-scoped.

## 3. Proposals, ranked

Ranked by (calls or lines whose reader stops needing context) × (how often the
corpus hits it) ÷ (fidelity and implementation cost). Each proposal says what
the reader no longer has to open.

### 3.1 A call changes exactly its receiver and its `mut` arguments

**Rule.** A parameter that the function writes through — a list, dictionary,
`class`, `Cell`, array, or a record holding one — is declared `mut`:
`def placeRows(rows: mut list[Row])`. A call passes such an argument as
`placeRows(mut ordered)`. A method call may change its receiver and nothing
else. Writing through an unmarked parameter is an error, not a warning, and the
message carries the paste for both the declaration and the call.

**What is true today.** The declaration side exists as the trailing
`effects(mutation) mutates(parts, pins)` clause. It is *optional*: an
unannotated function that appends to its argument gets `W_MUTATES_MISSING`
(probes p2, p9) and runs; a write through a `class` parameter gets nothing at all
(probe q5 prints 2 with no diagnostic), because the clause exempts reference
parameters on the grounds that "writing through the reference is the reason the
parameter is passed". A call-site marker also exists, as an opt-in: under
`--mutation-markers` (`[MUTATION-MARKER-1]`) an argument bound to a position in
the callee's *declared* `mutates(...)` footprint must be written `&argument`.
Because it keys on the declared clause, it inherits the clause's gaps: a writer
with no clause, and every `class` writer, still accepts an unmarked call with
the flag on. So the call site shows nothing by default and, with the flag,
shows it only where the author already wrote the fact down. In the corpus, 32
declarations carry `mutates(...)` against 769 `def`s, so a reader has a
one-in-twenty-four chance the fact was written down.

The substantive change is therefore not the glyph but three rules: the marker
is required exactly where the compiler infers a write (both directions), it is
on by default, and `class` and `Cell` parameters are not exempt. The existing
`&` machinery can carry all three.

Decision D2 of the effects-as-arguments plan already accepted making the
footprint mandatory ("one version as a warning, then an error"); D3 deferred the
call-site marker pending loop evidence. This audit's claim is that the
call-site half is the local-reasoning payoff, and that the declaration half
without it moves the fact from the body to the signature — still one hop away.

**Before** (`src/schematic/guest/layout.my:434-435`, `schematic.my:28`):

```text
# doc: not-mylang
ordered = collectRows(host, parts, pins, nets, lookup)
_ = placeRows(ordered)                 # writes rows[i].side and rows[i].y; returns 0
...
circuit.normalize(host, parts, pins)   # rewrites six fields of every pin and part
```

The reader of `build` must open `placeRows` (58 lines) to learn that `ordered`
is different afterwards, and the reader of `schematic.build` must open
`normalize` (67 lines) plus its `mutates(parts, pins)` clause.

**After:**

```text
# doc: not-mylang
ordered = collectRows(host, parts, pins, nets, lookup)
placeRows(mut ordered)
...
circuit.normalize(host, mut parts, mut pins)
```

and every other call in the function — `pinGroup(pin, nets, lookup)`,
`nearest(host, pin, parts, pins, rows, nets, lookup)` — is now known to leave
its arguments alone without opening anything. The declaration becomes
`def placeRows(rows: mut list[Row]) -> None` and the trailing
`effects(mutation) mutates(rows)` disappears (it is derived).

**Spelling.** This audit prefers `mut` to the existing `&` because it reads as
a word and matches the declaration side; both look visibly unlike Python, so an
agent that sees either will not expect Python semantics, and an agent that omits
it gets a rejection whose fix is a paste. The choice is cosmetic and should not
hold up the three rules above; keeping `&` reuses `E_MUTATION_MARKER` as is.
`inout` was rejected in D4 for value records and is not needed: a `record`
parameter is a copy and stays unmarkable.

**Interaction with `class`.** The exemption goes. `bump(mut counter)` costs
four characters per call and answers Q1 for the only type whose writes are
otherwise invisible. Receivers stay unmarked: `counter.bump()` (once class
methods land) and `xs.append(1)` may change their receiver, which is the
Python prior and needs no marker.

**Costs.** Fidelity: every free-function call that mutates an argument is a
first-try failure for a Python-trained agent. The 20 September session record
says a rejection that carries its fix costs 0 turns; the diagnostic must carry
both pastes. Corpus migration: ~32 declarations and their call sites, and
`fmt --fix` can apply the inferred clause the compiler already prints.
Implementation: parser (`mut` in parameter and argument position), `sema`
(marker required ⇔ inferred write, both directions), `origins.zig` (drop the
class exemption), diagnostics with two fixes; the mutation analysis itself
exists. Medium.

**Falsify.** On the cascade pack, count bytes read before the first edit with
and without the marker on arm B rewritten by script. The prediction is a fall on
every task that touches a mutating helper (T2, T3, T5) and no change on the
printer task T4.

### 3.2 The signature is the whole contract; an unused capability is an error

**Rule.** Effects are derived from the parameter list — a `Stream` permits
`output`, a `Host` permits `host`, a `mut` parameter permits `mutation` — and
allocation is ambient. `effects(...)`, `noalloc` and `noio` survive only as
narrowings. A capability parameter the body never uses is an error, because it
tells the reader the function may do something it cannot.

This is lever L1 of the cascading-levers proposal, restated for its
local-reasoning half. What that proposal did not count is the over-claim: in the
schematic guest, 41 of 60 exports take `host: Host`, and for **20 of them** the
checked effect set is empty (`text.equal`, `text.matches`, `text.number`,
`sexpr.form`, `circuit.title`, `circuit.label`, …). A reader who trusts the
signature believes `text.equal(host, a, b)` can call into C. The parameter is a
fossil of the brace dialect's byte-compare intrinsic.

**Before** (`src/schematic/guest/text.my`, `layout_graph.my`):

```text
# doc: not-mylang
public def equal(host: Host, a: Span, b: Span) -> bool effects():
public def rail(host: Host, span: text.Span) -> bool effects(host, managed_allocation):
```

**After:**

```text
# doc: not-mylang
public def equal(a: Span, b: Span) -> bool:            # pure by signature
public def rail(host: Host, span: text.Span) -> bool:  # may reach C; may allocate
```

With 3.1 in place the reader's rule for any signature is one sentence: *no
capability parameter and no `mut` parameter means the function computes a value
from its arguments and nothing else.* That is what "purity" should mean to a
reader, and today it is not readable — the corpus writes `effects()` on 60
standard-library functions as a hand-maintained purity marker instead.

**Costs.** Counted in the levers proposal: 93 of 185 effect clauses restate the
derived set and are deleted; 80 are narrowings and stay. The unused-capability
rule is new: ~20 signatures in the schematic guest change, and their call sites
drop an argument. Implementation: the levers proposal's; plus one lint that is
trivially derivable from facts `list-interfaces` already prints
(`effects()` alongside `ceiling(host)`).

### 3.3 Retire sentinels: make `Option` as cheap as `-1`

**Finding.** The corpus reaches for integer sentinels because an `Option` costs
a four-line `match` at every use: 24 `= -1` initialisations, 66 `== -1` / `< 0`
tests, 15 `return -1`, and record fields `pin1: int`, `pin2: int`,
`net_id: int`, `display_id: int` whose absent value is `-1` by convention. A
reader of `if id < 0: return -1` in `layout.pinGroup` has to know two
conventions — the argument's and the result's — from outside the function.
`is None` narrowing already exists (probe q1); what is missing is the one-line
form for the common "absent means default" case.

**Rule.** Add `option.unwrap_or(default)` and `option.is_none()` /
`option.is_some()` as intrinsic methods, and let `Option[T]` fields carry a
`None` default. Then a lint under the `agent` profile flags an `int` field,
parameter or return that is compared against a negative literal in two or more
places and names the `Option[int]` rewrite.

**Before** (`layout.my`, `pinGroup`):

```text
# doc: not-mylang
def pinGroup(pin: c.Pin, nets: list[g.Net], lookup: list[int]) -> int:
    id = -1
    if pin.display_id >= 0 and pin.display_id < len(lookup):
        id = lookup[pin.display_id]
    if id < 0:
        return -1
    return nets[id].group
```

**After:**

```text
# doc: not-mylang
def pinGroup(pin: c.Pin, nets: list[g.Net], lookup: list[Option[int]]) -> Option[int]:
    if pin.display_id is None:
        return None
    id = lookup[pin.display_id]
    if id is None:
        return None
    return Some(nets[id].group)
```

The reader now knows from the signature that the group can be absent and that
`display_id` can be absent, and every caller's `if group is None` reads as
what it is instead of `if group < 0`.

Two spellings were considered and set aside. `x or default` on an `Option` is
the Python idiom for `d.get(k) or 0`, but it would give `or` a second typing
rule and conflict with the strict-`bool` condition rule the language chose
deliberately. `?` on an `Option` already works inside an `Option`-returning
function and covers the propagation case.

**Costs.** Two intrinsic methods, small. The lint is the same shape as the
existing `report-quality` signals. Fidelity improves (the velocity audit lists
`unwrap_or` under §3.3). Migration is per-site and optional.

### 3.4 Tuples for multi-value returns

**Finding.** A function that returns two values declares a record for them:
`Step(node, next)` in the cascade parser, `DictItem(key, value)` for
dictionary views, five such two-field records in the corpus by name and more by
shape. The reader of `step = parse_node(cursor)?` then `step.next` must look up
`Step` to learn it is a pair, and the reader of the declaration must find its
one caller to learn why it exists. The velocity audit (§3.2) already recommends
tuples for fidelity; this audit adds the local-reasoning reason: the shape of a
two-value result belongs at the call site.

**Rule.** Fixed-arity immutable `tuple[A, B]`, constructed by `a, b` in return
position and taken apart by `x, y = f(...)` and `for k, v in ...`. No indexing,
slicing or methods on day one, so it cannot become a lightweight record.

**Before / after** (`experiments/cascade/designs/B/sexpr/parser.my`):

```text
# doc: not-mylang
record Step:                                       # 4 lines, one caller
    node: ast.Node
    next: int
def parse_int(token, next_pos) -> Result[Step, ParseError]:
    return Ok(Step(node=ast.Node.integer(value, token.span), next=next_pos))
# ---
def parse_int(token, next_pos) -> Result[tuple[ast.Node, int], ParseError]:
    return Ok((ast.Node.integer(value, token.span), next_pos))
node, after = parse_int(token, pos)?
```

**Costs.** New runtime shape (an anonymous value record), lowering, printing,
equality. Medium. Fidelity improves on five of the 79 idiom-probe failures.

### 3.5 Keyword-only parameters, and a lint on positional literals

**Finding.** `io.issue(host, 13, 0, ref.span.start)` appears, with different
integers, at every error site in the schematic guest; `finding(t, 0, id,
other, first)` in the pin-roles application; 34 calls in the corpus pass an
integer literal in the fourth position or later. Keyword arguments exist and
are never used at these sites because nothing asks for them. Python's bare `*`
in a parameter list — `def issue(host: Host, *, code: int, file: int,
position: int)` — is the tool the callee uses to force it, and it is rejected
today (probe q2, `E_SYNTAX`).

**Rule.** Accept `*` in a parameter list, after which every parameter is
keyword-only, with the Python meaning exactly. Add an `agent`-profile lint that
flags a positional `bool`, integer or `None` literal in a call with three or
more arguments.

**Before / after:**

```text
# doc: not-mylang
_ = io.issue(host, 13, 0, s.at(nodes, f).span.start)
# ---
io.issue(host, code=13, file=0, position=s.at(nodes, f).span.start)
```

The second line still says `13`, which §3.3's enum lint and §3.6 address; but a
reader now knows *which* 13 without opening `io.issue`. This is also the cheapest
proposal in the list: it is a parser change and one arity rule.

### 3.6 Conditional expression

**Finding.** Because `y = a if c else b` is rejected (probe q3) and a name must be
definitely assigned before it is read, the corpus writes a dummy first:
`point = Point(x=-1, y=-1)` in `layout.build`, `side = -1` then `if i >= split:
side = 1` in `placeRows`, `edge = 352` then `if row.side == 1: edge = 532` in
`endpoint`. Each dummy is a value the reader has to decide is or is not
meaningful. The velocity audit lists the conditional expression as "Add"; the
local-reasoning reason is that the dummy disappears and the two candidate
values sit on one line.

```text
# doc: not-mylang
edge = 352
if row.side == 1:
    edge = 532
# ---
edge = 532 if row.side == 1 else 352
```

Small: parser and one typed node; both branches must agree in type, the
condition must be `bool`.

### 3.7 `requires` on the signature

**Rule.** A declaration may carry `requires <bool expression over its
parameters>` after the return type. It desugars to `assert` at entry, so it costs
what an assert costs and traps `R_ASSERT` with the clause's text; `list-interfaces`
and `context` print it with the signature.

**Why.** The reader of a call wants the callee's domain without its body:
`at(nodes, index)` returns a synthetic atom for an index out of range (a fact
buried in its body), `partPin(part, number, ...)` handles `number` 1 or 2 and
returns a placeholder pin otherwise, `si_scale(letter)` answers 1.0 for any
unknown letter. Today these are comments, or nothing. A `requires 1 <= number
<= 2` on `partPin` is a contract the reader sees at the signature and the caller
gets checked. It is the cheapest form of lever L2 (docstring examples): a
predicate on the signature rather than an example beside it.

```text
# doc: not-mylang
def partPin(part: int, number: int, parts: list[c.Part], pins: list[c.Pin]) -> c.Pin requires 1 <= number <= 2:
```

Small to implement; the chained comparison is a separate idiom-probe item
(a02) that this clause would want.

### 3.8 Records are deep values, or they are classes

**Residue of the aliasing decision.** `record` copies its fields, but a managed
field — a list, dictionary or a record holding one — is shared by the copy
(`docs/statements.md`, the `Tally` example). So the reader of `pin = pins[i]`
followed by `pin.net.source` still has to know whether `Span.source` is a
`bytes` (immutable, fine) or a list (shared, a write reaches every copy). The
compiler catches the write to the copy's own field (`E_DEAD_RECORD_WRITE`) but
not `copy.items.append(x)`, which is the write Python programmers expect to be
local and here is not.

**Option A (small).** Warn on a mutating method or indexed write through a
managed field of a record copy — `W_SHARED_FIELD_WRITE` — naming the sharing.
This is the same analysis as the dead-write check with one more hop.

**Option B (larger).** A `record` may hold only scalars, `str`, `bytes`, enums,
other records and fixed arrays; anything with a mutable managed field must be a
`class`. Then "record and scalars copy; class, list, dict share" holds with no
mixed case at all, and Q1 is answered by the *type* of every field. The cost is
real: `record Node: children: list[Node]` in the docs becomes a class (which is
what it is), and every record in the corpus with a list field migrates. This is
a language decision, not an audit finding; it is listed because it is the last
place the copy-or-share answer is "depending".

### 3.9 Lints for what the syntax already offers

None of these need syntax; they need the compiler to say the shorter spelling
exists. They belong under the `agent` lint profile with the fix in the message.

| Corpus pattern | Count | Existing construct | Why the reader cares |
| --- | --- | ---: | --- |
| `i = 0` / `while i < len(xs)` / `xs[i]` / `i += 1` | 71 | `for x in xs`, `for i, x in enumerate(xs)` | The `for` header names what is iterated; the `while` hides it in the body, and reuses `i` across loops. |
| `kind == 0`, `kind != 0`, `item.kind == 1` | 30 | `enum Kind` + exhaustive `match` | An int comparison names nothing and cannot be exhaustive. |
| `Err(13)` and `-> Result[T, int]` | 22 | `union Error` with named cases | `Err(13)` is opaque at every `case Err(code)`. |
| `j = len(parts)` to leave a loop | 1 | `break` | A reader searches for where `j` is read next. |
| `_ = f(...)` where `f -> int` always returns 0 | ~25 | `-> None` | `_ =` should mean "value ignored", not "vestigial return". |
| `c == 40u8` on bytes | 63 (cascade) / 29 (letters) | `ord("(")`, folded to a constant | Already landed for `ord`; the lint names it. |

The index-loop rule needs one caveat: the schematic's s-expression walk
advances by `i = s.at(nodes, i).next`, which is a genuine `while`. The lint
should fire only when the loop body advances `i` by exactly one and reads
`xs[i]`.

### 3.10 Formatter: `- 1`

The formatter prints a negative literal as `- 1` (`pin1=- 1`, `return - 1`),
which reads as a dangling binary minus. Print `-1`. Trivial; listed because it
is the only place the *canonical* layout makes a value harder to read.

## 4. Considered and not recommended

- **Immutable locals by default (`let` / `final`).** Would answer Q6 in full,
  but every Python-trained first draft reassigns freely; the fidelity cost is
  paid on every function. The immutable loop variable and the block-scoped
  `for`/`match` bindings already cover the cases the corpus actually confuses.
- **Block-scoped assignment.** Python is function-scoped; the language chose
  that deliberately and documents it. The §3.9 index-loop lint removes the
  reuse that makes function scope hard to read.
- **Methods as a local-reasoning aid.** `nodes.at(i)` versus `s.at(nodes, i)`
  carries the same information; methods help fidelity, not locality, and a
  method that mutates `self` must stay unmarked (the receiver rule in §3.1).
- **`_`-prefix privacy instead of `public`.** Neutral for local reasoning: both
  are on the declaration line. Lever L3 should be argued on ceremony, not here.
- **A call-site marker for `Result` (`try f()`).** `?` already is one.
- **`x or default` on `Option`.** See §3.3: it would loosen the one typing rule
  that makes conditions readable.

## 5. What it adds up to

With §3.1 and §3.2 in place, a signature answers every one of Q1–Q2 by
itself and a call line answers Q1:

```text
# doc: not-mylang
def normalize(host: Host, parts: mut list[Part], pins: mut list[Pin]) -> None:
    #           may reach C  written          written              no result
def equal(a: Span, b: Span) -> bool:
    #  no capability, no mut: a pure function of its arguments
circuit.normalize(host, mut parts, mut pins)
    #  the only two values this line can change
```

§3.3–§3.5 remove the conventions a reader has to import (`-1`, `kind == 0`,
`13`); §3.6–§3.7 put the remaining facts (the chosen branch, the domain) on
the line where the reader is. §3.8 closes the last "depending" in the aliasing
answer, at a cost the language has to decide it wants.

Suggested order: **3.5, 3.6, 3.10** (each a parser change, no semantics),
then **3.1 with 3.2** as one change under one rule, then **3.3** and **3.4**,
with **3.9** lints landing whenever their profile is touched. The cascade pack
and its phase-split records (bytes read before the first edit; failed checks on
changed source) are the instrument, per the levers proposal §5; the prediction
for 3.1+3.2 is a fall in bytes read on the mutating-helper tasks and no rise in
failed checks once the rejections carry their pastes.

## Appendix — probes

All run on 2026-09-21 with `zig-out/bin/mylang run <file> --print-result`.

| Probe | Program | Result |
| --- | --- | --- |
| p1 | write through a `record` parameter | `E_DEAD_RECORD_WRITE`, fix names `class` |
| p2 | `append` through an unannotated `list` parameter | `W_MUTATES_MISSING`, prints 1 |
| p3 | `v == None` on `Option[int]` then use `v` | `E_TYPE: expected int, found Option[int]` |
| p4 | `return a // b, a % b` | `E_SYNTAX`, alternative names a record |
| p5 | assign to a `for` variable | `E_IMMUTABLE` |
| p6 | `int("x").unwrap_or(7)` | `E_COLLECTION_METHOD` (method list has no `unwrap_or`) |
| p7 | write through a `class` parameter, read in caller | prints 2 (reference semantics landed) |
| p8 | `enum` field compared with `==` | prints 1 |
| p9 | indexed write through an unannotated parameter | `W_MUTATES_MISSING`, prints 9 |
| p10 | drop a `Result` | `E_EXPLICIT_DISCARD_REQUIRED` |
| q1 | `if v is None: return 0` then `return v` | prints 42 (narrowing works) |
| q2 | `def f(a: int, *, b: int)` | `E_SYNTAX: expected a name` |
| q3 | `y = 42 if x > 0 else 0` | `E_SYNTAX`, alternative names if/else |
| q4 | `for row in rows: row.y = 5` on records | `E_DEAD_RECORD_WRITE` |
| q5 | write through a `class` parameter with no clause | prints 2, **no diagnostic** |

Static counts were produced with `grep` over the corpus files; the exact
patterns are the ones quoted in §1 and §3.9, and the unused-capability count
came from `mylang list-interfaces src/schematic/guest/main.my` by selecting
exports whose `effects(...)` set lacks `host` while the parameter list has
`host:host_cap`.
