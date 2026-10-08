# Values and keys, trap search, and test-backed simplifications: plan, 2026-10-07

Status: **designed with the user in conversation on 2026-10-07. VK7–VK10 confirmed the
same day, with one change to VK8: `@noalloc` is checked by the new core at build time, not
by trap search.** AM1–AM3 are applied to the front-end plan (`befaf67e` on
`claude/frontend-plan`). §2 lists what is accepted and what waits for data. Nothing here is
implemented. Read-only packages can start now. Every language change waits for the
front-end waves that own the same files.

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
  - Its waves F0–F5 start at the S5 exit.
  - **This plan amends it in three places (§4.2).** The user confirmed all three on
    2026-10-07, and they are applied there.
- **Local-reasoning item 2** (effect ceilings derived from the signature) is merged into
  `main`; `local-reasoning/integration`'s last commit is from 2026-09-22. AM2 deletes the
  effect checking it refined (§3.7).

## Launch instructions (for Codex)

**Now, read-only.** These need no compiler change:

> Run packages VP1 and VP2 of `docs/audits/values-keys-trap-search-plan-2026-10-07.md`
> (branch `claude/values-keys-plan`), each on its own new branch (`codex/vk-vp1`,
> `codex/vk-vp2`) from `claude/values-keys-plan`. Change no compiler file. Hold S4's
> machine rules: at most one build-heavy process, and never time anything. Finish each with
> its report and stop.

**After FB1's report (the S4 exit; alongside S5).** VP3 follows FB1 rather than running
beside it, because both add to the core's stats code:

> Implement package VP3 of the values-and-keys plan on `codex/vk-vp3`, created from
> `codex/frontend-fb1` after FB1's report. Merge `claude/values-keys-plan` into it first.
> Touch only `src/core/`. Never merge into `main` and never push. Finish with VP3's report
> and stop.

**The front-end amendments** (§4.2, AM1–AM3) are already applied to the front-end plan.

**At the S5 exit, after the user's go:**

> Implement the T wave of the values-and-keys plan on `codex/vk-trap-search`, created from
> the S5 exit commit, merging `claude/values-keys-plan` first. It runs in parallel with the
> front-end waves, owns only the files listed per package, and shares their limit of four
> build-heavy agents: front-end packages take free slots first. Stop after T1-R with its
> report.

**After F4, after the user's go:** the V wave, on `codex/vk-tables`.

**After S5, VP3's data and the user's go:** O1, on `codex/vk-static-ownership`.

## 1. Where it starts

- **Repository facts** are from `main` at `df55c52d7` unless a branch is named.
  **File ownership** for packages that run after S5 names the new core's files at the S3
  exit (`82c125dd`), because S5 deletes the old back end and its test runner.
- **The same freeze as the front-end plan (its §1).** Until S5 the front end is shared by
  both cores, and the old core is S4's differential oracle, so no front-end code changes
  before S5. Packages that run earlier touch nothing, or only `src/core/`.
- **Corpora**, the same as the front-end plan's:
  - the EDA slice: `eda-bench` `codex/s4-eda-stage1` `510c2e2`;
  - the Lox port: `codex/s4-lox-value-semantics` `f44302d8`;
  - `src/stdlib`;
  - `tests/lang`;
  - for performance, the 46 rows used by FB1.
- **The oracle after S5** is the pinned S5-exit compiler. It is built once, as the front-end
  plan's §1 describes.
- **Existing machinery this plan builds on:**
  - **Property tests** (`docs/tooling/guest-tests.md` "Property tests").
    - **After S5 they run in the new core's runner,** which has had its own since S3:
      `src/core/test_runner_property.zig` and `src/core/property_*.zig` (generation,
      shrinking, types, execution, rendering).
    - **On `main`** the runner is the old back end's: `src/native_test_property.zig` and
      `src/property_*.zig`, which import `qbe_build_io.zig`. S5 deletes them.

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
  - **Structured trap records** (`structured-native-trap-detail`) and
    `mylang invoke --describe` / `--input=FILE`.
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
| **VK12** | Static ownership replaces one-count RC in the core | O1's numbers against the rule in §4.5, written before O1 runs |
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
2. Run `mylang test` over them with the existing generator, using the S4 Wave 0 pin: the
   ReleaseFast build of `claude/new-core-s4-design` at `a16a324e` that ported both
   corpora (the S5 pin does not exist yet). A Python script under `experiments/` is fine;
   it is never needed to build or use mylang.

**Exit, per corpus:**
- functions searched, failed and not searched (with reasons);
- failures by trap code, with the five smallest inputs per code;
- the number of trap sites per kind, from `dump-typed` or FB1 when available.

This sizes T1-R: how much the gate would ask of existing code.

#### VP3. Ownership cost counters (after FB1's report, alongside S5; about 3–5 h)

VP3 starts from `codex/frontend-fb1` once FB1 has reported. Running the two side by side
would have both packages editing the core's stats code at the same time. FB1 counts per
function from the program text; VP3 adds what happens at run time.

