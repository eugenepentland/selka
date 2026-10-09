# Partial self-hosting for faster compilation and testing

Date: 2026-09-21. Status: proposed implementation plan, based on repository
inspection; no new timing measurements or compiler changes.

The priority is the time from editing the compiler or a test to getting a useful
test result. The recommendation is to keep a compiled Zig host and move bounded
compiler components and test cases out of its rebuild dependency graph. Start
with the test loop, then make the lexer/parser a replaceable native component
written in mylang. Expand only where the measured edit loop improves.

This does not require the mylang compiler to compile itself. The existing Zig
compiler can compile the `.my` components. Its checker, lowerer, native build
driver, runtime and backends can continue doing their current jobs.

## What the existing work establishes

| Finding | Consequence for this plan |
| --- | --- |
| The [September 14 plan](self-hosting-implementation-plan-2026-09-14.md) aimed to move the whole frontend through QBE emission, with stage 1/2/3 qualification. | That endpoint is larger than the first useful speed improvement. |
| The [September 17 pause](selfhost-pause-and-salvage-2026-09-17.md) records a stale oracle and the cost of implementing moving semantics twice. | Migrate one production responsibility at a time; do not resume P7–P10 or merge the entire old branch. |
| The preserved `selfhost/integration` worktree is now at `fe94e0d0`, with pause/fixture commits after checkpoint 32. It contains actual lexer/parser modules and their tests; the main checkout has only the small prototype. | Salvage selected source and fixtures from the preserved worktree, not just `selfhost/prototype`. Requalify them against current behavior. |
| The paused port's major remaining lowering work concerned its own compiler implementation. | A component built by the Zig compiler does not need the paused `.my` lowerer/emitter to be finished. Current-compiler compatibility of the selected component still needs checking. |
| [Test-layout measurements](../tooling/test-layout.md) reported a warm `.my` area at 0.06 s and an edited area under 1 s, versus a focused Zig area around 1.5 s, at their September 18 snapshot. | Moving behavior tests is already supported and gives an early reduction in test-authoring rebuilds. These are historical observations, not current guarantees. |
| The [Zig/guest timing audit](zig-vs-guest-test-times-2026-09-16.md) found an 80.73 s Zig test execution with its test binary compilation cached at 8 ms; other optimized test compilations took about two minutes. | Measure compilation and execution separately. Self-hosting does not remove the cost of running an unnecessarily broad suite. |
| [Integrated velocity work](velocity-implementation/final-status.md) already supplies checked-body caches, generic replay, shared test preparation and selective lowering. | Use these facilities; do not restart the older C2/C3/C4 backlog. Their final 100k feedback targets remained unmet. |
| [Current native builds](../tooling/native-build.md) default to LLVM O3/LTO for `ReleaseFast`, while Debug tests use QBE. The [performance roadmap](../performance-roadmap.md) records about 0.85 s of LTO relinking after a real edit in one workload. | Explicitly select QBE for component iteration. Host optimization mode and the backend used to build a component are separate choices. |

The source inspection started on `perf/lever-search` at `dcbcc2fd`. Older claims
that QBE is the only backend, and early estimates of the remaining test migration,
must not be treated as the current implementation inventory.

## 1. Establish the actual wait, then keep a fast development toolchain

Measure equivalent edits and test selections before choosing a larger port:

| Representative edit | Record separately |
| --- | --- |
| Change one Zig parser/checker body | Compiler rebuild, test-binary rebuild, selected test execution |
| Add/change one positive language test | Test preparation, native compilation/linking, execution |
| Change one rejection or expected-trap case | Harness rebuild, compiler invocation, result comparison |
| Change a `.my` compiler-component body, once available | Component check/build/link, host invocation, selected regression execution |

Record cold, warm unchanged, and genuinely edited runs, median/p95, compiler
identity, selected/executed/cached counts, and time spent in subprocesses. Use
repeated distinct edits so reverting to an already cached artifact cannot stand
in for compilation. Start with small representative cases; run the existing
large-project harness only when scale becomes the question.

Keep an optimized, verified compiler installation in a dedicated location with
its QBE and runtime resources. Do not let routine Debug builds overwrite it.
Keep the development host and the compiler used to build components explicitly
identified; initially they may come from the same verified source revision.

Use the existing paths now:

- `python3 scripts/focused_test.py units <filter>` or `cli <filter>` for the
  Zig machinery under modification. These supported targets already avoid the
  install/whole-tree Guardian graph and reject an empty selection.
