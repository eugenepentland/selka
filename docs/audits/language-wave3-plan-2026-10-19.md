# Language wave 3: `str` is bytes, slices are views (plan, 2026-10-19)

Status: accepted, 19 October 2026. The user accepted V1 to V8 as recommended (§11). Codex implements it, before the self-hosting run's lane P; the launch instruction is in §12. Written against `main`
at `c972e6cf7f`. Nothing in it is implemented. Source of the two proposals:
[surface simplification](../design/surface-simplification-2026-10-13.md),
proposals 16 and 17. The plan's structure follows
[language wave 1](language-wave1-10-agent-plan-2026-10-14.md).

## 1. Summary

Wave 3 makes the short spelling the cheap one for text and ranges:

- **`str` is bytes underneath.**
  - `len(s)` is the byte length.
  - `s[i]` is a byte, as an `int`.
  - `s[a:b]` slices by byte offset, and traps inside a multi-byte scalar.
  - Iterating a `str` directly is an error. The fix names `strings.chars(s)`
    or `strings.bytes(s)`.
  - f-string padding keeps counting scalars.
- **A slice is a view.** `xs[a:b]`, `s[a:b]` and `b[a:b]` are borrowed reads of
  their source:
  - never stored;
  - returned only under the one-parameter rule (§5.3);
  - `.copy()` makes an owned value;
  - `E_SLICE_ESCAPES` carries the `.copy()` fix.

**Much of the machinery exists.**
- Core already has a pointer-and-length `str_view`, with view operations,
  emission and a verifier rule that keeps views out of aggregates.
- The ownership checker already enforces the one-parameter rule for views:
  `returnSource` in `single_owner.zig`, `Signature.viewSource` in `ir.zig`.
- `str` and `bytes` share one runtime block.

**What is new:**
- list views;
- views across branches (`phi`);
- the byte meaning of `str` operations;
- the migration.

**The migration preserves every program's meaning.** It runs in two phases
(§4):
1. The old text operations are refused, and `mylang fix` rewrites them to
   explicit scalar helpers that compute today's results.
2. Once the corpus is migrated, the short spellings come back with their byte
   meaning.

A program never changes behaviour silently. Today's slices all copy, so every
`.copy()` the view rule inserts replaces a copy that already happens, and every
slice that needs none gets cheaper. The migration costs no runtime performance.

**The size,** outside `experiments/`, which wave 1 also exempted (census of
19 October):

| Construct | Sites |
| --- | --- |
| `len` of a `str` | about 510 |
| `str` index | about 210, nearly all used as a one-character `str` |
| `str` slices | about 290 |
| `bytes` slices | about 180 |
| list slices | about 50 |
| stepped slices | 33 (11 `str`, 22 list) |
| `for c in s` over a `str` | about 26 |
| a slice returned from a function | about 27 |
| a slice stored in a record, field, list or dictionary | about 29 |

The selka-projects code is already mostly bytes-based (markdown: 140 `bytes`
`len` calls against 10 `str`).

## 2. What changes for a program

| Today | After wave 3 | Migration (`mylang fix`) |
| --- | --- | --- |
| `len(s)` counts scalars | `len(s)` counts bytes | phase 1: `strings.char_count(s)` |
| `s[i]` is a one-scalar `str` at scalar position `i` | `s[i]` is the byte at offset `i`, an `int` | phase 1: `strings.char_at(s, i)` |
| `s[a:b]` copies scalars `a` to `b` | `s[a:b]` is a view of bytes `a` to `b`; it traps inside a scalar (`R_TEXT_BOUNDARY`) | phase 1: `strings.char_slice(s, a, b)` (owned, as today) |
| `s[a:b:c]`, `xs[a:b:c]` copy with a step | removed: a view is contiguous | `strings.char_stride(s, a, b, c)`, `lists.stride(xs, a, b, c)` |
| `for c in s` yields one-scalar `str`s | an error | `for c in strings.chars(s)` |
| `xs[a:b]`, `b[a:b]` copy | a view | none, unless the view escapes |
| a slice stored or returned | `E_SLICE_ESCAPES`, unless the one-parameter rule allows the return | `(xs[a:b]).copy()` |
| `s.borrow(a, b)`, `TextView`, `ByteView` | subsumed by slices | `s[a:b]` |

`bytes` indexing and slicing keep their byte meaning; only `bytes` slices become
views. Lists keep their element meaning; only list slices become views.

## 3. Where we start

