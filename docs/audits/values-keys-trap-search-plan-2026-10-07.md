# Values and keys, trap search, and test-backed simplifications: plan, 2026-10-07

Status: **designed with the user in conversation on 2026-10-07. VK7–VK10 confirmed the
same day, with one change to VK8: `@noalloc` is checked by the new core at build time, not
by trap search.** AM1–AM3 are applied to the front-end plan (`befaf67e` on
`claude/frontend-plan`). §2 lists what is accepted and what waits for data. Nothing here is
implemented. Read-only packages can start now. Every language change waits for the
front-end waves that own the same files.

**Updated 2026-10-08, after S5 merged into `main` at `5a6b501d`:**
- the launch order follows the front-end plan's waves: VP1 and VP2 now, VP3 after FB1,
  and the T wave at the front-end plan's F1 exit;
- §1's facts are rechecked against `main`;
- the front-end plan's slow-step rule (its §6.1) applies here too.

**The user's goal.** Maximize development speed:
- fast runtime;
- fast compile and test loops;
- a language that is locally understandable, so an AI agent can work on code without a
  lot of extra context.

**What the plan does.**
1. **Values and keys (memory model).**
   - Everything is a value, and anything with identity is a key into a table.
   - A built-in, dict-shaped `table[T]` with folder ownership replaces the `pool` library.
   - Static ownership (the compiler frees each value at its last use, with no counts) is
     measured against the new core's one-count RC and adopted only if it wins (§4.5).
2. **Failures.** Traps stay for bugs; expected failures are `Result` or `Option`. Traps
   become unlikely through two test-runner features, gated in `mylang test` and never in
   `check`:
   - **trap search:** every public function is property-tested for traps automatically;
   - **trap coverage:** every place that can trap must be reached by some test.
3. **Simplifications backed by tests.**
   - Delete the effect layer; authority already arrives only through parameters.
   - `noalloc` becomes `@noalloc`, checked by the new core at build time instead of by
     the checker's call-graph rule.
   - Domains become records with `@invariant`.
   - Contracts stay, because trap search and the interface tools read them.

**Plans this one depends on. Read them first:**
- **The new-core plan (S0–S5)**, `claude/new-core-s4-design:docs/audits/new-core-plan-2026-10-05.md`.
  Codex is in S4 (`codex/new-core-s4-*`). The core does ownership with one count, borrow
  inference and uniqueness tests.