- Invoke `mylang test` directly on a language area for `.my` changes. Keep the
  existing `--gc-stress` coverage where applicable.
- Build native compiler components with explicit `--backend qbe`; compare
  `--mode Debug` with `--mode ReleaseFast --backend qbe` if instruction accounting
  makes compiler-sized components slow. Retain the checked test configuration.
- Keep the full repository gates for integration and completion of implementation
  work, as required by the working rules. Self-hosting changes the fast loop,
  not the acceptance requirements for Zig changes.

**Exit:** a recorded baseline and a repeatable command for one useful edit/test
cycle. No new watch service or interpreter is needed to reach this point.

## 2. Remove test-case edits from Zig compilation

Finish the justified migrations under `tests/lang`, auditing the current bodies
rather than treating the September 18 list as an outstanding count. Move tests
that assert guest values into `.my`, preserve SPEC ownership and stress options,
and remove their redundant Zig value assertions in the same change. Keep
allocation-failure injection and compiler-internal assertions in Zig.

For negative cases, add a small data-driven compiler fixture path: source files
plus expected diagnostic code/location or expected runtime trap/status. Start
with one frequently edited area and reuse the existing diagnostic/golden-driver
infrastructure where suitable. The driver can remain in Python or a prebuilt
host; writing the runner itself in mylang is not necessary for the speed gain.
Load fixtures at runtime rather than embedding their text into a Zig test binary.

This is a proposed extension to the current test-layout rule: `mylang test`
currently needs a checked project and treats a trap as failure. Do not move a
negative test into an ordinary `test_*` function or discard an internal assertion
just to make it eligible. Establish the fixture runner before migrating those
cases. Preserve each case's diagnostic/trap contract and SPEC coverage.

**Selection must match what changed.** `--affected` can narrow tests after guest
source edits. Unchanged guest sources do not prove that their outcomes are
unchanged after a compiler implementation edit. Such edits require a deliberate
regression selection and cache keys that include the changed compiler component;
force execution when checking the invalidation mechanism itself.

**Exit:** editing a migrated positive or negative case rebuilds no Zig test
executable. Equivalent assertions still execute, and unchanged receipts are
reported separately from executed tests. This improves test development now;
the existing Zig compiler still needs rebuilding when its own implementation changes.

## 3. First compiler migration: lexer/parser, built by the existing compiler

Use the production lexer/parser closure in the paused branch as a donor. In that
tree, the parser imports `source`, `token`, `diagnostic`, `lexer`, `strings`,
`syntax` and `render`. Bring across only the required closure and useful fixtures.
Repair it to the current language and source-location conventions before adding
new grammar behavior. Do not import the old checker, lowerer or emitter as a
prerequisite.

The intended production path is:

```text
                         pinned compiler + QBE
                                  |
                         builds changed .my component
                                  |
source files -> Zig host -> .my lexer/parser -> versioned syntax records
                   |                                  |
                   +-------- Zig checker <-------------+
                                |
                      existing lowering and backend
                                |
                         selected regression tests
```

The `.my` lexer/parser is a native executable, built only when its inputs change.
The host invokes that executable directly, rather than recursively running
`mylang run` for each parse. Start with a bounded process protocol and batch
modules within an invocation; measure startup and serialization before choosing
a persistent worker or shared-library ABI.

Use a versioned data format with source bytes/identity, parse mode and options,
token tags/spans, AST tables and declaration data, and structured diagnostics.
The Zig adapter validates tags, indices, counts and source bounds, then constructs
the existing `ast.Program` representation. It must not pass pointers or assume
that Zig and managed `.my` records share a layout. Choose the wire encoding during
the pilot; JSON support in the old bootstrap whitelist is not an established
permission to depend on it.

Integrate at all syntax consumers: single-file compilation, module header/import
discovery, project/interface parsing, formatter input, and syntax-cache loads.
Routing only `run` through the new parser would leave other commands with
different language behavior. `src/compiler.zig`, `src/project.zig`, the interface
path and `src/project_syntax.zig` are places to audit, not a complete call-site list.

Split delivery into two reviewable steps:

1. **Lexer/transport pilot:** compile the donor closure with the pinned compiler,
   compare tokens and located errors against the current Zig lexer, and measure
   the component edit/build/test loop. This is feasibility evidence, not a claim
   that the compiler is already using it.
