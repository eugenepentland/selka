# Effects as arguments: gap analysis and plan (2026-09-17)

This records how far mylang already implements the "Effects as Arguments" design
sketch (2026-09-17), where it differs, and a dependency-ordered plan to close the
gaps that are worth closing. Status: every decision in section 2 is accepted; no
wave is implemented. Evidence is the source tree at `237871a6` plus the
uncommitted working tree; file:line references are to that state. Probe programs
used for the behavioural claims are described inline; each was run with
`zig-out/bin/mylang check` or `run`.

## Assumptions

Both assumptions were confirmed with the decisions in section 2.

- **Syntax stays Python-shaped.** The sketch's syntax section proposes braces,
  `fn`, `let`, `struct`. The brace dialect was removed on 2026-09-13
  (`docs/python-syntax.md`), and the scorecard of the same day recommended staying
  Python-shaped with every deliberate departure either behaving like Python or
  looking visibly different. This plan maps each sketch construct onto a Python
  spelling. The sketch's own reason for braces — written signatures and call-site
  markers — already holds here: every parameter and result is annotated, and `?`
  is a call-line marker. Reopening the syntax family is a separate decision this
  plan does not depend on.
- **The velocity lanes stay in force.** Lane C (Python fidelity, CPython oracle)
  is weighted 0.2 in `velocity/goal.json`. Every wave below states its lane C
  cost so the loop can see the trade rather than discover it.

## 1. Where the language already stands

The sketch has five rules and a reading table. Most of it exists.

| Sketch rule | Current state | Verdict |
| --- | --- | --- |
| Capabilities are ordinary typed values passed as parameters | `Filesystem`, `Network`, `Clock`, `Entropy`, `Environment` are five scalar variants of the runtime `Type` enum (`src/runtime_values.zig:7-27`); Python spellings map in `src/prelude.zig:44-60`. Passed, returned, reassigned, and stored in `record`/`class` fields freely (probe: a `record Env` holding `fs` and `clock`, a `class Box` holding `fs`, both check clean). Not storable in lists (`E_LIST_CAPABILITY`, `src/record_layouts.zig:99-102`) or `Cell` (`E_CELL_ELEMENT`), not printable, no `==`, not across the C ABI. | Done |
| One entry point; nothing else can create one | Only the generated entry shim mints them (`src/qbe_build_outputs.zig:82-95`); `Filesystem()` in call position is `E_UNKNOWN_FUNCTION`; no cast or literal produces one. `E_MAIN` restricts entry parameters to `args` plus one capability per kind (`src/sema.zig:4032-4141`). | Done |
| No forging | See above. The bytecode validator recomputes every effect summary independently (`src/effects.zig:602-635`). | Done |
| Narrowing only | `restrict_resource[read, write, complete](fs)` intersects permissions and cannot widen (`src/external_resources.zig:92-99`, `src/qbe_resources.c:64-68`); it works in Python syntax (probe: `restrict_resource[read](fs)` then `write_text` on the result answers a denial). But it is the only narrowing: no directory scoping, nothing for `Clock`, `Entropy`, `Environment` (`src/sema.zig:2835-2840` rejects them), and no `SPEC.md` bullet documents the operation. | Partial |
| Values over authority | `time.now(clock) -> Result[Instant, str]` returns a value record (`src/stdlib/time.my:109`); `random.from_entropy(rng)` returns a generator value. `Environment` has no Python surface: only `environment_get[Lookup](env, [75u8])` with a caller-declared result record over a byte array (`src/sema.zig:2842-2858`). | Partial |
| Bundles are capabilities too | A `record` or `class` may hold capability fields and passes like any value; the effect system charges use, not possession, so a bundle costs nothing until it is used. | Done |
| No global `open()`, `now()` | Both take the capability first. | Done |
| No global `print()` | `print` and `eprint` are ambient builtins (`src/sema.zig:1199-1232`) whose destination is a static enum, `typed.Sink` (`src/typed.zig:104`). They contribute the `output` effect, which only an explicit `noio` or `effects(...)` ceiling can reject. There is no output capability, no `Stream` type. | **Gap** |
| No mutable global state | Top-level declarations are `const NAME: T = expr` (desugared to a pure getter, `src/parser.zig:371-387`) plus types and functions. A bare `NAME = [1, 2]` is `E_SYNTAX` (probe). No module initialiser. | Done |
| Signature covers mutation (`inout` + `&`) | Declaration side exists: `effects(mutation) mutates(a, b)` with overlap checking (`src/origins.zig`). It is enforced only when the function declares a ceiling (`src/origins.zig:547`); an unannotated function may write any caller-owned `class`, `list`, `dict` or `Cell` silently. No call-site marker; `&` is a removed spelling (`src/removed_names.zig:35`). A write to a by-value `record` parameter that nothing reads afterwards is now a hard error, `E_DEAD_RECORD_WRITE` (probe). | Partial |
| Failing is `Result` + `try` | `Result[T, E]`, postfix `?`, `E_RESULT_UNHANDLED`, no exceptions, `Option[T]`. Prefix `try` becomes postfix `?`; both sit on the call line. | Done |
| Pausing (`async`) | Nothing implemented; `docs/concurrency-proposal.md` is a stale proposal (it links a deleted `src/vm.zig`). The sketch leaves this undecided too. | Deferred |
| A function with none of these is pure | No purity notion exists except `E_CODEC_EFFECT` (`src/domain_codecs.zig:30`). Under the capability model purity is readable from the signature once output and foreign calls are capability-gated. | Follows from the gaps |
| Closures cannot smuggle authority | Lambdas are noncapturing (`E_LAMBDA_CAPTURE`, `src/sema.zig:2441-2447`); a callback type carries its effect ceiling and `mutates` footprint as part of its identity (`src/callables.zig:38-59`); a capability may be passed to a callback only as a visible argument. | Done (ADR D5) |
| Shared mutable state is an explicit box | `Cell[T]` and `class` are the boxes; writes are the `mutation` effect; the type is the marker. | Done |
| Foreign code needs a capability | `extern def ... effects(host)` is ambient: no capability parameter, no `--allow-host`, "bypasses provider grants" (`docs/c-ffi.md:73-81`). | **Gap** |
| Reading the signature | `list-interfaces` prints names only (probe); `--contracts` prints `effects=…;mutates=…;origin=…` but spells capability types by their removed internal names (`filesystem_cap`, `src/interfaces.zig:756-759`). | Gap (tooling) |