- **The front-end plan.** The proposal and the implementation plan are on
  `claude/frontend-plan`: `docs/audits/frontend-plan-after-new-core-2026-10-06.md` ("the
  front-end proposal") and `docs/audits/frontend-implementation-plan-2026-10-06.md` ("the
  front-end plan").
  - FE1–FE7 were accepted on 2026-10-06.
  - Since its 2026-10-08 update, it runs from `main` at `5a6b501d`. F0 was mostly done by
    S5, so its waves are wave 1 (F1 with FP2 and FB1), then F2–F5.
  - **This plan amends it in three places (§4.2).** The user confirmed all three on
    2026-10-07, and they are applied there.
- **Local-reasoning item 2** (effect ceilings derived from the signature) is merged into
  `main`; `local-reasoning/integration`'s last commit is from 2026-09-22. AM2 deletes the
  effect checking it refined (§3.7).

## Launch instructions (for Codex)

**Now, beside the front-end plan's wave 1.** Neither package changes a compiler file:

> Run packages VP1 and VP2 of `docs/audits/values-keys-trap-search-plan-2026-10-07.md`,
> as committed on branch `claude/frontend-plan`. Use one new branch each, `codex/vk-vp1`
> and `codex/vk-vp2`, created from that commit. Change no compiler file.
> - VP2 uses the front-end plan's S5 pin: a ReleaseFast `mylang` built from `main` at
>   `5a6b501d`. Reuse the front-end coordinator's pin if it exists.
> - Both share the limit of four build-heavy agents with the front-end plan, and
>   front-end packages take free slots first. VP1 builds nothing; VP2 takes one slot
>   while it runs `mylang test`.
> - Apply the front-end plan's §6.1 slow-step rule.
> - Finish each with its report and stop. Never merge into `main` and never push.

**VP3 runs now (2026-10-08), by a Claude agent at the user's request.** It follows FB1
rather than running beside it, because both add to the core's stats code. Its branch is
`claude/vk-vp3`, created from `codex/frontend-cost-cli`, FB1's final state. It merges
`claude/bench-newcore` for the three NEW-CORE-TAKE-READS-1 fixes; without them the Lox
interpreter copies its whole heap on every append, which would swamp the counts. VP3
touches only `src/core/`, never merges into `main` and never pushes. §4.1 has the
retargeted exit.

**The front-end amendments** (§4.2, AM1–AM3) are already applied to the front-end plan.

**At the front-end plan's F1 exit, with the user's go for F2:**

> Implement the T wave of the values-and-keys plan on `codex/vk-trap-search`, created from
> `codex/frontend-integration` at the F1 exit. It runs in parallel with F2–F4 and owns only
> the files listed per package. It shares the limit of four build-heavy agents, and
> front-end packages take free slots first. Merge T2 and F3-C1 one at a time: both touch
> where the core emits checks. Apply the front-end plan's §6.1 slow-step rule. Stop after
> T1-R with its report.

**Why the T wave waits for the F1 exit:**
- Front-end wave 1 already fills the four build-heavy slots: F1-0, FB1 and FP2, then
  four F1 lanes and F1-D.
- T1-R runs trap search over `tests/lang`, `src/stdlib`, Lox and EDA, which are the
  corpora F1 migrates. A run started mid-migration would report on code that is about to
  change.
- T1's fixtures would be written in spellings F1 removes.

**After F4, after the user's go:** the V wave, on `codex/vk-tables`.

**The CE wave (§4.5) is done and merged into `main` (`3e210ffba`, 2026-10-08).** CE-A ran on
`claude/ce-records` and CE-B on `claude/ce-lists`, integrated on `claude/copy-elim`. It
replaced the O wave, which VP3's data ruled out.

**The CE2 wave (§4.5, "CE2") runs now (2026-10-08).** Claude agents run it at the user's
request: CE2-A on `claude/ce2-effects` and CE2-B on `claude/ce2-results`, integrated on
`claude/copy-elim-2`.

## 1. Where it starts

- **Repository facts.**
  - They were first taken from `main` at `df55c52d7`.
  - On 2026-10-08 they were rechecked against `main` at `5a6b501d`, which is S5 merged.
  - **File ownership** names the new core's files on `main`. The old back end and its
    test runner are deleted.
- **S5 is done.** The front end is no longer shared with an old core, so the freeze
  before S5 no longer applies. Front-end files are owned by the front-end plan's
  packages, so T and V packages change them only through that plan's coordinator.
- **Corpora**, the same as the front-end plan's:
  - the EDA slice: `eda-bench` `claude/s4-eda-newcore` `7e938b6` (310 tests, 34 goldens);
  - the Lox port: `codex/s4-lox-value-semantics` `f44302d8`;
  - `src/stdlib`;
  - `tests/lang`;
  - for performance, the 46 rows used by FB1.
- **The oracle** is the front-end plan's (its §1): S5-0's frozen references, plus the S5
  pin built once from `main` at `5a6b501d`.
- **Existing machinery this plan builds on:**
  - **Property tests** (`docs/tooling/guest-tests.md` "Property tests").
    - **They run in the new core's runner:** `src/core/test_runner_property.zig` and
      `src/core/property_*.zig` (generation, shrinking, types, execution, rendering).
      The old back end's `src/native_test_property.zig` was deleted by S5.

    They provide:
    - deterministic inputs from the parameter types, biased toward edge values;
    - discarding of inputs that break the test's own `@requires` or a parameter's
      `@invariant`;
    - shrinking, reproducible seeds, and per-test result caching.
  - **Deterministic capability stand-ins** (`filesystem.memory`, `time.simulated_clock`,
    `random.seeded_entropy`, `environment.fixed`, `network.denied`) and test capability
    parameters.
  - **Contracts** (`docs/contracts.md`):
    - they are checked in every build;
    - `R_REQUIRES` names the caller that broke the requirement;
    - contracts are part of the interface (`list-interfaces`, `context`, `api-diff`).
  - **Structured trap records** (`structured-native-trap-detail`). `mylang invoke` was
    retired by S5 (S5-D5); trap search drives functions through generated tests instead.
  - **`mylang lint`** with profiles, waivers and `--gate`; **`mylang test --affected
    --against REF`**.
  - **The `pool` module** (`src/stdlib/pool.my`): generation-checked handles. It is used
    in one file in each of `src/stdlib`, `tests/lang` and `tests/value_semantics`.

## 2. Decisions

### Accepted by the user (conversation, 2026-10-07)

| # | Decision |
|---|---|
| **VK1** | **Two rules.** (1) Everything is a value, and anything with identity is a key into a table. (2) A call changes a caller's variable only through a `mut` argument. |
| **VK2** | **Tables and keys** replace the `pool` library, with the dict-shaped API of §3.2. Key numbers are never reused. `t[k]` and `t.pop(k)` trap with `R_MISSING_KEY` on a missing key; `t.get(k)` and `k in t` do not. |
| **VK3** | **Folder ownership in tables.** An entry may be added under an owner. Removing an entry removes everything it owns, and the table maintains the children and owner links. |
| **VK4** | **Failure model.** Bugs trap; expected failures are `Result`/`Option`. No compile-time proof obligations. The compiler's facts serve only the optimizer (front-end proposal B5). `int` stays fixed-width, with checked overflow. Traps can later be caught at task or isolated-call boundaries (C1). |
| **VK5** | **Trap search and trap coverage**, gated in `mylang test` and the lint gate, never in `check`. |
| **VK6** | **`prune`** (compiler-generated cleanup of unreachable table entries) is built only if VP1 finds shared data that does not fit a tree. |

**One change from the conversation.** The conversation wrote removal as `del t[k]`. The plan
writes it `t.pop(k)`, because `del` is a removed spelling:
- `src/removed_names.zig` says "remove with `_ = xs.pop(index)` for a list or
  `_ = d.pop(key)` for a dictionary";
- the front-end plan's one-way rule keeps it out.

The semantics are unchanged.

### Confirmed by the user (2026-10-07); each changes an accepted front-end row

| # | Decision | Amends | Why |
|---|---|---|---|
| **VK7** | **Keep `@requires`, `@ensures` and `@invariant`** | Reverses FE1/A6, which replaced them with `assert` | **Keep.** Trap search needs `@requires`: it discards inputs that break the requirement instead of failing on them, and it blames the caller. `@invariant` filters generated records. `@ensures` becomes a free property checked on every generated input. All three show up in `context` and `api-diff`, where an agent reads them without opening the body. An `assert` in the body gives none of this. |
| **VK8** | **Delete effect checking entirely.** `noalloc` becomes the attribute `@noalloc`, **checked by the new core at build time** (the user's change: the draft had trap search check it) | A4 (keeps `noalloc` as the only effect annotation), A5, B6, and F2-C2 (keeps the per-body `E_EFFECT_BOUND` and "callees must be `noalloc`") | **Delete.** `docs/effects.md`: "Real authority reaches a body only through its parameters." Once A4 removes every clause except `noalloc`, the per-body check has nothing left to enforce except `noalloc`, and the checker's `noalloc` needs every callee annotated too. **The build-time check needs no propagation either:** the core sees the whole program, so it follows every path, not only the inputs trap search happens to generate. It reports the warning `W_NOALLOC_ALLOCATES` and the lint gate blocks on it, so `check` gains no whole-program obligation (VK4). Uses: 4 in `src/stdlib`, 9 test files. |
| **VK9** | **Domains become records with `@invariant`** (new row A16) | Adds a row to FE1. Needs VK7 | **Do it.** A domain is a second kind of type, with its own members, private functions and `wrap`/`unwrap`. What it protects is that only valid values exist, and `@invariant` checks that wherever a value is built or changed. There are 16 domain declarations in 12 files. |
| **VK10** | **Name:** `table[T]` and `key[T]` | Docs call the enum-indexed `[Kind]T` arrays "tables" (`E_TABLE_KEY`, `E_INCOMPLETE_TABLE`) | **`table`**, the word an agent reaches for. Rename the `[Kind]T` prose to "enum arrays" and those two codes to `E_ENUM_ARRAY_KEY` and `E_INCOMPLETE_ENUM_ARRAY`. The alternative is keeping `pool[T]`, which reads as a memory pool. |

### Decided later, on data

| # | Decision | Decided by |
|---|---|---|
| **VK11** | Open files, sockets and directory handles become keys handed out by their capability (§3.9) | V2's inventory, after V1 |
| **VK12** | Static ownership replaces one-count RC in the core | **Decided by VP3 (2026-10-08): no.** The rows net 0.47% (threshold 3%); EDA −15%; Lox ×4.9 instructions. The CE wave (§4.5) replaces the O wave. |
| **VK13** | Shrink the path-sensitive `Result` rules (`E_RESULT_PATH`, `E_RESULT_OVERWRITE`, `E_RESULT_LOOP`, `E_RESULT_CONSUMED`) to one local rule, "a `Result` must be used" | Only if T3's failure injection is in place and the idiom suite shows friction from those rules |
| **VK14** | Remove inline structural requirements too, beyond A15 | A typed count of their uses. Not in this plan's packages |
| **VK15** | Merge `byte_buffer` into `bytes`, and drop B7's `byte_buffer` lint | Only if VK12 adopts static ownership, which makes `s += x` append in place |
| **VK16** | Trap containment: `isolate(f, ...)` returns `Err(trap)`, and tasks fail alone | C1's design note, built with concurrency (D9 stage 5) |

## 3. The design

### 3.1 Two rules

1. **Everything is a value, and anything with identity is a key into a table.**
   - Your own entities (widgets, nets, AST nodes) are keys into your tables.
   - The outside world's (open files, sockets) are keys handed out by their capability
     (§3.9).
2. **A call changes a caller's variable only through a `mut` argument,** marked at both
   ends, as today.

Value semantics is already the default (`docs/value-semantics.md`). Tables are what VK1
adds.

### 3.2 Tables and keys (V1)

**Types.** `table[T]` holds values of any value type `T`. `key[T]` names one entry.
`t: table[Widget] = table()` builds an empty table, inferring the element type the way `[]`
does.

| Operation | Result | When the key is not in the table |
|---|---|---|
| `t.add(v)` | a new `key[T]` for a new top-level entry | — |
| `t.add(v, owner=k)` | a new `key[T]` for an entry owned by `k` | `R_MISSING_KEY` for `k` |
| `t[k]` | the entry, as a value | `R_MISSING_KEY` |
| `t[k] = v`, `t[k].f = x`, `t[k].items.append(x)` | changes the entry in place | `R_MISSING_KEY`; `[]` never inserts |
| `t.get(k)` | `Option[T]` | `None` |
| `k in t` | `bool` | `False` |
| `t.pop(k)` | removes `k` and, transitively, every entry it owns; returns `k`'s value | `R_MISSING_KEY` |
| `len(t)` | the number of entries | — |
| `for k in t:` | every key present when the loop starts, in insertion order, skipping any removed during the loop | — |
| `t.roots()` | `list[key[T]]`: the top-level keys, in insertion order | — |
| `t.children(k)` | `list[key[T]]`: the entries `k` owns, in insertion order | `R_MISSING_KEY` |
| `t.owner(k)` | `Option[key[T]]` | `R_MISSING_KEY` |
| `t.move(k, owner=o)` | makes `o` (an `Option[key[T]]`; `None` means top level) `k`'s owner | `R_MISSING_KEY`; `R_OWNER_CYCLE` if `o` is `k` or inside `k` |

**Keys:**
- **A key is a plain value.** It can be stored in records, lists and dicts, compared with
  `==`, hashed (dict keys, set elements) and printed as `Widget#41`. No conversion makes a
  key from an integer, and keys are not typed-JSON values for now.
- **A key carries a slot index and a serial number.** The serial is never reused anywhere
  in the process. A lookup compares the serial with the one stored in the slot, so all of
  these simply fail to match:
  - a removed key;
  - a key from another table;
  - a key whose slot a new entry reuses.
- **A key does not keep its entry alive.**

**Tables are values:**
- A function that changes one takes it as `mut`.
- Copying a table copies its entries under the same keys, as copying a dict does. Entries
  added to either copy afterwards get new serials, so the copies never collide.
- `w = t[k]` makes a copy, and changing `w` does not change the table. The existing
  dead-write diagnostic (`E_DEAD_RECORD_WRITE`) already catches a modified copy that is
  never used again.

**Owners:**
- An owner must be in the same table. For trees of mixed types, use a union as the element
  type.
- `pop` removes the subtree and unlinks `k` from its owner's children.
- Keys that the program stored itself are never updated. A key stored in a record field (a
  "focused" widget, a net's pin list) simply stops matching when its entry is removed.

**Traps:**
- A missing key raises today's dict trap, `R_MISSING_KEY`:
  `app.my:58:9: error[R_MISSING_KEY]: key Widget#41 is not in table `ui`; removed at app.my:31:9 in close`.
- Debug and test builds record where each serial was removed, and whether a key belongs
  to a different table. Release builds report the key and the table.

**Costs:**
- A lookup checks the slot is in range and compares one serial.
- `add`, `pop` of a leaf, and `move` take constant time; `pop` of a subtree takes time
  proportional to its size.
- A key is 16 bytes in v1.

**`pool` is removed:**
- removed spelling `E_POOL_REMOVED`, naming `table`;
- the three files that use it are migrated by hand;
- `Handle[T]` becomes `key[T]`.

**Dict consistency.** `d.get(k)` with one argument returns `Option[V]`, beside today's
`d.get(k, fallback)`.

### 3.3 Failure model (accepted, VK4)

- **Bugs trap and stop the program,** with the code, the line and the values:
  - an index out of range;
  - a missing key through `[]` or `pop`;
  - overflow and division by zero;
  - a failed `assert` and a broken contract.
- **Expected failures are values.** I/O, parsing, and lookups that may miss return
  `Result` or `Option`.
- **No proof obligations at compile time.** The compiler's facts remove runtime checks
  (front-end proposal B5) and never reject a program.
- **`main` may already return `Result[int, int]`.** V3 adds `Result[int, str]` and
  `Result[None, str]`: an `Err` prints its message to standard error and exits 1.
- **Catching traps at a boundary is designed in C1,** not built here.

### 3.4 Contracts (VK7)

- **`@requires`** is for problems the caller can always avoid and that are a bug if it
  doesn't, such as an index into a list the caller owns.
- **`Result`/`Option`** is for data that may legitimately be bad (user input, file
  contents).
- **`assert`** is for something that should be impossible inside the function.

The docs (`docs/contracts.md`) state this rule. Contracts stay checked in every build.

### 3.5 Trap search (T1, T3)

**What it checks.** Every public function is an implicit property: for every generated input
that satisfies its `@requires` and its parameters' `@invariant`s, the call returns without
trapping, and its `@ensures` hold. No test code is written for this.

**What is searched:**
- every `public def` in the project's non-test modules, except those listed as not
  searched (below);
- each search is a test entry named `trap::<module>::<function>`, so `--filter`, caching,
  `--affected` and reproduction work exactly as for tests.

**Inputs:**
- **Data parameters:** generated by the property-test generator (same seeds, sizes and edge
  bias). `mut` parameters are generated like any other.
- **Capabilities:** `Stream` gets a buffer; `Filesystem`, `Clock`, `Entropy`,
  `Environment` and `Network` get the deterministic stand-ins.
- **Not searched** (listed in the report with the reason):
  - parameters of type `Host` or a function type, and domains until A16;
  - generic functions (v1);
  - a function whose generated inputs are discarded more than ten times the run count
    ("precondition too narrow", naming the clause that discarded most).

**Outcomes:**
- **Discarded:** an input that breaks the searched function's own `@requires`, or an
  `@invariant` of a parameter value.
- **Failure:**
  - any trap during the call, including a callee's `R_REQUIRES`;
  - an `@ensures` violation;
  - a call that exceeds the test timeout;
  - with T3, an `Err` dropped without being handled.
- **Not a failure:** returning `Err` or `None`.

**Report**, shrunk to the smallest input:

```text
failed trap::labels::label_for: R_LIST_BOUNDS at labels.my:2:12 (index 0, length 0)
  smallest input: names=[] index=0 (3 shrinks)
  fix: return Option[str]; add @requires so callers must pass a valid index; or handle the case
  reproduce: mylang test app/main.my --filter 'trap::labels::label_for' --seed 4128163384585622329
```

**Runs and cost:**
- 100 runs per function by default; `--trap-runs N` changes it.
- A function's result is cached by the code it reaches, like a test result, so an edit
  re-searches only the functions it affects.

**Configuration.** In `mylang.json`: `"trap_search": "gate" | "report" | "off"`. The
default is `"report"` until the user changes it at T1-R's stop. `mylang lint --gate
--profile=agent` blocks on trap-search failures when the setting is `"gate"`.

**T3 adds:**
- **Hints from trap sites.** The generator also tries values aimed at each site the function
  reaches:
  - an index's list length minus one, its length, -1 and minus the length minus one;
  - a zero divisor;
  - an empty list for `pop`, `min` and `max`;
  - removed keys and keys from another table (with T4);
  - out-of-range values for conversions.

  A hint applies when the operand is a parameter, `len(parameter)`, or either plus or minus
  a constant.
- **Failure injection.** On some runs (chosen by the seed), the stand-ins fail on purpose:
  a missing file, a failed write, a refused connection. The function must not trap. Test
  builds mark an `Err` that came from an injected failure; if it is destroyed without
  being matched, propagated or returned, the run fails with
  `Err from fs.read_text at x.my:12 was dropped at x.my:15`.

`@noalloc` is not part of trap search. The new core checks it at build time (§3.7).

### 3.6 Trap coverage (T2)

**Trap sites.** In test builds the core assigns an id, a span and a kind to every place that
can trap:
- indexing (list, `str`, `bytes`, fixed arrays);
- key lookups and `pop` (dict, table, list);
- division, modulo and shifts;
- checked overflow and narrowing conversions;
- `pop`, `min` and `max` on an empty collection;
- `assert` statements;
- calls to a function with `@requires`, `@ensures` checks and `@invariant` checks;
- text scalar construction.

Each executed site increments a counter. Sites go through the core's emitted checks. No
`ir.zig` change: the front-end plan freezes it through F4.

**A site counts as covered when** any test or trap-search run reached it, or when FB1's
report proves the check unnecessary for that function. A comment `# trap-site: <reason>` on
the site's line waives it. Waivers are listed in every report, and the strict lint profile
forbids them.

**Report:**

```text
trap coverage: 41 of 43 sites covered (35 reached, 5 proved, 1 waived)
  never reached: parser.my:88:21   tokens[pos + 1]   R_LIST_BOUNDS
                 parser.my:131:9   width // count     R_DIVISION_BY_ZERO
```

**When it runs.** Full runs, and `--affected` runs over the affected functions. A filtered
run reports nothing. The setting is `"trap_coverage": "gate" | "report" | "off"`, default
`"report"` until T1-R's stop.

### 3.7 Effects, `noalloc` and domains (§4.2 amendments, VK8, VK9)

**Effects (VK8):**
- After A4, every ceiling derives from parameter types. Authority only arrives through
  parameters, so the derived ceiling is already enforced by name resolution and types.
- F2-C2 therefore deletes the per-body check (`E_EFFECT_BOUND`), the inferred effect sets,
  callback-type ceilings and `E_DERIVED_EFFECTS`.
- It keeps `E_UNUSED_CAPABILITY`, which moves into sema's binding-usage check.
- Function types lose their effect clause: a callback that prints takes a `Stream`.
- The P4 run (front-end plan F2-C2 step 1) proves that no verdict changes, except for
  programs that relied on `noalloc` being checked by the checker. The build-time check
  covers them.

**`noalloc` (VK8).**
- **Spelling:** `noalloc` after a signature becomes the attribute `@noalloc`, the same form
  as contracts.
- **Who checks it: the new core, at build time** (front-end plan F2-C2 step 3):
  - over the whole program, before optimization, so debug and release builds agree;
  - through every callee, with no annotation needed on callees;
  - a call through a function value whose target the core cannot resolve counts as
    allocating;
  - FB1's definition of "allocates" is used.
- **A violation is the warning `W_NOALLOC_ALLOCATES`,** naming the allocation site and the
  call chain. `mylang lint --gate` blocks on it; `check` never rejects for it.
- **Migration:** fix rule "move the clause to an attribute"; 4 stdlib uses.

**Domains (VK9, row A16):**
- `domain D: base:` with members becomes `record D: value: base`.
- The member that validated becomes an `@invariant(...)`.
- `wrap[D](v)` becomes `D(value=v)`, and `unwrap(d)` becomes `d.value`.
- Members become top-level functions in the domain's module, and `private def` members
  become module-private.
- **Removed spelling:** `E_DOMAIN_REMOVED`, naming the replacement. The 16 declarations are
  migrated by hand, together with domain codecs (`src/domain_codecs.zig`,
  `examples/domain-codecs`).
- **Check:** a one-field record has the same layout and cost as its field in the core.
  FB1's report and `dump-ir` confirm it on the migrated examples.

### 3.8 Static ownership (O wave, VK12)

**Not adopted (VP3, 2026-10-08).** This section is kept as the design that was
measured; §4.5 has the data and the CE wave that replaced it.

The meaning is unchanged: value semantics. Only the implementation in the core changes:
- **One owner per buffer.** It is freed at its last use, on each control-flow edge where it
  dies, so no runtime drop flags are needed.
- **Moves and borrows.** A value moves at its last use. A read-only parameter is borrowed.
- **Copies instead of shared counts.** Where one-count RC would let two owners share a
  buffer, the compiler copies.
- **In-place reuse.** A dying buffer is reused in place when a value of the same shape is
  built at the same point.
- **Gone:** counts, uniqueness tests and the count word in the header.
- **No `own` keyword:**
  - for module-private functions, the compiler infers whether a parameter is consumed;
  - public functions borrow and copy what they keep, so a body edit never changes an
    interface;
  - release builds may still infer across modules.
- **Tables own their entries.**
- **The copies left are listed** by FB1's report (`W_HIDDEN_COPY` in F5).

### 3.9 Resources as keys (V2, VK11; proposed)

- `f = fs.open(path)?` returns a key. Reading and writing take the key, and `fs.close(f)`
  removes it.
- A closed key traps `R_MISSING_KEY` ("closed at …"), just like a removed table entry.
- `with fs.open(path) as f:` stays (A14) and closes at the end of the block.
- A forgotten close leaks until exit, as a forgotten table entry does.
- This deletes the owned-resource rules: `E_OWNED_CONSUMED`, `E_OWNED_PATH`,
  `E_OWNED_LOOP`, the `E_RESOURCE_*` codes and `E_WITH_RESOURCE`.
- V2 starts with an inventory of every resource kind and its rules, and stops for the
  user before changing any.

### 3.10 `prune` (V4, built only if VP1 says so)

- `prune(mut app)` removes every table entry inside `app` that no key in `app` reaches.
- The compiler generates the walk from the types, which say which fields hold keys into
  which tables.
- The checker rejects a call while any live variable outside `app`, in the function or a
  caller, could hold a key into those tables. A derived fact on each function records
  whether it prunes. The error names the variable.
- Its cost is proportional to the reachable entries, and it runs only where it is written.

### 3.11 What does not change

- Python spelling.
- `mut` at both ends.
- Capability parameters.
- `match`, `Result` with `?`, `Option` with `is None`.
- Value semantics.
- Fixed-width integers with checked overflow.
- No closures, no methods, no exceptions.
- Everything in the front-end plan that §4.2 does not amend.

## 4. Work packages

Each package runs in its own locked worktree (`git worktree lock --reason`), commits with
Guardian's checks, and records evidence under `experiments/vk-<package>-<date>/`, one log per
command. **Owns** lists the files a package may change; a change needed elsewhere goes
through the coordinator.

### 4.1 Early packages

#### VP1. Table-fit census (now; about 3–5 h; no compiler change)

**What.** For each corpus, list every graph-shaped structure:
- index-based graphs: `int` fields pointing into lists;
- dicts used as entity stores (`dict[int, T]` with a counter);
- `pool` uses;
- `class` uses in tests.

Classify each edge into one of three:
1. **owning:** it fits folder ownership;
2. **weak cross-reference:** a stored key;
3. **genuinely shared:** several owners, or cycles that need reachability to clean up.

**Exit:**
- a table per corpus;
- every "genuinely shared" structure, with file:line and why;
- a recommendation on VK6 (`prune`) and on mixed-type trees (union tables or not).

#### VP2. Trap-search prototype (now; about 4–6 h; no compiler change)

**What:**
1. In scratch copies of the corpora, generate, for every searchable public function
   `f(a: A, b: B) -> R`, a property test `test_trap_f(a: A, b: B) -> bool` that carries
   `f`'s `@requires`, calls `f`, and returns `True`.
2. Run `mylang test` over them with the existing generator, using the S5 pin: a
   ReleaseFast `mylang` built from `main` at `5a6b501d`, shared with the front-end plan's
   coordinator. (The earlier S4 Wave 0 pin, `a16a324e`, is superseded.) A Python script
   under `experiments/` is fine; it is never needed to build or use mylang.

**Exit, per corpus:**
- functions searched, failed and not searched (with reasons);
- failures by trap code, with the five smallest inputs per code;
- the number of trap sites per kind, from `dump-typed` or FB1 when available.

This sizes T1-R: how much the gate would ask of existing code.

#### VP3. Run-time cost counters (after FB1's report; about 4–6 h)

VP3 starts from FB1's final state (`codex/frontend-cost-cli`). Running the two side by
side would have both packages editing the core's stats code at the same time. FB1 counts
sites per function from the program text; VP3 counts what actually happens at run time.

**Retargeted 2026-10-08.** The question VP3 was written for, whether static ownership is
worth prototyping, is mostly answered by profiles of the 2026-10-08 benchmark binaries
(`experiments/bench-newcore-20261008/`, with perf on non-timing CPUs):

| Program | Copying records and buffers | Count updates |
|---|---|---|
| Lox VM, fib (28× Zig) | ~58% of samples: 32-byte vector moves of records in `vm::run` (16.9 KB frame, 1,454 vector moves) | ~5% |
| Lox tree, properties (6× Zig) | ~35% in the hottest functions | ~4% |
| EDA, rds3+flat (3.3× Zig) | ~44% in the runtime: freeing blocks 17%, glibc `memmove` 15% (6 points from `realloc` in list growth in `kicad_sch_textbox::scan`), dict copy plus its child walk ~14%, allocation 3% | ~2–3% |

So VP3's main job is now the **copy-elimination target list.** Static ownership becomes a
side verdict.

**What.** Runtime counters in a counting build, off by default:
- **Count operations:** retains and releases executed.
- **Uniqueness tests:** executed, with their unique and shared outcomes.
- **Copies:** executed, by kind (list, dict, text and bytes, record or aggregate), with
  bytes copied.
- **Memory:** allocations and frees, with bytes; list and buffer growth (realloc) events
  and bytes moved; peak live bytes.
- **Attribution:** each count goes to its emitting function, and to its source span where
  the core knows it.

With the counters off, the emitted LLVM text and the executables are byte-identical to
FB1's, as FB1 guaranteed for its own stats.

**Owns:** the counters in `src/core/runtime/` and the core's emission of them, their stats
plumbing, the dynamic columns added to FB1's `cost` report, and
`experiments/vk-vp3-<date>/`. It changes FB1's static counts only through the coordinator.

**Programs:**
- Lox, tree and VM engines, on the ten timed scripts at reduced sizes, plus
  `instantiation` and `binary_trees` at small sizes;
- the EDA slice, on all 34 designs, with the six slowest reported separately;
- the parity programs `nbody` and `str_build`, plus `matmul` and `knucleotide`;
- totals over the 46 rows.

**Exit:**
- **Per program:** totals, and bytes copied per unit of work.
- **The top 20 functions by bytes copied,** each with its sites (source span, copy kind)
  and the pattern behind it. The known candidates to confirm or reject:
  - a whole record written back into a list element while the local stays live (the Lox
    VM frame);
  - an element-field store lowered as a whole-record copy (nbody);
  - copy-on-write of a whole list when only one element is held across a `mut` call (Lox
    `instantiation`);
  - a materialized slice in a `for` loop, or an accessor returning a payload copy (EDA
    `as_list`, `cl[1:len(cl)]`);
  - dict copies;
  - list growth through `realloc`;
  - out-of-line checked appends (str_build).
- **The ranked copy-elimination target list,** with each pattern's share of bytes copied
  across the programs. This is the input to a copy-elimination package that replaces the
  O wave.
- **The static-ownership verdict.**
  - Count operations removed, against the extra copies static ownership would make at
    each point where RC shares (shares are retains on still-live values).
  - Run O1 only if the estimated net saving is at least 3% of instructions on the rows'
    geomean, or at least 10% on five rows, Lox or EDA.

### 4.2 Amendments to the front-end plan (applied 2026-10-07, `befaf67e` on `claude/frontend-plan`)

| Amendment | Package it changes | Change |
|---|---|---|
| **AM1 (VK7)** | F1-S | Drop A6. Contracts and invariants stay; F1-S no longer owns contract checking. The proposal's §3.1 row A6 and §4 are marked reversed, citing this plan. |
| **AM2 (VK8)** | F1-E and F2-C2 | **F1-E:** the `noalloc` clause becomes `@noalloc`, with a fix. **F2-C2:** besides the call-graph passes, delete the per-body effect check, the inferred effect sets, callback-type ceilings and `E_DERIVED_EFFECTS`; keep `E_UNUSED_CAPABILITY`. Contract purity becomes a local rule: a contract condition passes no capability and no `mut` argument. P4 also runs with effect checking removed and lists every changed verdict. **F2-C2 adds the core's build-time `@noalloc` check** (§3.7). **B6** in FB1 keeps one definition of "allocates", shared with that check. |
| **AM3 (VK9)** | F1, as its own package F1-D | Add row A16 (§3.7). F1-D (about 4–6 h) starts in the first free slot after F1's four parallel packages, to hold the four-agent limit. |

### 4.3 T wave: trap search and coverage (from the front-end F1 exit; in parallel with F2–F4)

#### T1. Trap search (about 8–12 h)

**What.** §3.5 without hints or failure injection:
- `trap::` entries;
- discards, shrinking, the report and caching;
- the `mylang.json` setting;
- lint gate integration.

**Owns:**
- the new core's test runner, `src/core/test_runner*.zig`;
- its generator, `src/core/property_*.zig`;
- the project-config reader for the two new keys;
- `docs/tooling/guest-tests.md`.

The old back end's runner (`src/native_test_*.zig`) is gone after S5.

**Tests:**
- every outcome in §3.5, as runner tests;
- determinism: two runs, identical results;
- an unchanged function is not re-run;
- a `@requires` violation by a callee fails; one by the searched function's own input is
  discarded.

**Exit:** §6's gates, and the test-time budget in §6.

#### T1-R. Report-mode run over the corpora, then stop (about 2–3 h)

Run T1 in report mode over `tests/lang`, `src/stdlib`, Lox and EDA.

**Stop** with:
- per-corpus counts;
- the failures grouped by fix kind: add `@requires`, return `Option`/`Result`, or a real
  bug.

The user decides:
- whether the corpora get fixed in a follow-up package (T1-M);
- when the defaults become `"gate"`.

#### T2. Trap coverage (about 6–10 h; after T1)

**What:** §3.6.

**Owns:**
- the trap-site table and counters where the core emits checks (no `ir.zig` change);
- the runner's aggregation and report;
- the waiver comment.

Coordinate with F3-C1, which moves desugaring into the core.

**Tests:**
- a site of every kind is counted when reached and reported when not;
- a waiver is listed;
- FB1-proved sites count as covered.

#### T3. Hints and failure injection (about 7–10 h; after T2)

**What:** §3.5's T3 items. The dropped-`Err` mark exists only in test builds. `@noalloc`
is not here: the front-end plan's F2-C2 checks it at build time.

**Owns:** the generator (`src/core/property_generate.zig`), the stand-ins' failure
schedule, and the test-build `Result` mark in the core.

**Tests:** every hint kind finds its seeded bug in a fixture, every stand-in fails on
schedule, and a dropped `Err` is reported.

#### T4. Table and key generators (about 3–5 h; after V1)

Tables with random entries and owner structure, and keys that are present, removed, or from
another table, respecting `@requires(k in t)`.

### 4.4 V wave: tables and the smaller items (after F4; `ir.zig` is unfrozen)

#### V1. Tables and keys (about 16–24 h)

**What:**
- §3.2 end to end: the types in the catalog, subscript and place paths, the operations,
  the runtime (slots, serials, owner links, removal sites in debug and test builds), the
  traps and the `R_OWNER_CYCLE` code;
- `d.get(k)` returning `Option`;
- the `pool` removal;
- VK10's renames.

**Owns:** the table type and operations in sema and the core, the runtime table
implementation, `src/stdlib/pool.my` (deleted), `docs/` for tables, dicts and enum arrays.

**Tests:** `tests/lang/tables.my` covers every row of §3.2's table, including:
- loop skipping;
- copy semantics;
- cascade;
- `move` cycles;
- a stale key, a key from another table and a reused slot;
- the trap message in debug and release builds.

**Exit:**
- §6's gates;
- a microbenchmark row comparing a table lookup with a list index, reported.

#### V2. Resources as keys (VK11; inventory, stop, then about 8–12 h)

**Inventory:** every resource kind and its ownership rules. Then **stop** for the user, then
implement §3.9.

#### V3. Small items (about 4–6 h)

- **`main` returning `Result[int, str]` and `Result[None, str]`** (§3.3).
- **Literal checks**, after inventorying what `E_CONSTANT_ARITHMETIC` already rejects:
  - `split("")` with a literal separator;
  - a literal zero divisor;
  - a literal index outside a literal list or string;
  - `pop()` on a literal empty list.
- **The lint `silent-default`** (agent profile, report level): a `case None:` or
  `case Err(...)` arm whose body only returns a literal or `pass`. Its message names `?`
  and `Err`. It sits beside `sentinel-int`.

#### V4. `prune` (only if VP1 recommends it; about 6–10 h)

§3.10, with tests for the generated walk, the root check's error, and Lox's environments as
the acceptance case.

### 4.5 CE wave: copy elimination (replaces the O wave, 2026-10-08)

**VP3 decided VK12: static ownership is not prototyped.** By the rule the O wave carried:
- the rows' geomean net saving is 0.47% (the threshold is 3%);
- EDA loses 15% and Lox about 5× in instructions, because RC's shares of large records
  would become copies.

The O wave is dropped, and one-count RC stays the memory model. VP3 also found what the
cost actually is: copying, at 2.4–7.5 bytes per instruction retired, not counting. The CE
wave removes it.

**Who and where.** Claude agents run the wave at the user's request (2026-10-08):
- two lanes, each branched from `claude/copy-elim` (VP3's tip plus this plan change);
- the coordinator integrates and gates them.

Both lanes change `src/core/` only, never a front-end file, so they never touch the
front-end waves' files.

**Measurement.** VP3's counters (`--counters`, `mylang cost --counters`) and its tools in
`experiments/vk-vp3-20261008/tools/`, run on VP3's programs at VP3's sizes. Each lane
reports bytes moved per pattern, before (VP3's numbers) and after.

#### CE-A. Records in the emitter (about 12–20 h)

**Targets.** P1, P8, P2 and P7: 54% of bytes moved, 85% of Lox's and 88% of EDA's (VP3
report).

**What**, in this order, running the counters after each step:
1. **P1, phi fills.** Coalesce memory-phi slots with incoming slots that die on the edge,
   and give loop-carried memory records one home slot (`analyzeMemory`,
   `fillMemoryPhis`).
2. **P8, copies out of a containing record.** Read fields of memory records through a
   pointer projection when the source outlives the use (`record_get`, `union_payload`, the
   field loads in `countedMemory`).
3. **P2, whole-record copies before a field store.** Update a memory record in place when
   its old version has no later reader. This extends `writableInPlace` from "made in this
   block" to liveness, including `mut` parameters and phis.
4. **P7, `sret` returns and `mut` copy-in/copy-out.** Pass `mut` records larger than four
   words by reference, and build returned records in the caller's destination.

**Owns:** the memory-record paths of `src/core/emit_llvm.zig` (`analyzeMemory`,
`fillMemoryPhis`, `countedMemory`, `writableInPlace`, record and union operations, calls,
returns and parameter passing), and any liveness helper they need.

**Exit:**
- P1+P2+P7+P8 bytes moved down by at least 50% on Lox and on EDA, with actuals per pattern;
- no other pattern up;
- the CE gates below.

#### CE-B. Lists, copy-on-write, slices and appends (about 10–16 h)

**Targets:**
- P3/P4/P5, whole-element list access: all of nbody, and the Lox VM frame;
- P9, whole-list copy-on-write: Lox `instantiation`, which is quadratic;
- the `for` loop over a slice: EDA `overlaps_of`, 38% of rds3+flat's bytes;
- `str_build`'s out-of-line appends.

**What:**
1. **Field-level element access.**
   - `xs[i].f` reads lower to `list_get_field`.
   - `xs[i].f = v` stores the field in place after the uniqueness test.
   - `xs[i] = v` releases the old element's fields in place and stores from `v`'s slot.
2. **Copy-on-write narrowing in `own.zig`.**
   - Promote only the element read, not the list read.
   - End a write-back temporary (`__wb_N = it.rt … it.rt = __wb_N`) before the element
     store, so the store finds the list unique.
3. **Slices used only as a loop source.** Iterate the source list by index instead of
   materializing the slice, and give a materialized slice its exact capacity. This is a
   Core IR rewrite, not a front-end change.
4. **Buffer appends.** An inline fast path for `append_range`, with the checked call as the
   slow path.

**Owns:**
- `src/core/own.zig`;
- the Core IR rewrites for element access and slice loops;
- the list operations' emitters in `emit_llvm.zig`: `list_get`, `list_set`,
  `list_get_field`, `list_push`, and any new element-field store;
- the runtime's buffer append.

**Exit:**
- nbody P3+P4 bytes down at least 90%;
- Lox `instantiation` linear in N on both engines, with P9 bytes down at least 90%;
- EDA `overlaps_of` bytes down at least 90%;
- no out-of-line append calls left in `str_build`'s hot loop;
- the CE gates below.

**A shared file.** Both lanes edit `emit_llvm.zig`, in different functions. A lane that has
to change a function the other lane owns makes the smallest change it can and says so in
its report. The coordinator resolves it at the merge.

#### CE-X. Integration and measurement (coordinator; about 3–5 h)

- **Merges:** CE-B, then CE-A, into `claude/copy-elim`, qualifying after each.
- **Counters** on all of VP3's programs: bytes moved per pattern, before and after.
- **Wall time**, interleaved, on CPU 10 under its lock, medians of three runs, against the
  VP3 base (`65a14aeb`) built the same way:
  - Lox, both engines;
  - EDA, all 34 designs;
  - the 27 parity programs;
  - the 46 rows.
- **Exit:**
  - every CE gate;
  - no row slower than 1.03× the base beyond noise;
  - a report with the before/after tables.

#### CE gates

A wrong answer is never acceptable. Every lane and every merge passes:
- `zig build` (Guardian), `zig build test --summary all` and `zig build fmt-check`;
- conformance against the frozen S5 references in debug and release, with leak and fact
  verification: 1518/0/0 (`experiments/new-core-s5-20261007/tools/`);
- the frozen fuzz matrix, 9×50 per lane and per merge, and 9×200 at CE-X;
- Lox conformance 974/974 and its tests; EDA 34/34 goldens and 310 tests; parity output
  equal to `.expected`;
- the same output with counting on and off.

#### CE2. Second wave: field effects, and results and arguments in place (2026-10-08)

**The CE wave is done.** It was merged into `main` at `3e210ffba` (report:
`experiments/ce-x-20261008/REPORT.md`). Measured against the pre-wave compiler:
- copies: Lox −96%, EDA −91.5%, parity −99.8%;
- wall time: Lox VM ×0.229, tree-walker ×0.279, EDA ×0.784, parity ×0.910; the rows are
  unchanged.

**What is left.** Lox still copies 51.3 GB, and its VM is 6.6× Zig. EDA copies 3.47 GB.
Two shapes account for most of it:
- **Element round trips through a local.**
  - `frame = rt.frames[k]` … `rt.frames[k] = frame` stores the 88-byte frame back at
    `vm.my:433` and again at `vm.my:534`: two stores per instruction, 22.2 GB, which is 43% of
    Lox.
  - `heap::sweep` copies elements out to read them: 3.0 GB.
- **Calls that pass a record `mut` and also return a value.**
  - `read_byte(mut frame)` writes only `frame.ip`, but the whole frame is copied first while a
    view of `frame.function` is live, because interference is tracked per value.
  - The declared result is then copied into `%ret`.
  - Together these are P2 and P7: about 11 GB of Lox and 1.7 GB of EDA.

**Who and where.** As in CE:
- two Claude lanes, branched from `claude/copy-elim-2` (`main` after the CE merge, plus this
  section);
- `src/core/` only;
- the coordinator integrates the lanes, gates them and times the result (CE2-X).

The counts are compared with CE-X's final numbers (`experiments/ce-x-20261008/raw/final`,
`tools/ce.py`, `tools/tables.py`).

**CE2-A. Field effects (about 10–16 h).** Branch `claude/ce2-effects`.
1. **Field-level effect summaries.** For each function and each `mut` parameter, record the
   field paths it may write and may read.
   - They are transitive over the call graph.
   - They are conservative for indirect, `extern` and runtime calls.
   - They live in a new module in `src/core/`.
2. **Per-field interference** in `emit_homes.zig`. An in-place update of one field may go
   ahead while a view of a disjoint field is live, including across a call whose summary
   writes only other fields (`read_byte` writes only `frame.ip`).
3. **Dead and sunk element stores.** An element store whose value a later store to the same
   element overwrites, with no read of that element in between, is removed or moved to the
   exits that need it. A read counts whether it is direct or through a callee's summary.
   Target: `vm.my:534`, which the next iteration's `vm.my:433` overwrites.
4. **Narrowed element stores.** In `xs[k] = v`, `v` was loaded from `xs[k]` or last stored
   to it, and the summaries show only some of its fields changed since. The store writes only
   those fields: no whole-record copy, and no count traffic for the unchanged parts.

- **Targets:**
  - P4 at `vm.my:433` and `:534`: 22.2 GB;
  - P4 in `vm::call`, `heap::allocate` and `heap::set_env_slot`: 2.9 GB;
  - P2 at `vm.my:254`, `interpreter.my:667` and `heap.my:106`: 7.7 GB.
- **Owns:**
  - the summary module;
  - interference in `emit_homes.zig`;
  - element-store emission: `list_set`, `list_set_field`, and `own.zig`'s store rules.
- **Exit:**
  - the two `vm.my` store sites at 2 GB or less together;
  - the named P2 sites down at least 90%;
  - Lox P2+P4 down at least 70%;
  - no other pattern up;
  - the CE gates.

**CE2-B. Results and arguments in place (about 10–16 h).** Branch `claude/ce2-results`.
1. **Declared results next to `mut` values are built in `%ret`**, by giving them homes inside
   the result record. Examples: `return Ok(token)`, and
   `return frame.function.code.constants[i]`.
2. **Read-only by-value arguments are read where they lie.** A list element or record field
   passed by value to a callee that never writes that parameter is passed by address,
   provided no `mut` argument of the same call can reach it. Examples:
   `object.cost(rt.objects[i])`, `is_free(rt.objects[i])`.
3. **`sret` sharing for a by-value argument that dies at the call:** `s = advance(s, x)` (the
   rows' `record_pass`).
4. **A record pushed onto a list is built in its new slot** (P6, EDA `parse_list`).
5. **`table::set`'s list copy** (P9, `table.my:84`): find what shares the list, and remove the
   copy when it is not needed.
6. **Container operations on an element's field happen in place**, for example
   `xs[i].items.append(v)`, by extending `list_set_field`.

- **Targets:**
  - P7 at `vm.my:264`, `vm.my:268` and `interpreter.my:668`: 5.3 GB;
  - EDA's `sexpr_*` P7: 1.7 GB;
  - `heap::sweep` P3: 3.0 GB;
  - the rows' P1: 363 MB;
  - EDA P6: 0.44 GB;
  - Lox P9 at `table.my:84`: 1.85 GB.
- **Owns:**
  - call, return and parameter lowering in `emit_llvm.zig`, including the in-out ABI and
    `sret`;
  - `list_push` emission;
  - `own.zig`'s copy-on-write decision for the `table::set` case. Element stores belong to
    CE2-A.
- **Exit:**
  - the named P7 sites, `heap::sweep` P3, the rows' P1 and EDA P6 each down at least 90%;
  - EDA total copies at 1.5 GB or less;
  - no other pattern up;
  - the CE gates.

**Shared files.** Both lanes edit `emit_llvm.zig` and `own.zig`, in different functions. A
lane that has to change the other's function makes the smallest change it can and lists it
in its report.

**CE2-X. Integration and measurement (coordinator).**
- **Work:** as CE-X. Merge both lanes into `claude/copy-elim-2`, run the CE gates with fuzz
  9×200, and count against CE-X's final.
- **Wall time** on CPU 10 against the CE-X compiler (`3e210ffba`'s generated code):
  - Lox, both engines, including the six formerly infeasible cells;
  - EDA;
  - parity;
  - the rows.
- **Exit:**
  - every CE gate;
  - no row slower than 1.03× beyond noise.

### 4.6 C1. Trap containment design note (about 2–3 h; with D9 stage 5 planning)

**Semantics.** `isolate(f, args...)` returns `Result[T, Trap]`. `f` takes values, not `mut`
arguments, so a trap leaves the caller's data untouched. The result moves to the caller.
The same mechanism serves tasks.

**Options:**
1. a per-call heap, which static ownership makes natural;
2. a child process, with the result sent back as typed JSON, which restricts result types.

**Exit:** the note with a recommendation, and no code.

## 5. Order and expected time

| Wave | Packages | Starts after | Expected wall time |
|---|---|---|---|
| Early | VP1, VP2 | now | 3–5 h; 4–6 h |
| Early, core | VP3 | FB1's report (front-end wave 1) | 3–5 h |
| Amendments | AM1–AM3, applied to the front-end plan's F1 and F2 on 2026-10-07 | — | counted in the front-end plan: F1 17–24 h, F2 13–18 h |
| T | T1, then T1-R (stop), then T2 and T3; T4 after V1 | the front-end F1 exit and the user's go | 26–40 h |
| V | V1, then V2 (inventory and stop), V3, and V4 if needed; T4 | F4's exit and the user's go | 28–42 h, plus 6–10 h for V4 if VP1 calls for it |
| CE | CE-A and CE-B in parallel, then CE-X | VP3 (done 2026-10-08) and the user's go (given) | 25–41 h (done 2026-10-08) |
| CE2 | CE2-A and CE2-B in parallel, then CE2-X | CE merged into `main` (done) and the user's go (given) | 22–36 h |
| C | C1 | concurrency planning | 2–3 h |

The T wave runs beside F2–F4 because it owns different files (the runner, the generator,
the core's check emission). The coordinator merges T2 and F3-C1 one at a time. It starts
at the F1 exit, not with F1: wave 1 has no free build-heavy slot, and F1 migrates the
corpora T1-R reports on (launch instructions).

**The T wave is not free.** It shares the front-end waves' limit of four build-heavy
agents, and front-end packages take free slots first. F1 alone fills all four, so T mostly
runs in F2–F4's spare slots and stretches those waves. Plan for T to finish after F4,
not alongside F1.

## 6. Gates

**For every package:**
- the front-end plan's §5 gates where they apply: the full gate, the differential against
  the S5 oracle, the corpora, check timing and rebuild time.

**Trap search and coverage (T wave):**
- **Deterministic:** two runs give identical results and reports.
- **Test-time budget,** measured on CPU 10 under the front-end plan's machine rules:
  - `mylang test tests/lang` with every result cached is at most 5% slower;
  - after a one-function edit, only the affected `trap::` entries re-run;
  - the cold full run is reported. If it is more than 30% slower, stop and report before
    turning the gate on.
- **The harness never fails on its own.** A trap inside the generated harness is a runner
  bug, not a function failure, and the report says which.

**Tables (V1):**
- every §3.2 row tested;
- a key never matches after removal, even after slot reuse (a stress test);
- the table lookup microbenchmark reported.

**Static ownership (O wave):** O2's rule. A wrong answer stops the wave.

## 7. Rules

- **A wrong answer is never acceptable.** A mismatch is reduced to a regression fixture
  before it is fixed.
- **Stop for the user** after:
  - VP1 and VP2;
  - VP3;
  - T1-R;
  - V2's inventory;
  - O1, for O2.
- **No pushes,** and nothing merged into `main` unless the user says so.
- **External corpora** (Lox, EDA) are changed only on new branches.
- **Machine rules:** the same as the front-end plan's §6:
  - builds through `scripts/build-slot.sh`;
  - timing only on CPU 10;
  - at most four build-heavy agents **across this plan and the front-end plan together**;
  - never the full gate while a fuzz matrix runs.
- **The slow-step rule** (the front-end plan's §6.1, the user, 2026-10-08):
  - every command is timed;
  - anything over about 5 minutes uncontended gets a speed investigation, and the
    speedup is implemented when it keeps the check identical;
  - nothing is sped up by weakening it;
  - entries go in the front-end plan's ledger. For the T wave's test-time work this
    comes on top of §6's test-time budget, not instead of it.
- **Out-of-scope bugs** get a regression fixture and a report.

**Repository rules** (from `CLAUDE.md`, `guardian.toml` and the documentation gate):
- **A spec tag for every behavioural line,** with a test carrying `// spec: TAG` and a
  `SPEC.md` bullet. Extra tests for the same bullet use `// spec-case:`.
- **A `src/features.json` entry** (`{kind, summary, doc}`) whose doc anchor has a runnable
  example. A removed construct moves to `removed`, gets `E_<NAME>_REMOVED` naming the
  replacement, a `fix` edit where the rewrite is mechanical, a `# doc: expect-error`
  example, and an entry in the removed-spellings table (F1-0).
- **Where tests go.** Guest-visible behaviour is tested in `tests/lang/<area>.my`.
  Diagnostics, traps and runner behaviour are tested in `src/root_test.zig` or
  `test/integration.zig`.
- **Guardian limits:** at most 7 struct fields and 6 parameters; `///` on every `pub`
  declaration; no import cycles; the type-size ratchet.
- **Every rejection carries its fix,** with the replacement in the message.
- **Interface surfaces agree.** `list-interfaces`, `context`, `api-diff` and the interface
  fingerprint render new signature elements: table and key types, `@noalloc`.

## 8. Reports

**Every package's report has:**
- its commits;
- the gate receipts;
- line deltas per file group;
- every remaining limit.

**Package-specific additions:**
- **VP1:** the classification tables.
- **VP2 and T1-R:** the trap-search counts.
- **VP3 and O1:** the ownership tables.
- **T wave:** test-time numbers against the budget.

## 9. Evidence

Counts are from `main` at `df55c52d7` (2026-10-07), with `git grep` over `*.my` and
`src/*.zig`:
- **205 distinct `E_*` codes** in `src/*.zig`.
- **The `R_*` trap codes, grouped:**
  - bounds: `R_LIST_BOUNDS`, `R_INDEX_BOUNDS`, `R_TEXT_BOUNDS`, `R_SLICE_BOUNDS`,
    `R_BYTE_RANGE`, `R_BUFFER_BOUNDS`;
  - missing things: `R_MISSING_KEY`, `R_LIST_VALUE`, `R_SUBSTRING_NOT_FOUND`;
  - arithmetic: `R_OVERFLOW`, `R_DIVISION_BY_ZERO`, `R_INVALID_SHIFT`,
    `R_NEGATIVE_EXPONENT`;
  - conversions: `R_FLOAT_CONVERSION`, `R_TEXT_SCALAR`, `R_EMPTY_SEPARATOR`;
  - checks: `R_ASSERT`, `R_REQUIRES`, `R_ENSURES`, `R_INVARIANT`;
  - iteration: `R_LIST_ITERATION_MUTATION`;
  - old memory model: `R_ARENA_ESCAPE`, `R_COW_DEPTH`, `R_REFERENCE_COUNT_LIMIT`,
    `R_REGION_LIMIT`;
  - I/O: `R_FILE`, `R_OUTPUT`, `R_HOST_FAILURE`, `R_CAPABILITY`, `R_ENVIRONMENT`;
  - machine limits: `R_MEMORY_BUDGET`, `R_FRAME_LIMIT`, `R_STEP_LIMIT`, `R_TIMEOUT`,
    `R_HOST_LIMIT`;
  - compiler bugs: `R_INTERNAL`.
- **Line counts:** `src/effects.zig` 1,278 lines; `src/origins.zig` 1,423 lines.
- **Uses in `.my` files:**

  | Construct | Uses | Files |
  |---|---:|---:|
  | `domain` declarations | 16 | 12 |
  | `constraint` declarations | 14 | 8 |
  | `noalloc` (2 stdlib and 9 `tests/lang` files; the rest in `experiments/`) | 124 | 115 |
  | `effects(...)` | 535 | 172 |
  | `with arena()` | 346 | 194 |
  | `@requires` | 7 | 3 |
  | `@ensures` | 14 | 5 |
  | `@invariant` | 3 | 2 |
  | `pool` | — | 3 |

**Earlier measurements this plan relies on:**
- **P2 (2026-09-24).** 6 of 7 agent incidents were conservative `E_MUTATION_OVERLAP`
  rejections. This is why the plan prefers local rules to inferred ones.
- **P3 (2026-09-24).** Copying instead of sharing (the borrow arm) cost 1.11× (QBE) and
  1.21× (LLVM) against the GC. That is the risk O2 guards against.
- **P1 (2026-09-24).** Of 525 transfers, 34% were moves, 35% copies that are never written,
  and 24% real copies.
- **RC on main.** About 1.07× the GC's instructions, with a 32-byte header (the common
  16-byte header plus two 64-bit counts, ABI 5).
- **The front-end proposal's §3.2.** Over 33 rows, 242 updates were proven in place, 11
  tested at run time, and 11 copied.
- **The 2026-10-04 integer_math ladder** (runtime-levers assessment). One proven range fact
  took the kernel from about 1.9× Rust's time to about 0.5× on baseline x86-64. This is why
  facts belong in the optimizer.

## 10. Risks

- **Trap search may flag many functions that rely on unstated assumptions.**
  - VP2 measures this before any gate.
  - The fixes are local (`@requires`, `Option`, a bug fix), and T1-R stops for the user.
- **Test time grows.** Caching by reached code and the §6 budget bound it. Raise
  `--trap-runs` only in CI.
- **AM1 and AM2 reverse rows the user accepted on 2026-10-06.** The user confirmed both on
  2026-10-07, with `@noalloc` moved to a build-time check.
- **Deleting the effect check rests on "authority only through parameters".**
  - The P4 run in F2-C2 verifies it.
  - `Host` and `extern def` bodies are trusted either way, as today.
- **Static ownership may lose to one-count RC on copy-heavy code.** O2's rule decides, and
  the fallback keeps RC.
- **Folder ownership is one tree per table.** Mixed-type trees need a union element type;
  VP1 checks whether that fits EDA's parts and pins.
- **Removing domains loses constructor-only encapsulation.** `@invariant` checks every
  construction instead. A value can be built anywhere, but an invalid one traps where it is
  built.