From the compiler survey of 19 October, at `23c63cf50a`:

- **A `str` is a `myl_block`** (`core_rt.c:93-101`): a 32-byte header with a
  byte `len`, then the octets and a NUL. `bytes` shares the layout and differs
  only in its kind byte.
  - `str` carries text-only caches in its header: an ASCII flag, a cached
    scalar count, and a scalar-to-octet cursor (`MYL_TEXT_*`,
    `core_text.c:2-3,113-210`). These exist only to make scalar indexing
    cheap.
  - `str` is valid UTF-8 by construction. The check runs at each entry point:
    literals (`E_TEXT_UTF8`), decode, file reads, argv and the environment.
- **Text operations count scalars.**
  - `len` lowers to `myl_core_str_chars`.
  - `s[i]` lowers to `str_index_offset` plus `str_char` and returns a `str`.
  - `s[a:b]` lowers to `str_slice` and copies by scalar position.
  - Steps go through `str_slice_step`.
  - `for c in s` desugars to scalar indexing, and the `fuse_text` pass turns
    it back into byte offsets.
- **List slices** copy element by element: sema desugars `xs[a:b]` to an
  append loop (`collection_lower.zig:383-416`), and Core lowers a stepped slice
  to a copy loop.
- **Optimizations that recover views.** Slices that are only read are already
  recovered as views by special-case passes: loop-only list slices
  (`slices.zig`), read-only text slices (`fuse_slice_key.zig`), and the offsets
  kept by `split` (`split_views.zig`).
- **Core's views:**
  - `str_view` is `{ptr, i64}` (`ir.zig:52-53`, `emit_text.zig:29-37`), with
    `str_view_of`, `str_slice_view` and `str_from_view`.
  - `verify_ir.zig:66-78,446-463` forbids a view in an aggregate, in a function
    value and in a `phi`.
  - There is no list view.
- **The ownership checker** (`single_owner.zig`) tracks loans per local
  (`State`, `Loan{root, write, path}`) and invalidates views when their owner
  moves or changes (`E_ZERO_RC_VIEW_INVALIDATED`). Its `returnSource` and
  `origin(.call)` let a function return a view only when it has exactly one
  immutable view parameter, and it may then take no `mut` parameter. Core's
  `own.zig` links a view's lifetime to its parent.
- **`copy(x)` as a free function does not exist.** Wave 2's proposal 1 has not
  landed, so this plan spells the repair `.copy()`. Wave 2 renames it with the
  other built-in methods.

## 4. The two-phase migration

A one-step switch would change the meaning of some lines silently. For
example, `out.print(s[i])` would print a number, and `len(s)` on non-ASCII text
would give a larger value. No diagnostic would point at either. The plan
therefore separates refusal from the new meaning:

- **Phase 1, refuse and rewrite.** On a `str` receiver:
  - `len`, indexing, slicing, stepped slicing and direct iteration are
    rejected (`E_TEXT_SCALAR_FORM`, `E_TEXT_ITERATION`);
  - each diagnostic carries a certain fix to the explicit scalar helper of §2;
  - the helpers return exactly what the expression returns today;
  - `mylang fix` therefore moves any project across with no change in
    behaviour.
- **Corpus regeneration.** The coordinator regenerates the corpus with
  `mylang fix` and hand-edits only what the fix cannot reach (the exempt list
  in §6). Code whose data is known to be bytes-shaped (protocols, parsers, the
  selka-projects) is then converted by hand from the helpers to the byte
  forms, where that is faster and correct.
- **Phase 2, the byte meaning.** It lands when no unmigrated site remains,
  checked by an audit query in the gate. `len`, `s[i]` and `s[a:b]` on a `str`
  are accepted again with their byte meaning, and the phase 1 refusals are
  deleted.

Direct iteration stays an error in phase 2, as the proposal says.

Projects outside the tree migrate by running `mylang fix` against a phase 1
compiler. The release notes say so, and the phase 2 compiler's refusal of an
old `for c in s` names the helpers.

## 5. Design

### 5.1 Text as bytes

- **Representation.** The runtime block is unchanged.
  - `len(s)` reads the block length: one load, no call.
  - `s[i]` is a bounds-checked byte load, `R_TEXT_BOUNDS` as today.
  - `s[a:b]` is a view whose endpoints must be scalar boundaries. A
    continuation byte at either end traps `R_TEXT_BOUNDARY`, so a view of
    valid UTF-8 is valid UTF-8 and `str` keeps its guarantee.
