# What the fact-certificate theorem assumes

**The development declares no Lean `axiom`.** `Facts/Check.lean` runs `#assert_axioms` over the headline theorem and
the lemmas it rests on, in the build: it fails unless each depends on nothing beyond `propext`, `Classical.choice` and
`Quot.sound` (the axioms `simp`, `omega` and `decide` use). A `sorry` (`sorryAx`) and `native_decide`
(`Lean.ofReduceBool`) are therefore refused. There is no `sorry` in the project.

What the theorem does assume is below. Each item is a definition of the model (true of the model by construction,
false of the real system only if the model is wrong), a hypothesis of the theorem, or a clause of `Adm` (`AdmFrame` in
`Inv.lean`), the assumptions an execution must honour. The design's list is section 8 of `docs/design/fact-certificates.md`;
the column "design" maps this list onto it.

## The model

| # | Assumption | Where | Design |
| --- | --- | --- | --- |
| M1 | Integers are mathematical; the three forms of an arithmetic operation are as design section 4 says: `none` wraps modulo the type, `exact` traps when the exact result is outside the type, `proven` is undefined behaviour then. The same for the shift count outside `[0, bits)`, a zero divisor and an out-of-bounds access: a checked one traps, any other is undefined behaviour. Division and remainder are the truncating and flooring ones of `Int`; `bit_xor` is the exclusive or of the two's complement bits; `saturating_add` clamps. | `Sem.lean` (`evalOps`) | A1 |
| M2 | A list is a `List` of values; `list_push` traps when the length would exceed `M = 2^47`; `list_copy`, `list_view_of` and `borrow` give the same list (a view is a whole-list view); `record_make` of type `list` builds the list of its operands' values; `array_get`/`array_set` act on a list. | `Sem.lean` | A2 |
| M3 | A call to a function with a body runs that body in a new frame with the arguments passed by value (a missing one is an opaque unit); the callee's return value is the register its `ret` names. A parameter takes the argument's bits at the parameter's type. | `Sem.lean` (`Step.call`, `Step.ret`, `paramVal`) | section 6 |
| M4 | Any other operation (the ones the checker has no exact model of) returns *any* value its type allows, except that `str_len` and `dict_entries` are in `[0, M]`. A call to a function without a body is such an operation. | `Sem.lean` (`Allowed`) | A6 |
| M5 | Execution is a sequence of steps of the machine; a trap ends it and is excluded from the theorem (a failing checked operation traps as in a debug build). | `Sem.lean` | section 7 |

## Typing (the machine is typed)

The IR verifier checks the signature of every operation and the runtime is type safe; the model takes this as
given by making the step relation *typed*:

| # | Assumption | Where |
| --- | --- | --- |
| TY1 | The value a step produces has the instruction's declared type (`ValTy`): an integer in the type's range, a list of at most `M` elements, or an opaque value. This includes a constant fitting its type, and the value a callee returns fitting the call's type. | `Step.inst`, `Step.ret` |
| TY2 | A fixed array has the length its type declares (`aux` of the access) (`ArrayTy`). | `Step.inst`, `StepUb.inst` |
| TY3 | A comparison and the other integer operations read integer registers, a list operation reads a list register: a step on an operand of the wrong kind has no result (it is `stuck`, not a step). | `evalOps` |

## Hypotheses of the theorem

| # | Assumption | Where | Design |
| --- | --- | --- | --- |
| H1 | `ModOK m`: the checker accepts every function of the module. | `fact_certificates_sound` | the theorem |
| H2 | `ModWf m` (`SsaWf`): every use is dominated by its definition, a phi operand at the end of its predecessor, a branch condition and a returned value at the end of their block, in the blocks the verified tree reaches. **Proved for the Lean copy of the IR verifier** (`VerifyIr.modWf_of_verdicts`, `proofs/verify_ir/VerifyIr/SsaProof.lean`): when that checker accepts every function of the build's final IR and the certificate's skeleton is the translation of that IR (`translatesB`), `ModWf` holds of the certificate. Trusted: that the copy agrees with `verify_ir.zig` (the differential of `scripts/verify_ir_proof.py`) and that the exporter's certificate is the translation (checked over the gate's corpus by `irverify --facts`, not proved of `fact_export.zig`); `proofs/verify_ir/AXIOMS.md` V1 to V5. | `Avail.lean` | proved for the Lean copy; the differential |
| H3 | The entry's arguments satisfy the stated parameter intervals (`ArgsOK`). The stated interval of a parameter exists only for an `internal` function that is not address-taken; any other function states none (`entry_args`). For a call inside the module the arguments are the ones F6 checked (`call_args_ok`), so this is the assumption about the *external* entry only. | `Inv.lean` | A3, A4 |