2. **Parser production switch:** match current accepted/rejected programs, AST
   meaning, recovery and diagnostics, then route normal commands through it.
   Keep the old parser only as an explicit bootstrap/reference implementation;
   ordinary grammar fixes have one maintained production home.

The pinned compiler can build a parser that recognizes newer syntax: that syntax
is input data to the parser, and the parser's own implementation stays within the
seed's supported subset. This avoids freezing the whole evolving language.
Reconcile `bootstrap-v1` and D6/D7 for this component workflow explicitly; the
existing full-bootstrap documents should not silently acquire a different meaning.

**Exit:** an actual parser implementation edit, component rebuild and selected
end-to-end compiler tests run without rebuilding Zig compiler/test sources.
A standalone port that normal commands never call does not meet this condition.

## 4. Cache and bootstrap rules required for the hybrid compiler

- Give every component a content identity covering its source/import closure,
  build seed, configuration and protocol. Include parser identity in syntax and
  downstream semantic/diagnostic/test-result validity. The unchanged host binary
  is no longer a sufficient compiler identity.
- Keep native object reuse based on emitted content and existing driver/runtime
  identities where sound. Do not unnecessarily discard every object when a
  parser implementation changes but the resulting program does not.
- Rebuild with an explicitly selected seed; component building must not depend
  recursively on the component being rebuilt. Publish successful outputs
  atomically. A failed component build must fail the development command rather
  than silently run an older artifact and report green.
- Use differential tests during each migration, then remove the duplicate from
  the routine production path. Keep a known seed artifact/source revision for
  bootstrap; do not require every subsequent feature to be implemented twice.
- Compare cold, warm and cache-disabled results. Include malformed transport,
  a component-only edit, a same-size source edit, and a changed imported module.
  Maintain deterministic diagnostics and the existing source mapping.

Initial targets, to be calibrated against step 1: at least a 2x improvement in
the equivalent component edit/test cycle, with a small focused cycle aiming for
under 1 s p95. Record component-build time and its added cost to ordinary checks
separately. If transport or a slower frontend consumes the saved build time,
stop expanding the port and address the measured cost first. These are proposed
acceptance targets, not measured speedups.

## 5. Choose the next component from the remaining waits

| Changes still causing waits | Next candidate | Limit of the benefit |
| --- | --- | --- |
| Formatting, diagnostic presentation or lint rules | `.my` formatter/renderer/rules consuming host-produced syntax or semantic facts | Error detection and semantic facts remain Zig responsibilities until separately migrated. |
| Standard-library algorithms | Explicit development source-directory support for the existing `.my` standard modules | `src/standard_library.zig` currently embeds these files; ordinary file edits otherwise still rebuild the host. Primitive/runtime changes remain native. |
| QBE text transformations | One pure text pass through a narrow interface, with the current pass order preserved | Current cleanup is intertwined with two emission passes, allocation analysis and frame sizing; moving the entire emitter is not a small extraction. |
| Type rules, inference and effects | A separately planned semantic-checking component | This is the large remaining step. Parser self-hosting will not accelerate a change that still edits `sema.zig` or `generic_bodies.zig`. |
| Allocation, GC, capability plumbing or machine-code support | Continue focused native development | Self-hosting the frontend does not remove these native rebuilds. |

The standard-library source-directory improvement is useful but is not the main
answer to compiler rebuild time. If implemented, use one explicit library
snapshot across providers, preserve reserved module identity, and hash actual
contents through all relevant caches. Do not rely on a local file shadowing
`@stdlib`: the current project loader selects embedded standard modules first.

Do not make a full checker port, a new VM/JIT, hot reload, or stage 2/3
reproducibility prerequisites for these gains. Add a persistent process only if
the new measurements show process startup is material.

## First implementation batch and stopping point

The first batch should deliver the baseline, a repeatable focused test command,
one audited test-area migration, and the lexer/transport feasibility pilot.
That makes both the immediate testing benefit and the likely cost of the parser
switch reviewable before committing to the larger integration.

The useful partial-self-hosting stopping point is the production lexer/parser
plus migrated tests, with the Zig semantic compiler, runtime and native driver
remaining supported components. Extend it when actual work repeatedly falls in
those remaining Zig areas. Success is fewer seconds waiting on representative
edits, not a percentage of compiler lines rewritten in mylang.

No builds or Guardian gates were run while preparing this plan. The historical
timings above are cited evidence; all new targets require implementation-time
measurement.