- **Helpers in `strings`.** Each is new and documented with a runnable
  example, as `doc-coverage` requires:
  - `chars(s)`, a loop source yielding one-scalar views;
  - `bytes(s)`, yielding `int`s;
  - `char_count(s)`;
  - `char_at(s, i)`;
  - `char_slice(s, a, b)`, owned;
  - `char_stride(s, a, b, step)`.

  The scalar caches move behind these helpers. Whether they stay is a stage C
  measurement (§6): the ASCII flag probably does, because it makes every
  helper O(1) on ASCII text.
- **Comparison and hashing are already bytewise.** Byte order equals scalar
  order for UTF-8, so `<` and dictionary keys do not change.
- **f-string padding counts scalars**, as it already does.

### 5.2 Slices as views

- **A slice expression produces a view** of its source's type: `str`, `bytes`
  or `T[]`.
  - The static type stays `str`, `bytes` or `T[]`, so a view passes to any
    borrowed parameter of that type with no new spelling.
  - "View" is an ownership state of the binding, which the checker already has
    (`State.view_definition`), not a new surface type.
  - A view is immutable. Writing through it is the existing
    `E_TEXT_IMMUTABLE` for text and a new refusal for lists.
- **Core.**
  - A `list_view` leaf `{ptr, len}` with its element type joins `str_view`,
    with view-of, slice-of-view, index, `len` and iteration operations.
  - Emission and `verify_ir` follow `str_view`.
  - `bytes` slices use `str_view`, whose layout they share.
  - The special-case passes that recover views (`slices.zig`,
    `fuse_slice_key.zig`, `split_views.zig`) become redundant. Stage C deletes
    each one once the measurement shows no row regresses.
- **Escapes.** A view may not be stored in a record, a list, a dictionary or a
  module constant, captured into a function value, or outlive its source.
  - Each is `E_SLICE_ESCAPES` with the `.copy()` fix.
  - The census found about 29 stores and 5 self-overwrites
    (`state.input = state.input[used:]`). Each becomes a copy, which is what
    happens today.
- **Views across branches.** `verify_ir` today forbids a view in a `phi`. Wave
  3 allows one:
  - the result's parent set is the union of the incoming views' parents;
  - `own.zig` keeps every parent alive to the view's last use.

  Without this, `if p: rest = s[a:] else: rest = s[b:]` needs a copy.

### 5.3 The one-parameter return rule

**The rule.** A function may return a view when exactly one of its parameters
is borrowable: a managed value (`str`, `bytes`, a list, a dictionary, or a
record or union holding one) that is neither `mut` nor a capability.

- **The result borrows from that parameter.**
- **At a call site,** the argument's root stays alive and unmodified while
  the result lives. These are the existing loan rules, extended from views to
  any borrowable argument.
- **A function that returns a view takes no `mut` parameter,** as today.
- **A slice of a local, or of a temporary, cannot be returned:** the source
  dies at the return. Both are `E_SLICE_ESCAPES` with the `.copy()` fix. The
  census found about 27 returns: most of them have one borrowable parameter,
  a few slice a local, and one has two parameters.

This generalizes `returnSource` (`single_owner.zig:307-315`), `origin(.call)`
(`:419-426`) and `Signature.viewSource` (`ir.zig:514-527`) from "one view
parameter" to "one borrowable parameter". No annotation spelling is added. A
function with two borrowable parameters returns an owned value, and if the
user wants a choice later, a lifetime-style annotation can be added without
breaking this rule.

**Standard-library functions that fit the rule as they stand:**
- `path.basename` and `path.dirname`;
- `http.target`;
- `strings.lstrip`, `rstrip` and `strip`.

**Functions that need a copy where they store a slice:**
- `path.splitext`;
- `strings.lines`;
- `http.parse_request` and `parse_response`, and two private `http` helpers
  with two borrowable parameters.

### 5.4 What is removed

- **Phase 1:** the scalar meaning of `len`, indexing and slicing on `str`, and
  direct `str` iteration.
- **With views:** stepped slices of `str` and lists, and `.borrow(a, b)`
  together with `TextView` and `ByteView` (7 uses outside `experiments`). A
  view is contiguous, and `.borrow` is what a slice now is.
- **Stage C:** the slice-copy lowerings, the redundant view-recovery passes
  and the text cursor caches. Each goes only when its measurement holds.

## 6. Lanes