## `Adm`: what an honest execution is asked to honour (the facts accepted without a derivation)

These are the "assumed" outcomes of the checker (`factcheck` prints their number as `assumed=`; `factcheck --census`
splits them). Each says that a value the checker accepted on trust has the stated property. The theorem proves
everything else from them.

| # | Assumption | `Adm` clause | What would close it | Design |
| --- | --- | --- | --- | --- |
| A6.1 | The stated interval of the result of an instruction the checker has no rule for (field and record reads such as `record_get` and `list_get_field`, `float_to_int`, dictionary reads, `undef`, the `take` family, and the other opaque operations) holds. Also the stated interval of a `list_get`, `array_get` or `call` result whose derived interval is not within the stated one (the facts rewrote the list after the instruction was derived, `staleAfterFacts`). | `stated` | A rule for the operation (design section 9); for the stale ones, a derivation that reads the list's facts at the right program point. | A6 |
| A6.2 | A phi accepted by a *reduction* (design 5.5; not by the hull of its operands, not as a counted loop's counter) whose growth passes an **inner counted loop** (or whose counter's bound is wider than its type) stays in its stated interval. The reductions whose growth is a chain of checked additions and subtractions of the accumulator, with joins, are **proved** (`ChainProved`, `FrameInv.red`, `FrameInv.jn`). In `tests/lang`: 12 of 152 reduction phis remain. | `phi` | The same invariant for the inner loop's phi, relative to the accumulator (`NOTES.md`, "Reductions"). | 5.5 (a derived rule in the design; its proof is the open item) |
| A2 | A fill cap (`value <= M` in the blocks the exit of the fill loop dominates) holds: the runtime allocates what the builder asked for and the fill pushes once per iteration. | `caps` | The fill-list pattern validation (design 6.2) as a derived rule. | A2 |
| A6.3 | A stated length or element interval of a list value *with no derivation* holds: the list is a parameter, a call result, the result of an operation `Ctx.deriveList` does not know, or the derivation does not give that component (`LenAssumed`, `ElemsAssumed`). For every other list value the facts are **proved** (`ListDerive.lean`). | `listLen`, `listElems` | Derivations for the missing operations; the facts of a parameter or a call result as F6 facts. | A6 |
| A5 | A call to a function *without a body* returns within the interval that function states for its return. | `calls` | Nothing inside the module: a function without a body is `extern` (C interop or the runtime), so its stated return interval is a contract with that code. For a function *with* a body the proof uses F6 at its `ret` (`ret_claim`) and assumes nothing. | A3, A6 |

The counted loops' counters are **proved**, not assumed (`counter_enter`): the interval of a counter at its header
holds by induction over the entry edge and the back edge. So are the reductions by accumulator chains and joins (`chain_next`, `jEdges_spec`). List facts (lengths, element intervals) of every list a
list operation, a view or a phi derives are proved (`inst_lst`, `phi_lst`, `init_lst`).

## Checked, not proved

| # | Assumption | Where |
| --- | --- | --- |
| E1 | The Lean checker is the Zig validator: that `Facts/Rules.lean` and `Run.lean` mean what `validate_facts.zig` means is checked by running both on the same certificates (the 13,200 functions of `tests/lang`, the fixtures, the mutants) and comparing every verdict and every statistic. Lean checks *more* than the validator in places (`NOTES.md`, section "Deviations"); where it does, a certificate the Zig validator accepts and Lean rejects is a finding, not a disagreement of semantics. | `lake exe factcheck`, the gate action |
| E2 | The emitter emits the three forms (design A1) and the other readers use a fact only where design 1.1 says (A5). C8 proves the lowering formulas; the readers are tested. | `proofs/arith` |
| E4 | A `proven` signed constant addition or subtraction that the checks on every edge into its phi's block make safe (design change 16, reason `edge-checked`) is counted, not validated: its unguarded form rests on the argument of `overflow_edges.zig` (that two reads of one field of one record are one value is that pass's alias analysis). The theorem says nothing about such an instruction. | `Ctx.edgeChecked` |
| E3 | Every pass that changes the IR after the facts preserves each fact: covered by the certificate being of the *final* IR. | design 8 A5 |

## Not covered

* Floating-point values (`f64`): they are opaque; `float_to_int` is an unmodelled operation (A6.1).
* Dictionary, record-field and string contents: opaque values; their lengths are `strLen`/`dictEntries` reads (A6.1).
* Concurrency (`parallel.group`, tasks): the machine is sequential.
* The traps' messages and the values a diagnostic prints.
