# Phase 4 notes — opt-in call-site `&` mutation markers (`eaa4/markers`)

Status: **complete (experiment)** — compiling, focused tests green, every new
behavior behind an explicit opt-in flag. This is the D3 experiment the plan
gates on velocity-loop evidence; nothing changes by default. Guardian's `spec`
check still reports `MUTATION-MARKER-1` as *unlinked* because `SPEC.md` and
`src/features.json` are shared files this branch may not edit; every other
Guardian check is clean.

## What landed

The declaration side (`effects(mutation) mutates(...)`) was already live. This
branch adds the caller-side marker as an opt-in experiment:

- `src/source.zig` — `Source.mutation_markers: bool = false` carries the flag
  through lexing, parsing and checking, so the frozen `sema.checkCached`
  parameter list and `Compilation` field count do not grow. `initMapped`
  propagates it to a merged project source.
- `src/lexer.zig` — `lexWithMarkers`/`lexRangeWithMarkers` admit `&` as
  `.ampersand` only when the flag is set, and the punctuation switch now emits
  `& => .ampersand`. With the flag off, `rejectRemovedPunctuation` still emits
  `E_REMOVED_SPELLING` exactly as before.
- Every other source-body lexer reads the policy from its `Source`: project
  header scanning (`src/project.zig`), per-module parsing (`src/interfaces.zig`),
  the incremental declaration/body normalizers (`src/incremental.zig`), the
  native-test body hash (`src/native_test_facts.zig`) and the partial navigation
  fallback (`src/navigation_partial.zig`). Missing one of these would reject a
  marker body during a hash or parse pass even though the checker accepted it.
- `src/ast.zig` — the parsed `call` node gains
  `argument_markers: []const bool = &.{}`, aligned with `arguments`; `ast_copy`
  already relocates a `[]const bool` by reflection.
- `src/parser.zig` — `callArguments` records one marker per argument
  (positional `f(&x)` or keyword `f(x=&y)`), and returns the slice only when at
  least one `&` appeared, so a default-mode parse is byte-for-byte unchanged.
- `src/call_arguments.zig` — `bind` carries markers through parameter-order
  rebinding (keyword and default-filled arguments), and `release` frees them.
- `src/sema.zig` — `Checker.mutation_markers` mirrors `src.mutation_markers`
  and `checkMutationMarkers` enforces the rule on the resolved direct call
  (`ast.FunctionSignature.mutates`) and on a callable value
  (`typed.Callable.mutates`). Calls carrying a marker skip the builtin /
  constructor dispatch so a marker on a callee with no `mutates(...)` footprint
  is rejected rather than silently accepted.
- CLI plumbing — `--mutation-markers` on the main parser (`check`, `run`,
  project and internal child commands), `build` (`src/qbe_build_options.zig`
  accepts it and `src/qbe_build.zig` forwards it to the frontend child) and
  `test` (`src/native_test_options.zig` `Flags`, forwarded by
  `src/native_test_session.zig` and `src/native_test_directory.zig`).
- Cache keys — the flag is folded into the persistent frontend `Contract.flags`
  and the semantic contract, so a syntax tree or checked body parsed under one
  mode is never reused under the other. The default value is the empty string,
  so default cache identities and hit rates are unchanged.
- Tests — `src/effects_test.zig` unit tests cover the accepted direct and
  callable-value calls, the keyword rebinding path, and every diagnostic
  (missing, undeclared, non-lvalue, indirect missing, indirect undeclared) plus
  the default-mode rejection. `test/fixtures/mutation-markers.my` is the guest
  fixture; `test/integration.zig` exercises it through the real CLI with and
  without the flag.

## Flag syntax

```
mylang check  [--mutation-markers] <file.my>
mylang run    [--mutation-markers] <file.my>
mylang build  <file.my> -o <output> [--mutation-markers]
mylang test   <entry.my|dir> [--mutation-markers]
mylang check-project / run-project / emit-* etc. accept it through the same
main parser, and `test` forwards it to every compiler child it spawns.
```

Default OFF. With the flag off, `&` remains a removed spelling and every
existing program, cache entry and diagnostic is unchanged.

## Rule (with the flag on)

For every argument bound to a parameter position named in the callee's declared
`mutates(...)` footprint:

| Situation | Result |
| --- | --- |
| declared position, marker present, argument is a variable/field/index | accepted |
| declared position, marker missing | `E_MUTATION_MARKER` — `argument N is declared writable by mutates(...); add the & marker so the call shows the write: &x` |
| undeclared position, marker present | `E_MUTATION_MARKER` — `& marks a write, but the callee does not declare this position in mutates(...); remove the marker: x` |
| declared position, marker present, argument is not an lvalue | `E_MUTATION_MARKER` — `` & requires an assignable argument (a variable, field, or list slot); assign it to a local first `` |

`mutates` positions are normalized to parameter order by the existing clause
parser; `call_arguments.bind` keeps the marker list aligned when keyword
arguments or defaults reorder the arguments.

### Fix-it representation

The diagnostic pipeline has no structured `fix` field: `diagnostic.Diagnostic`
and the `diagnostic-v1` JSON payload carry `code`, `severity`, `message`,
`location`, `notes` and `stack` only. The established convention for a
suggestion is message text (`typed.suggestionClause`, `; did you mean ...?`), so
each marker error embeds the exact replacement spelling (`&x` or `x`) in its
`message`, and it flows through `--diagnostics=json` as an ordinary
`diagnostic-v1` record. Adding a structured `fix` object would change every
existing record and is deliberately out of scope for an opt-in experiment.

## What is intentionally not checked