**What.** Runtime counters in stats builds, reported per function and per row:
- retains and releases executed;
- uniqueness tests executed, with the unique and shared outcomes;
- copies executed and bytes copied;
- allocations, and peak live bytes.

From these, estimate what static ownership would add: copies, and bytes copied, at every
point where RC shares instead of copying.

**Owns:** the runtime counters in `src/core/runtime/` and their stats plumbing, and the
dynamic columns VP3 adds to FB1's `cost` report. It changes FB1's static counts only
through the coordinator.

**Exit:**
- the table over the 46 rows, Lox and EDA;
- the estimate;
- a recommendation on whether O1 is worth running: run it if the estimated net saving is
  at least 3% of instructions on the rows' geomean, or at least 10% on five rows, Lox or
  EDA.

### 4.2 Amendments to the front-end plan (applied 2026-10-07, `befaf67e` on `claude/frontend-plan`)

| Amendment | Package it changes | Change |
|---|---|---|
| **AM1 (VK7)** | F1-S | Drop A6. Contracts and invariants stay; F1-S no longer owns contract checking. The proposal's §3.1 row A6 and §4 are marked reversed, citing this plan. |
| **AM2 (VK8)** | F1-E and F2-C2 | **F1-E:** the `noalloc` clause becomes `@noalloc`, with a fix. **F2-C2:** besides the call-graph passes, delete the per-body effect check, the inferred effect sets, callback-type ceilings and `E_DERIVED_EFFECTS`; keep `E_UNUSED_CAPABILITY`. Contract purity becomes a local rule: a contract condition passes no capability and no `mut` argument. P4 also runs with effect checking removed and lists every changed verdict. **F2-C2 adds the core's build-time `@noalloc` check** (§3.7). **B6** in FB1 keeps one definition of "allocates", shared with that check. |
| **AM3 (VK9)** | F1, as its own package F1-D | Add row A16 (§3.7). F1-D (about 4–6 h) starts in the first free slot after F1's four parallel packages, to hold the four-agent limit. |

### 4.3 T wave: trap search and coverage (after S5; in parallel with F1–F4)

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

### 4.5 O wave: static ownership, decided by data (after S5 and VP3)

#### O1. Prototype behind `--ownership=static` (about 20–30 h)

**What:**
- §3.8 in the core, behind a flag;
- the header layout is unchanged in the prototype; header bytes saved are computed from
  the allocation counts and reported separately;
- the differential fuzz against one-count RC.

**Owns:** `src/core/` ownership and emission, and the runtime's count operations under the
flag.

**Exit:** the comparison over the 46 rows, Lox and EDA:
- instructions, cycles and peak RSS;
- copies and bytes copied;
- check and build time.

#### O2. Decision (VK12). Written now; the user may edit it before O1 starts.

Adopt static ownership only if all of these hold:
1. no wrong answer in the differential fuzz or the corpora;
2. retired instructions, geomean over the 46 rows, at most 0.97× one-count RC;
3. no row above 1.10×;
4. median peak RSS at most RC's, with header savings counted;
5. Lox and EDA benchmark wall time at most 1.00× RC, and both test suites green;
6. check and build time within 5%.

If it fails, keep one-count RC, and keep any O1 analysis that elides RC operations.

#### O3. Adoption (only if O2 passes; about 15–25 h)

- static ownership becomes the default;
- the RC paths and the count word are deleted;
- `W_HIDDEN_COPY` reports copies only;
- VK15 is decided on its data;
- tables are supported in the static mode.

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
| Early, core | VP3 | FB1's report (after the S4 exit, alongside S5) | 3–5 h |
| Amendments | AM1–AM3, applied to the front-end plan's F1 and F2 on 2026-10-07 | — | counted in the front-end plan: F1 17–24 h, F2 13–18 h |
| T | T1, then T1-R (stop), then T2 and T3; T4 after V1 | the S5 exit and the user's go | 26–40 h |
| V | V1, then V2 (inventory and stop), V3, and V4 if needed; T4 | F4's exit and the user's go | 28–42 h, plus 6–10 h for V4 if VP1 calls for it |
| O | O1, then O2 (stop), then O3 if it passes | S5, VP3, and the user's go | 35–55 h |
| C | C1 | concurrency planning | 2–3 h |

The T wave runs beside F1–F4 because it owns different files (the runner, the generator, the
core's check emission). The coordinator merges T2 and F3-C1 one at a time.

**The T wave is not free.** It shares the front-end waves' limit of four build-heavy
agents, and front-end packages take free slots first. F1 alone fills all four, so T mostly
runs in F2–F4's spare slots and stretches those waves. Plan for T to finish after F4,
not alongside F1.

## 6. Gates

**For every package:**
- the front-end plan's §5 gates where they apply after S5: the full gate, the differential
  against the pinned S5 compiler, the corpora, check timing and rebuild time;
- before S5, the S4 rules.

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
