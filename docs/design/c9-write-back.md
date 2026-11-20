# Write-back results and the whole-program corollary (design note, package C9.4)

**Status (26 October 2026): option (b) approved and landed on `c9/write-back-design` (section 8).**

This is the design hour of C9.4 in `docs/audits/ownership-certificates-plan-2026-10-26.md` (§7.3), written by the Lean
lane. It chooses between the two ways the plan names to close `CallWf.noEmptied`, the one hypothesis of the
whole-program corollary (`runs_sound`, `main_no_leak`) that excludes real programs. It changes nothing in `src/` or
`proofs/`. The measurements are `experiments/c9-measure-20261026/REPORT.md`.

## 1. The problem

A function with `mut` parameters returns a record of its declared result (unless it is `unit`) followed by each `mut`
parameter's final value (`build.zig`, `returnType`; the caller side is `callTarget` and `writeBack`). The caller reads the
parts out with one `record_get` each. `own.zig` (`Taking.empty`) marks such a record `emptied` when every managed field is
read exactly once in the block that defines it, so the exporter writes the call's value as `state emptied` with a `slots`
list. The per-function theorem (`check_sound`) covers this: an `emptied` value is an immediate, the call destroys the trees
it consumes, and each take out of the record is a fresh tree (NOTES.md items 12 and 13). The corollary does not.
`PStep.call` runs the callee, which returns the record as `.own r` with `r` live; the caller's certificate says the
destination is `emptied`, which the invariant requires to be `imm`. `effect_of_post` cannot build the `Effect`, so
`CallWf` carries `noEmptied : cert.state d ≠ .emptied` as a hypothesis (design entry 48: "`noEmptied` is **not**
enforced").

Programs with at least one such call: 26% of the gate corpus, 73% of EDA stage 2, 80% of selka (891, 2,036 and 279
calls). For every one of those programs the corollary says nothing today.

Two facts decide the options below.

- The record travels through a tuned ABI. `emit_llvm.zig` (`InOutAbi`, `compact`, `returnFinals`, `finalFields`), `emit_homes`
  (sret sharing) and CE2 (construction directly in the caller's destination) all key off "the call returns a record whose
  fields are the result and the in-out final values". 37 non-test files of `src/core` mention `record_get`.
- The caller-side meaning is already given by the per-function model. The model's `Effect` for a call whose destination is
  `emptied` is: the consumed trees are destroyed (`Xform` with no result tree), the destination is `imm`. That is the
  convention for an `emptied` constructor (entry 41), for `record_get` and for `union_take` results. Only the whole-program
  step, which has the callee's actual return value, disagrees with it.

## 2. Option (a): an IR form (a multi-result call or a write-back operation)

**What changes in Zig.**
- `ir.zig`, `verify_ir.zig`: an instruction with several results (or a distinct op for "part k of a call's result" that
  is itself a definition), its printing and its verifier rules.
- `build.zig` (`returnType`, `callTarget`, `writeBack`) and `build_fn.zig` (`mapCallable`): the callee returns a
  list of results and the caller binds them; every `ret` of a function with `mut` parameters.
- `own.zig`: classes for the new form; the `empty` rule for call results disappears, the one for user records stays.
- The passes that read a call's type or its `record_get`s: inlining, fusion, forwarding, effects, destination
  planning, facts (the 37 files above).
- `emit_llvm.zig` and `emit_homes.zig`: to keep the call ABI, the new form must lower to the record that `InOutAbi`
  and CE2 already expect; otherwise the ABI changes and the parity suite decides.
- `ownership_export.zig`, `validate_ownership.zig` and the format: several result values per instruction; the
  `emptied` call case in the exporter and the validator goes.

**What changes in Lean.** `Inst.dst` becomes a list. About 250 occurrences in 20 files mention `.dst`
(`EdgeStep` 55, `InstBase` 32, `Checker` 31, `StaticFacts` 25, `InstPres` 25, `EdgeBase` 22, ...). `Effect` creates one
tree per owned result; `Function.result` and `Post` become a list of result shapes; `RunsAt`, `PStep.call` and
`callNext` bind several values; the callee's `ret` returns several values and `ResultShape` is per part.

**What `CallWf` then states.** The number of destinations equals the callee's result arity; `resOwned`, `resBor`
and `resImm` hold per part; `noEmptied` is gone because a call result is never an aggregate to be taken apart.

**What goes away.** Entry 48's last clause; the "Outside the whole-program corollary" paragraph of AXIOMS.md. Entries 28
and 41 (emptied constructors) shrink but do not go: they also cover a user-written record built and taken apart at once
(`record_make` results in state `emptied`: 104, 135 and 2 in the three corpora; I did not trace how many of them are
inlined write-back, and in `v_mut` one is). No new assumption is needed for the call itself.

**Estimate.** Zig 25-40 h, Lean 15-25 h, parity measurement and repair 5-10 h, docs 3 h: 50-80 h. The plan's 8-14 h counted
neither the multi-result generalisation of the Lean checker nor the coupling to the ABI work. **Risk.** High. The hard stop
(a release regression above 1% on the parity suite) is at risk because the in-out ABI is where the parity work of
October went; the change touches every checker and every pass that sees a call.

## 3. Option (b): a Lean semantics for `emptied` call results

**The rule.** A call whose destination the certificate calls `emptied` *dissolves* the callee's result tree: the cells of
the returned record are destroyed in the model, and the parts the caller then takes out are fresh trees, exactly as for
an `emptied` constructor. In Lean (`ProgramDefs.lean`):

    def dissolve (h : Heap) (r : Addr) : Heap := fun x => if h x = .live r then .dead else h x
    def callVal (ctx : Ctx) (i : Inst) (v : Val) : Val := if i.res ctx = .emptied then .imm else v
    def callHeap (ctx : Ctx) (i : Inst) (h : Heap) : Val → Heap
      | .own r => if i.res ctx = .emptied then dissolve h r else h
      | _ => h

`callNext` uses `callHeap` for the heap and `callVal` for the destination, the pending takes and the held loans. Any
other call is unchanged.

**What the proof needs.** `effect_of_post` builds the `Effect` the caller's step needs from the callee's `Post`. For an
`emptied` destination it needs `Xform` with no result tree, which `Post` supplies: a cell that is outside the owned
arguments' trees stays live and is not in the result tree (`Post.frame`, `Post.fresh`); a dead cell stays dead; a
consumed or newly created cell is dead or in the result tree, which `dissolve` makes dead. `ResultOk` is `v = .imm`.
Nothing else moves: `pend`, `held` and `lent` use the result root `none`.

**Spike (not committed).** I proved this in a scratch copy of `proofs/ownership` at `23504dbb5`
(`~/.cache/selka/certs-lane2/spike-emptied/`, diffs `ProgramDefs.diff` and `ProgramLink.diff`). The changes are the three
definitions above, a new `effect_of_post_emptied` (about 70 lines), the old `effect_of_post` kept as
`effect_of_post_plain` for the other states, and a thin dispatching `effect_of_post`. `CallWf.noEmptied` is replaced by
`resEmptied` (an emptied destination implies the callee returns an owner, which the exporter already checks, entry 48).
`Program.lean` (`good_pstep`, `runs_sound`, `main_no_leak`) is unchanged and compiles; `lake build` is green in 20 s,
no `sorry`, `runs_sound` and `main_no_leak` on `[propext, Classical.choice, Quot.sound]`. The diff is 22 lines in
`ProgramDefs.lean` and 108 in `ProgramLink.lean`. This is why I expect option (b) to be small; it is also why I do not
find the proof awkward.

**What changes in Zig.** Nothing is needed for soundness. The exporter already refuses an `emptied` call whose callee does
not return an owner (`callDisagreement`, entry 48), which is the one fact the proof uses. Optional (section 6): a line of
the `ownership-proof` action that says how many programs meet every hypothesis of the corollary.

**What `CallWf` then states.** The same fields as today, `noEmptied` replaced by `resEmptied`. The call-site hypotheses of
the corollary are then: arguments in parameter order, passing modes, scalar parameters, result state follows the callee's
result, never a stack list. All are checked by the exporter (entry 48), none by the validator, since the certificate names
no callee (that is C9.2).

**A new assumption, A16 (dissolution).** The model is faithful to the program if the storage of the record a call returns
is exactly the storage of the parts the caller takes out at once, and nothing else. Three facts support it:
`Taking.empty` marks a record `emptied` only if each managed field is read exactly once in the defining block; J8
(`emptiedOk`, verified on all 1,269 `emptied` values of the first corpus) makes the same demand of the certificate;
records are by-value aggregates with no allocation of their own. It is the assumption already made for the three other
sources of `emptied` values, now stated once and extended across the call. It is **not** a Lean axiom (it is in the
definitions, like items 12 and 13 of NOTES.md); AXIOMS.md gets a row for it.

**What goes away.** Entry 48's last clause (`noEmptied` is not enforced, the corollary keeps it as a hypothesis); the
"Outside the whole-program corollary" paragraph of AXIOMS.md and the matching bullet of NOTES.md "Open gaps" for
`emptied` (the stack-list half stays: `noStack` holds by J1). Entries 28 and 41 stay unchanged: they describe the
per-function treatment, which the corollary now shares. The plan lists them under C9.4; they only go with option (a), and
then only in part.

**What stays.** A15 (forward-take views have an empty footprint) applies to the views of an `emptied` call result as it
does to those of an `emptied` constructor. Option (b) neither helps nor worsens it.

**Estimate.** Land the spike cleanly: 1 h. Docs (AXIOMS.md A16, NOTES.md, README, the header comments of `Program*.lean`)
and the proposed design-doc entry: 1.5 h. Gate run: 0.5 h. A worked example that takes the corollary through a program with
an `emptied` call (a two-function `Program` with `ProgWf` by `decide +kernel` and a proved `CallWf`), so that the theorem
is shown not to be vacuous there: 1.5-2 h. Total 4.5-5 h, 6.5-8 h with the optional census of section 6.

**Risk.** Low for the proof (the spike builds). The residual risk is the modelling one: the corollary's guarantee for these
programs is relative to A16. If a program returned a record with a managed part that the caller never takes, J8 would reject
the caller, so the model cannot lose a leak that way. The other direction (a part taken twice) is J8 as well. If a later
package gives a take a model that moves cells (A14, A15), the `emptied` call case is redone with the constructor case; that
cost does not depend on the choice made now. An alternative to dissolving, keeping the record's tree and letting each take split
off a part ("adoption"), is more faithful but needs cells per slot in the heap and a new invariant for every `emptied` value
(20-35 h); I do not recommend it.

## 4. Comparison

| | (a) IR form | (b) dissolve in the model |
| --- | --- | --- |
| `src/` change | build, own, ir, verify, emit, passes, exporter, validator | none (optional census) |
| Lean change | `dst` becomes a list (250 sites, 20 files), `Post` per part | 130 lines in `Program*.lean` (spike builds) |
| `CallWf` | arity and per-part fields, no `noEmptied` | `resEmptied` instead of `noEmptied` |
| Entry 48 last clause | goes | goes |
| Entries 28, 41 | shrink, do not go | unchanged |
| New assumption | none for calls (A-arity in `CallWf`) | A16 |
| Parity risk | high (hard stop 1%) | none |
| Hours | 50-80 | 4.5-8 |

## 5. Recommendation

Option (b). The per-function model already treats an `emptied` result as an immediate whose parts are fresh trees; the
corollary needs only to say the same of a call, and the proof of that is short. Option (a) cannot give more than (b)
for this theorem: the cells of a returned record are the cells of its parts either way, and (a) would buy "no
assumption" at the price of the call ABI and a Lean generalisation of the checker. If the IR is later changed for other
reasons, (a) can be taken up then and A16 retires for calls.

## 6. Plan if approved

1. Branch `c9/emptied-calls` from main: land the spike (`ProgramDefs`, `ProgramLink`), remove `effect_of_post_plain`'s
   duplication where possible, keep the statements of `runs_sound` and `main_no_leak`.
2. The worked example (optional), AXIOMS.md A16, NOTES.md, README, a proposed design-doc entry in NOTES.md for the
   coordinator (entry 56 or the next free number; I may not edit the design document).
3. Optional census (2-3 h): `certcheck` and `ownership_proof.py` report "programs meeting every hypothesis of the
   corollary: N of M", where a program meets them when all its functions are accepted and none is `unchecked`; the
   exporter-checked `CallWf` is the remaining trust. With it the 26%, 73% and 80% become a number the gate prints.
4. Interaction with C9.1: `ProgramLink.lean` reads `hI.acct` (in `heap_wf`), which C9.1 weakens; the two changes touch
   one line of common ground and can land in either order.
5. Gate: the complete gate and the `ownership-proof` timing, as for every Lean change.

## 7. Decisions asked of the coordinator (all four answered: (b) approved, A16 approved, census built, plan row corrected)

- Approve option (b).
- Approve A16 as a documented assumption (not a Lean axiom).
- Say whether to build the optional census.
- Strike entries 28 and 41 from C9.4's "deletes" column in the plan: option (b) keeps them.

The two corrections to the plan's C9.4 row (§7.3 of the plan): the "deletes" column names entries 28 and 41 and the `emptied`
state's constructor special cases, which option (b) keeps (they are the per-function treatment, shared by the corollary now) and
option (a) would only shrink; and the hours (8-14 in the table, 10-16 in the order list) are 4.5-8 h for (b) and 50-80 h for (a).
What goes is entry 48's last clause, the "Outside the whole-program corollary" paragraph of `AXIOMS.md` (the `emptied` half) and
the matching bullet of `NOTES.md`.

## 8. Outcome

Landed in two commits on `c9/write-back-design`: this note, and the Lean change (`ProgramDefs.lean`, `ProgramLink.lean`, the
census in `Certcheck.lean`, `ProgramExample.lean`, `AXIOMS.md` A16, `NOTES.md`, `README.md`). No file of `src/` changed.
`lake build` is green with no `sorry`; `runs_sound`, `main_no_leak` and the example's theorems depend on the three standard
axioms only. The complete gate passed.

**The census** (`certcheck` prints `summary corollary: programs meeting every hypothesis of the corollary: N of M (…)`; a
program meets them when every function of it is accepted, and the call-site agreement is the exporter's check):

| Corpus | Programs | Before C9.4 | After C9.4 |
| --- | ---: | ---: | ---: |
| gate (632 programs, release export; the debug export groups to the same 632) | 632 | 466 (74%) | 632 (100%) |
| EDA stage 2 (140 wrapper certificates of the C9.0 lane) | 140 | 35 (25%) | 140 (100%) |
| selka (`http-server` 10, `kicad-convert` 6, `markdown` 70) | 86 | 17 (20%) | 86 (100%) |

"Before" is the covered programs with no call whose value is `emptied`; it counts every such call, a runtime call included, so it
is an upper bound of what `noEmptied` excluded (it reproduces the 26%, 73% and 80% of C9.0). The Zig validator and the Lean checker give the same
verdict on all 49,846 functions of the EDA set and all 10,998 of selka's.

**Correction (2026-10-26, C9.2 review):** these counts are programs whose every function is accepted and that no `emptied` call excludes. They are not yet "every hypothesis of the corollary": `CallWf.dst` requires every call of a program function to have a destination, nothing enforces it, and a call of a program function that returns nothing (a unit function) has none, so a program with such a call is still outside the corollary. Today's certificates cannot tell program calls from runtime calls, so the size of that gap is not known yet (4 of 181 sampled `test/core` and `examples` programs have one). C9.2 drops the destination requirement, audits every hypothesis, and re-reports the census with its exact meaning.

**A finding that the census exposed.** Before the run, Lean rejected `eval_design_block::parse_board` (J1 `parentsOk`) in 24 of
the 140 EDA programs, which the Zig validator accepted: a borrowed leaf read from the `emptied` result of a call lists, as its
parent, a value in the call's `from` list (design §3, Project, R3), and the Lean rule for the parents of a projection did not know
the `from` list. `callFromOperand` (`Checker.lean`) adds it; two examples in `CheckerTests.lean` pin it (`okEmptiedFromView`,
`badEmptiedFromViewParent`). No proof changed: the proof uses `parentsOk` only to see that a parent is a `.val` that is usable.

**Evidence for A16 at run time**, as written in `AXIOMS.md` ("Evidence for A16"): the gate's leak-checked release run covers
`tests/lang`, `tests/value_semantics` and `tests/ported`, which hold 661 of the 896 emptied call results of the gate corpus
(129 programs with such a call) and report no leak; it does not cover `test/core`, `benchmarks` and `examples` (235 results), and I
did not measure which of the 661 calls actually run. So that run does not exercise "all 891" calls. Of the 37 programs outside it,
23 ran clean when run by hand with `SELKA_CORE_LEAKCHECK=1`; 12 could not be run standalone, and 2 are servers I did not run.