Two things the sketch does not have that mylang does, and should keep:

- **Per-capability entry parameters instead of a `System` root.** `def main(fs:
  Filesystem, clock: Clock)` says on its own line which authorities the program
  can ever use; `main(sys: System)` makes the reader open the body. The
  command-line grant model (`--restrict`, `--allow-*`) keys on exactly this. A
  root bundle would weaken the property the sketch praises.
- **Inferred effects alongside capabilities.** The nine-bit effect mask
  (`src/effect_set.zig`) is what lets a ceiling three calls up reject a leaf
  operation with a path in the diagnostic. Capabilities answer "may it", effects
  answer "does it"; both stay.

## 2. Decisions (accepted 2026-09-17)

Every recommendation below was accepted by Eugene Pentland on 2026-09-17, so the
waves treat them as settled. Reopening one changes only its wave.

| # | Decision | Accepted answer | Why |
| --- | --- | --- | --- |
| D1 | Output becomes a capability | **Yes.** Add a `Stream` capability; `out.print(...)` replaces `print(...)`, `err.print(...)` replaces `eprint`. Add a `debug(...)` statement that needs no capability and is stripped from `--mode ReleaseFast` builds. | This is the sketch's central rule and the one property the current design lacks: today a signature with no capability and no ceiling still may print. `debug` is the sketch's own answer to the plumbing cost. Lane C cost: 13 of the 67 CPython-oracle idiom probes print and would have to move to `mylang-only` or be rewritten with a harness stream. |
| D2 | Mandatory mutation footprint | **Yes.** An externally observable write with no `mutates(...)` clause on the declaration becomes a diagnostic regardless of whether a ceiling is declared; the message carries the inferred clause as the fix. One version as a warning (ADR D7), then an error. | Closes "absence is informative" for mutation at the callee without any new syntax. Required before any call-site marker could be checked. |
| D3 | Call-site `&` marker | **Defer; decide with loop evidence after D2.** | It is the most Python-hostile item in the sketch: every `shuffle(&xs)` and `bump(&counter)` diverges from Python and from the aliasing decision that made `class` behave like Python. D2 already makes the callee signature complete; `&` adds call-line visibility at a fidelity cost the loop can measure. |
| D4 | `inout` on value records | **No.** | `class` is the reference type, `record` the copy; `s = add_line(s, line)` or `class Stats` expresses the sketch's example without a third passing mode or by-reference lowering (records are blitted twice today, `src/qbe.zig:304-308`, `868-873`). |
| D5 | `System` root bundle | **No**, keep per-capability entry parameters. | See above. |
| D6 | Foreign calls need a capability | **Yes.** Add a `Host` capability; every `extern def` and `host def` takes it as a leading parameter that is checked and then dropped before the C call. `--allow-host` under `--restrict`. | Makes "this function can reach C" visible in the signature; today it is the one ambient authority left once D1 lands. |
| D7 | Allocation stays ambient | **Yes.** | GC by default is a stated goal; `managed_allocation` and `noalloc` already track it. |
| D8 | Async | **No work.** | Undecided in the sketch; the concurrency proposal's Go-style blocking calls need no marker. |