The structure is that of wave 1: one coordinator and workers, one feature per
worker.

| Lane | Owns | Deliverable |
| --- | --- | --- |
| **W0 coordinator** | `build.zig`, `SPEC.md`, `CLAUDE.md`, `src/features.json`, `test/fix_cli_test.zig`, cache format versions | integration in order; the generated corpus commits; the phase 2 audit query |
| **W1 text runtime** | `core_text.c`, `build_text*.zig`, `emit_text.zig` | byte `len`, index and boundary-checked view slices; `R_TEXT_BOUNDARY`; the helpers' runtime |
| **W2 text front end** | `sema_operators.zig`, `sema_loops.zig`, `sema_expressions.zig` and `collection_lower.zig`, claimed function by function | the phase 1 refusals with fixes (`E_TEXT_SCALAR_FORM`, `E_TEXT_ITERATION`); the phase 2 meaning; `FIX-MIGRATION` tests in `test/fix_wave3_text_test.zig` |
| **W3 standard library** | `src/stdlib/*.my`, `docs/text.md`, `docs/bytes.md` | the `strings` helpers, `lists.stride`; the stdlib migrated by hand, protocols to byte forms; docs and doctests |
| **W4 Core views** | `ir.zig`, `verify_ir.zig`, `own.zig`, `emit_*.zig`, `build_list*.zig` | `list_view`; views through `phi`; slice lowering to views |
| **W5 ownership** | `single_owner.zig`, `dictionary_views.zig` | `E_SLICE_ESCAPES` with fixes; the one-parameter rule generalized; stepped-slice and `.borrow` removal with fixes; `test/fix_wave3_views_test.zig` |
| **W6 corpus and projects** | the generated commits; `selfhost/components` (forms both compilers accept); selka-projects | `mylang fix` over every group; hand conversion of bytes-shaped code; `check.sh` for every project on the new pin |
| **W7 measurement and deletion** | `bench/`, `benchmarks/`, stage C deletions | the parity and runtime suites before and after; FR-108's 4,000-record walk; compile time; deleting what stage C allows |

**Order:**

| Stage | Lanes | Exit |
| --- | --- | --- |
| A, phase 1 | W1, W2 and W3, in parallel | the corpus regenerated and green |
| A, phase 2 | W1 and W2 | the audit query finds zero unmigrated sites |
| B | W4 and W5 | W5 can start on `str` and `bytes` views at once, because `str_view` exists; list views wait for W4 |
| C | W7 | after B |

W6 regenerates after each stage. `experiments/`, `docs/audits` and
`docs/design` are exempt from migration, as in wave 1. Conformance pins keep
their names.

## 7. Gates and done criteria