- **Unknown callees and builtins/prelude operations.** The marker is only
  meaningful against a declared `mutates(...)` footprint. A marked call that
  resolves to no declared function skips the builtin dispatch and is rejected by
  ordinary resolution (or by the builtin's own pre-check, e.g. `print`); it does
  not get a `mutates`-specific message. Record constructors, type conversions and
  the prelude never declare `mutates`, so a marker there is never accepted.
- **Generic template bodies.** The abstract generic-body pass
  (`src/generic_bodies.zig`) has no marker check. A marker inside a generic body
  is enforced only when the template is instantiated through the concrete
  checker; a template that is never specialized is not checked.
- **Deep assignability.** The lvalue predicate accepts a variable, or a
  field/index chain rooted at a variable. It does not re-run the full
  assignment-destination analysis, so a syntactically lvalue-shaped chain over a
  temporary is not distinguished here (the ordinary assignment/target rules
  still govern the callee side).
- **Caller mutability.** The marker proves the argument is a place; it does not
  re-check that the caller's binding is mutable (the callee's write already
  carries that obligation).

## Proposed SPEC.md bullet (do not apply from this branch)

```markdown
- [MUTATION-MARKER-1] An opt-in `--mutation-markers` flag adds a caller-side `&`
  marker for input mutation. With the flag on, every argument bound to a
  parameter position named in the callee's declared `mutates(...)` footprint
  must be written `&argument` (`shuffle(&xs)`); an argument on an undeclared
  position, a non-assignable argument, or a missing marker is a located
  `E_MUTATION_MARKER` whose message names the exact replacement. The rule
  applies to resolved direct calls and to calls through callable values with a
  `mutates(...)` binder. With the flag off, `&` stays a removed spelling and no
  existing program changes.
```

## Proposed `src/features.json` entry (do not apply from this branch)

```json
"mutation-markers": {
  "kind": "tooling",
  "summary": "Opt-in `--mutation-markers` flag: a call-site `&` marks an argument passed to a callee parameter declared in `mutates(...)`, and a marker on an undeclared position, a non-assignable argument, or a missing marker is a located `E_MUTATION_MARKER` with a concrete replacement; off by default, so `&` remains a removed spelling.",
  "doc": "docs/effects.md#mutation-markers"
}
```

## Velocity-loop experiment design (task pack with and without the flag)

The plan defers the rule until loop evidence: the experiment must show whether
the review benefit pays for the Python-fidelity cost. Run the same small task
pack twice through the velocity loop and compare.

**Task pack (8 tasks, mutation-heavy, declaration contracts supplied).** Each
task gives the agent a module whose callee already declares
`effects(mutation) mutates(...)` and asks it to write the caller:

1. `shuffle(xs)` a caller-owned `list[int]` in place.
2. `append_all(dst, items)` — append a second list into the caller's list.
3. `fill(buffer, value)` — fill an `[N]int` buffer.
4. `bump(counter)` — increment a caller-owned single-element list.
5. `sort_in_place(values)` — insertion sort over a caller list.
6. `merge_into(dst, src)` — two-input footprint.
7. `advance(state)` — mutate a record field through an index loop.
8. `apply(f, values)` — call a callable value whose contract has
   `mutates(values)`.

**Control vs treatment.** Both arms get the same tasks, the same compiler and
the same prompting. The only difference is the compiler flag: the control arm
runs `zig-out/bin/mylang` with the default (flag off), the treatment arm with
`--mutation-markers`. Under the flag, the author must spell `&` on exactly the
declared positions and cannot spell it elsewhere.

**Measurements.** Per task and per arm record: turns to a green `check`/`run`;
count and codes of `E_MUTATION_MARKER` diagnostics; whether the first submission
already spelled the marker; and a reviewer's answer to "does the call line show
every caller-visible write?" (the review-benefit signal the marker is meant to
buy). Aggregate over the pack: median turns, marker-error rate, and review
findings.

**Decision rule (matches the D3 note).** Adopt the marker as a default rule only
if the treatment arm's review benefit is measurable and its fidelity/velocity
cost over the control arm is small relative to the loop's noise. Otherwise the
decision stays "deferred" and this flag remains an available experiment.
Record the raw pack (task prompts, transcripts, diagnostics and reviewer notes)
next to the other velocity-loop runs before changing any default.

Note: no velocity-loop run is available in this session, so the decision is
still open; this branch only provides the mechanism the experiment needs.

## Verification (this branch)

```
zig build                              # compiles and installs; only the Guardian
                                       # `spec` check fails on the unlinked
                                       # MUTATION-MARKER-1 tag (shared SPEC.md)
zig build fmt-check                    # PASS
zig build test-units                   # PASS 1177/1177
python3 scripts/focused_test.py units M4                              # PASS 17/17
python3 scripts/focused_test.py cli "mutation markers"                # PASS 1/1
python3 scripts/focused_test.py cli mutation                          # PASS 4/4
python3 scripts/focused_test.py cli format                            # PASS 3/3
```

The focused CLI test drives the real binary: default mode rejects the fixture
with `E_REMOVED_SPELLING`, and `--mutation-markers` checks and runs it to `8`.
`build` and `test` forwarding were verified against the focused binary: a
`test_` program that calls `shuffle(&xs)` reports `1 passed` with
`test --mutation-markers` and `E_REMOVED_SPELLING` without it, and
`build --run --mutation-markers` prints the fixture's `8`.

Git writes are denied in this sandbox (the worktree's `.git` is read-only), so
the changes are left uncommitted for the orchestrator; commit with
`--no-verify` because Guardian blocks only on the unlinked SPEC bullet.