## 3. Waves

Waves 1 to 4 touch disjoint files and may run in parallel worktrees once wave 0
lands. Every behavioural line needs a `// spec:` tag, a `SPEC.md` bullet, and a
`src/features.json` slug with a runnable doc example (Guardian and
`doc-coverage` block otherwise).

### Wave 0: contract hygiene and reading the signature

No semantic change. Makes the existing model legible before it grows.

1. **`list-interfaces` shows the whole signature by default**: capability
   parameters by their Python spelling, inferred `effects`, `mutates`
   positions by name, and the declared ceiling if any. Fix `interfaces.zig:756-759`
   to render `Filesystem` rather than `filesystem_cap`. This is backlog item
   D-4 and the tooling half of "reading a signature".
2. **Python surface for `Environment`**: `env.get("HOME") -> Option[str]` and
   `env.names() -> list[str]` in an embedded `environment` module or as builtins,
   over the existing `environment_get` primitive. Move `environment_get[...]`,
   `clock_now[...]`, `random_u64[...]` behind the trusted-stdlib gate the way
   `__float_sqrt` is (`src/parser.zig:120`), so they stop being public spellings.
3. **Document `restrict_resource`** as it stands (a `SPEC.md` bullet and a
   `docs/effects.md` example) so wave 2 has a baseline to replace.
4. **Stale contract lines**: `SPEC.md:602-603` and `:707` still call `class` a
   compatibility spelling of `record`; `docs/adr/D5-noncapturing-lambdas.md:21`
   predates managed `class`. Write ADR D8, "authority is an argument", stating
   the five rules and the decisions above.

Size: small. Files: `src/interfaces.zig`, `src/main.zig`, `src/navigation.zig`,
`src/stdlib/`, `SPEC.md`, `docs/effects.md`, `docs/io.md`, `docs/adr/`.

### Wave 1: output is a capability (D1)

**Language.** A new capability kind `Stream`. The entry point may declare
`out: Stream` and `err: Stream`; because `E_MAIN` allows one parameter per kind,
the entry rule is extended to match streams by parameter name (`out`, `err`) or
by a two-kind split (`Stdout`, `Stderr`) — the plan prefers one `Stream` type
with the name rule, so a helper can take `log: Stream` and be handed either.
`stream.print(values..., sep=, end=)` and `stream.write(text) -> int` are the
operations; both contribute `output`. `print(...)` and `eprint(...)` with no
receiver become `E_OUTPUT_CAPABILITY`: *"print needs a Stream; add `out: Stream`
to this function and pass one from main"* (a fix in `diagnostic-v1` form, per
backlog C-12).

**`debug(values...)`** writes to standard error, takes no capability,
contributes no effect, returns unit, and is emitted only in `--mode Debug`
builds and by `run`/`test`; a `--mode ReleaseFast` build drops the node in
lowering. It exists so an agent can look inside a pure function without editing
five signatures.

**Implementation.**