| # | Criterion |
| --- | --- |
| G1 | Every new refusal has a certain fix where §2 lists one, and a `FIX-MIGRATION-1`-style test proving `mylang fix` takes a pre-change file to a clean check |
| G2 | The whole corpus migrates with `mylang fix` (generated commits). Hand edits are only in `src/stdlib`, the hand conversions of W6 and tests whose subject is scalar semantics, and each is listed in the lane notes |
| G3 | Behaviour is preserved: every test in `tests/lang`, `test/core`, `tests/ported` and `tests/value_semantics` passes under its old name after phase 1, and again after phase 2 |
| G4 | Phase 2 lands only when the audit query finds zero `len`, index or slice on `str` left over from before the migration |
| G5 | No runtime regression: every row of the parity and runtime suites within its threshold. The rows that slice gain, and are reported (kicad-convert's walk, the markdown project, `http-server`) |
| G6 | The complete verification, formatting, `doctest .` and `doc-coverage .` pass on the final commit |
| G7 | After stage C, zero uses of the removed forms and machinery (W0's audit, with its queries). `CLAUDE.md`, `docs/python-syntax.md`, `docs/text.md`, `docs/bytes.md`, `docs/managed-memory.md` and `src/features.json` describe only the surviving language |

## 8. How it fits with the other work

- **Wave 2 (methods on built-ins, punning and the rest).** The ladder's tag
  counts put wave 3 first (FR-108, the slice copies; three tinycalc agents and
  lane E choosing `bytes` for byte semantics). Wave 3 uses `.copy()`, which
  wave 2 renames.
- **Self-hosting stage 1 (Codex).** Its lexer and parser are written over
  `bytes` with integer spans (S3 of that plan), so they are neutral to wave 3.
  Their files do not overlap. Its lane P changes Core for performance, and so
  does W4. Run them in sequence, or give W4 the Core files first.
- **FR-003, the borrow friction.** Views remove some `.copy()` calls: a slice
  passed straight to a borrowed parameter no longer copies. The stored and
  returned cases remain, and the owned-parameter proposal in the ladder report
  covers those. Neither change blocks the other.
- **The ledger.** FR-108 (slices copy) closes with stage B. FR-019's
  slice-view half closes with it. FR-411 (the borrow code is in no guide)
  should be fixed together with `E_SLICE_ESCAPES`'s documentation.

## 9. Risks

- **Silent meaning change.** This is the reason for the two phases, and G4
  checks it.
- **Scalar helpers are slower than today's cached scalar indexing on
  non-ASCII text,** if the caches go. Stage C deletes them only when no row
  regresses.
- **Views through `phi` widen the ownership checker's state.** The parent set
  union is the simplest rule, but a long-lived view can keep several sources
  alive. That is the price of not copying.
- **The `experiments/` exemption** leaves old programs that no longer compile.
  They are evidence, not code, as in wave 1.
- **Wave 2 renames `.copy()`** a second time. One more mechanical `mylang fix`
  pass.

## 10. Calendar (estimate)

This wave has fewer forms than wave 1 and more new machinery:
- stage A: about a day of lane time;
- stage B: one to two days;
- stage C: half a day, with its measurement.

These are estimates, not measurements.

The gates decide, not the calendar.

## 11. Decisions (accepted 19 October as recommended)

1. **V1. The two-phase migration (§4).** Meaning is preserved by explicit
   scalar helpers, and the byte meaning returns only after the corpus is
   migrated. The alternative is a one-step switch, which is faster but changes
   lines like `out.print(s[i])` silently.
2. **V2. The helpers' names:** `strings.chars`, `bytes`, `char_count`,
   `char_at`, `char_slice`, `char_stride`, and `lists.stride`.
3. **V3. Stepped slices are removed** in favour of the stride helpers, so that
   every slice is a contiguous view. The alternative keeps stepped slices as
   owned copies, which leaves an exception to the rule.
4. **V4. The one-parameter rule as stated in §5.3,** with no annotation
   spelling for now.
5. **V5. Views across branches** through a parent-set union (§5.2), instead of
   requiring a copy.
6. **V6. `.borrow(a, b)`, `TextView` and `ByteView`** are removed in favour of
   slices.
7. **V7. Wave 3 before wave 2.**
8. **V8. Codex implements it,** before the self-hosting run's lane P (§8). The
   operating rules and the launch instruction are in §12.

## 12. Operating rules and launch instruction for Codex

The default is **decide, log, continue**. Write every decision to
`experiments/language-wave3-20261019/DECISIONS.md`: the question, the options, the
evidence, the choice, and whether it can be reversed. Commit at every step, with a
progress section in `experiments/language-wave3-20261019/status.md`, so the run can be
inspected without interrupting it. Investigate and fix a gate failure within the run,
for up to about 6 to 8 h. Early measurements are checkpoints; only the final ones bind.

**Hard stops.** Stop and ask only for:

1. **A language change beyond V1 to V8 and §5.** For example:
   - a different meaning for an operation;
   - a broader or narrower return rule than §5.3;
   - a new surface spelling other than the helpers of V2;
   - any other shape, ownership-rule or capability change.
2. **Relaxing a gate on `main`, or any of G1 to G7,** or retiring or moving a
   verification group. Measuring one better is allowed.
3. **A broken premise.** For example:
   - a removed form whose meaning no certain fix can preserve;
   - a scalar helper that cannot reproduce today's result;
   - a corpus program that `mylang fix` cannot migrate and that is not on the
     exempt list.
4. **A failure that cannot be fixed within the bound.**
5. **Anything outside this plan's branches:**
   - pushes and `origin`;
   - `claude/*`, `projects/*` and `selfhost/*` branches;
   - Claude worktrees and another active run's tree;
   - `../guardian-zig`.

   The exception is selka-projects (§6, W6). There, migrate on a branch named
   `wave3` and leave `COMPILER` and `main` alone.
6. **Resources:** free space on `/` under 25 GB, or the machine swapping.

**Branches and authority.**

- **Branches.** Integration happens on `wave3/integration`, in the worktree
  `~/ai/canopy/mylang-wave3`, branched from `main`. Each lane gets its own branch
  (`wave3/w1-text-runtime`, `wave3/w4-core-views`, …) in its own worktree, which it
  claims with `git worktree lock --reason`.
- **Landing.** Each stage of §6 lands on `main` as its own batch:
  1. phase 1 with its regenerated corpus;
  2. phase 2, only when G4's audit query finds nothing;
  3. stage B;
  4. stage C.

  A batch is fast-forwarded to `main` when it has passed
  `python3 scripts/verify_cache.py --zig "$ZIG" --profile complete` and `main` has not
  moved since the batch's base. Do it only in the primary checkout, with
  `git -C ~/ai/canopy/mylang merge --ff-only wave3/integration`, after
  `git -C ~/ai/canopy/mylang status --porcelain` prints nothing. If `main` has moved,
  merge it into `wave3/integration`, verify again, then fast-forward.
- **Corpus migrations** are generated commits (`migration (generated): …`), produced
  by `mylang fix` on the integrated tree and regenerated after every merge of `main`,
  never merged by hand. That is wave 1's rule.
- **The self-hosting run.** It may run at the same time, limited to its P0 lanes A, C
  and D. Do not edit:
  - `src/syntax_dump.zig`, the `dump-syntax` command;
  - `selfhost/` and `bench/selfhost/`;
  - `docs/bootstrap-v1.md`.

  Its lane B (standard input) waits for W1 and W3. Its lane P and its P1 lanes wait
  until stage B has landed.

**Machine rules from `CLAUDE.md`.**

- **Environment:** every compiler tree runs `source ~/.config/mylang/dev-env.sh` first.
- **Admission:** builds and focused tests go through `scripts/build-slot.sh build …`, and
  timing (G5) through `scripts/build-slot.sh timing …`. `scripts/verify_cache.py`
  owns its own admission. At most four agents build the compiler at once.
- **The lane check:** `python3 scripts/patch_gate.py --parallel` on the lane's branch.
- **Paths:** caches, `TMPDIR` and install prefixes go under `~/.cache/`, never `/tmp`.
- **Tests:** a behavioural change under `src/` ships with a test change in the same
  diff (Guardian's `change-classification`). `SPEC.md` is frozen, so no new bullets
  or `// spec:` tags are needed. Language behaviour is tested in `tests/lang/*.my`
  where possible.
- **Breaking changes** carry their `mylang fix` repair and a `FIX-MIGRATION-1`-style
  test (`CLAUDE.md`, "Breaking changes land with their `mylang fix` migration").
- **Evidence:** keep committed evidence under 10 MB. Large logs stay in `~/.cache`.
- **Processes:** never kill a process this run did not start, and never use broad
  `pkill` patterns.

**Finish** with `experiments/language-wave3-20261019/REPORT.md`. It covers:
- G1 to G7 with their evidence;
- every new diagnostic with its fix and migration test;
- the corpus migration counts by construct, set against §1's census;
- the parity and runtime suites before and after, and the slice-heavy rows;
- what stage C deleted, and what it kept and why;
- the selka-projects `wave3` branch and its `check.sh` results;
- the ledger items this wave closes (FR-108, the slice half of FR-019).

```text
You are implementing docs/audits/language-wave3-plan-2026-10-19.md on main in
~/ai/canopy/mylang: language wave 3, str is bytes and slices are views. Read the
plan fully, then CLAUDE.md, docs/design/surface-simplification-2026-10-13.md
(proposals 16 and 17) and docs/audits/language-wave1-10-agent-plan-2026-10-14.md,
whose lane structure this plan follows. Decide, log in
experiments/language-wave3-20261019/DECISIONS.md, and continue; stop only for the
hard stops in section 12. Create the worktree ~/ai/canopy/mylang-wave3 on branch
wave3/integration from main. Run the stages in order: A phase 1 (W1, W2 and W3 in
parallel), the generated corpus migration (W6), A phase 2 once the audit query
finds nothing, then B (W4 and W5), then C (W7). Every refusal carries its certain
mylang fix repair and a FIX-MIGRATION-1-style test; no program may change
behaviour silently. Land each stage on main as its own batch after a green complete
verification, fast-forwarding only from the primary checkout as section 12 says.
Never push. Do not touch ../guardian-zig, selfhost/, bench/selfhost/,
src/syntax_dump.zig or docs/bootstrap-v1.md. In ~/ai/canopy/selka-projects work
only on a wave3 branch and leave COMPILER and main alone. Commit at every step
with a progress section in status.md. Finish with REPORT.md.
```