- Type: add `stream_cap` to `runtime_values.Type` and `capabilityIndex`
  (`src/runtime_values.zig:7-39`); `prelude.reservedType` maps `Stream`
  (`src/prelude.zig:44-60`). Note `capabilityIndex` is `u3`: five kinds exist,
  so `Stream` and wave 4's `Host` leave one slot free.
- Checker: `outputBuiltin` (`src/sema.zig:1199-1232`) becomes a method check on
  a `stream_cap` receiver; `typed.Print` carries a stream operand instead of the
  static `Sink` (`src/typed.zig:104-106`); the entry rule at `src/sema.zig:4137`
  admits the new kind. `debug` reuses the print operand checks with a `debug`
  flag.
- Effects: `.print` keeps `.output` (`src/effects.zig:334`, bytecode twin at
  `:525`); the `debug` node contributes nothing in both switches and in
  `origins.nodeOrigin` (`src/origins.zig:220-239`). Bump
  `cache_key.Contract.effects` (`src/cache_key.zig:28`, `src/qbe_build_cache.zig:27`).
- Lowering: the per-type C renderers (`src/io_render.zig`, emitted per program)
  take the fd from the stream value's sentinel rather than a constant; entry shim
  grants `stream_cap` in `src/qbe_build_outputs.zig:82-95`; `src/qbe_providers.c`
  gains the sentinel. `--restrict` grants streams unconditionally (a program
  without stdout is not a useful denial), so `cli_grants.zig` needs no flag.
- Tests: guest tests already capture `print` off the protocol channel
  (`docs/tooling/guest-tests.md`); the runner hands each test a `Stream` pair
  the same way the entry shim does, so `def test_x(out: Stream)` works and a
  test without one cannot print except through `debug`.

**Migration.** 27 corpus `.my` files print (examples, experiments, velocity
probes), 31 Zig test files with 169 `print(` sites, 18 fenced doc examples in
seven pages, `SPEC.md` bullets `IO-1` to `IO-6`. `eprint` has two uses. A
one-off script rewrites `print(` inside `def main` bodies to `out.print(` and
adds the parameter; helpers that print need a hand-added `out: Stream`
parameter, which is exactly the visibility the rule buys. Velocity: the 13
CPython-oracle probes that print move to `mylang-only`, and `velocity/goal.json`
records the lane C baseline change as a decision, not a regression.

Size: large. This is the wave to run as its own branch with a release note.

### Wave 2: narrowing in Python spelling

Replaces the bracket form with methods on the capability and adds the two
derivations the sketch uses.

- `fs.read_only() -> Filesystem`: the existing permission intersection with a
  Python spelling; `restrict_resource[...]` becomes `E_REMOVED_SPELLING` with
  the replacement named.
- `fs.dir(path) -> Filesystem`: a filesystem whose root is `path` resolved under
  the current root, rejecting escapes with the existing `scopedPath` rule
  (`src/scoped_providers.zig:185-199`). The derived value is lazy: it records a
  (root, prefix) pair in a bounded host-side table and every operation joins the
  prefix before the existing checks, so `dir()` itself performs no I/O and
  contributes no effect, like `restrict_resource` today. The sentinel encoding
  in `src/qbe_resources.c:47-63` gains a scope index.
- `env.only("HOME", "PATH") -> Environment`: name narrowing over the runtime's
  existing allow-list (`--allow-env=NAME,...` already implements the check).
- `Clock` and `Entropy` have nothing to narrow; the value route (`time.now`,
  `random.from_entropy`) is the narrowing. `Network` has no Python surface at
  all (zero corpus uses; only `acquire_resource`), so host narrowing waits for
  one.

Each derivation is checked in `src/sema.zig` next to the `restrict_resource`
arm (`:2835-2840`) and mirrored in `src/generic_bodies.zig:1064`. Tests:
`test/fixtures/attenuation.my`, `src/scoped_providers_test.zig`,
`src/resource_source_test.zig`, `tests/goldens/qbe_resource_parity.json`.

Size: medium. Independent of wave 1.

### Wave 3: the mutation footprint is mandatory (D2)

- `origins.checkDeclaredBound` returns early when no ceiling is declared
  (`src/origins.zig:547`). Change it to report `W_MUTATES_MISSING` (one
  version, ADR D7) and then `E_MUTATES_MISSING` when `summary.external` is true
  and the declaration has no `mutates(...)`. The message prints the inferred
  clause verbatim so the fix is a paste: *"this function writes `values`
  (parameter 1) reachable from the caller; declare `mutates(values)`"*.
- Because a `mutates` clause requires the `mutation` effect in the ceiling
  (`E_MUTATES_EFFECT`, `src/parser.zig:716`), allow `mutates(...)` without a
  ceiling to mean "unbounded effects, this footprint".
- Overlap checking (`E_MUTATION_OVERLAP`) then applies to every declared
  footprint, which is what the sketch's read-only-by-default parameters mean.
- `list-interfaces` (wave 0) already prints the footprint, so the call line's
  reader can see it from the signature.

Migration: 2 corpus files declare `mutates` today; the warning period surfaces
how many helpers write caller state silently. Size: small. Files:
`src/origins.zig`, `src/parser.zig`, `src/effects_test.zig`.

D3 (`&` at the call site) is a follow-on: with footprints mandatory, a marker is
a one-line check in the call checker against the callee's `mutates` positions.
It should be tried behind the velocity loop as an experiment on a task pack
before it becomes a rule.

### Wave 4: foreign calls take a `Host` capability (D6)

- Add `host_cap` (`Host`). An `extern def` or `host def` must declare a first
  parameter of type `Host`; the checker verifies it at every call and the C ABI
  lowering (`src/qbe_c_abi.zig`, `src/qbe_host_lower.zig`) drops it before the
  foreign call. `effects(host)` stays inferred so ceilings keep working.
- `--allow-host` under `--restrict`; granted by default like the others.
- A callback type whose parameters include `Host` is the only way a function
  value can reach C, which closes the last hole in the closure question.

Migration: 29 files mention `extern def` or `host def` (mostly Zig tests and
docs); one corpus program. Size: small. Files: `src/parser.zig:477-501`,
`src/c_abi.zig`, `src/sema.zig:187-189`, `src/cli_grants.zig`,
`src/qbe_grants.c`.

### Wave 5 (optional, after the loop has data)

- Method spellings for the file helpers (`fs.read_text(path)`) for consistency
  with `out.print` and `fs.dir`; the free-function forms stay one version.
- A Python-shaped `Network` surface, then `net.host(name)` narrowing.
- Use signature purity (no capability parameters, no footprint) to let
  `mylang test` skip re-running unaffected pure tests without a receipt.
- Decide D3.

## 4. What the plan deliberately does not adopt

- **Braces, `fn`, `let`/`var`, `struct`.** Assumption above.
- **`let` immutability.** Python has none; unused and dead bindings are already
  diagnosed. Parameters remain rebindable locals, which is not observable.
- **`inout` for records** (D4) and a **`System` root** (D5).
- **An allocator parameter** (D7).
- **`try` as a prefix.** `?` is the same marker on the same line.
- **Removing effect inference in favour of capabilities alone.** Capabilities
  cannot express allocation or mutation, and the inferred mask is what makes a
  bound diagnosable with a path.

## 5. Risks

- **Lane C.** Wave 1 is the first change that makes a plain Python program
  (`print("hi")`) invalid mylang. The sketch accepts that cost knowingly; the
  loop must record it as a baseline change.
- **Test churn.** 169 `print(` sites in Zig tests are mechanical but wide;
  wave 1 should land with the rewrite script committed under `scripts/`.
- **`capabilityIndex` is `u3`.** Waves 1 and 4 take two of the three free
  slots. A ninth kind means widening the index, the sentinel encodings in
  `src/qbe_providers.c` and `src/qbe_resources.c`, and the grant table.
- **Semantic cache.** Any new node kind or effect encoding must bump
  `cache_key.Contract.effects` and `semantic_cache.mutation_contract_version`
  (`src/semantic_cache.zig:30`) or warm caches will replay stale bodies.
- **`mutation` is not an ordinary effect.** It is excluded from graph
  propagation (`src/effects.zig:360, 414, 553, 630-631`) and produced by
  `origins.zig`. Wave 3 changes reporting, not propagation; do not fold it into
  the mask walk.
