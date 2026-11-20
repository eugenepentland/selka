# What the Lean copy of the IR verifier rests on

**The development declares no Lean `axiom`.** `VerifyIr/Audit.lean` runs `#assert_axioms` (from `proofs/facts`) over the
two theorems and their pieces in the build: it fails unless each depends on nothing beyond `propext`,
`Classical.choice` and `Quot.sound`. There is no `sorry`. `#print axioms` (11 November 2026):

```text
'VerifyIr.modWf_of_verdicts' depends on axioms: [propext, Classical.choice, Quot.sound]
'VerifyIr.a17' depends on axioms: [propext, Quot.sound]
'VerifyIr.payload_of_verdict' depends on axioms: [propext, Classical.choice, Quot.sound]
```

## What is proved

* **H2 of `proofs/facts`** (`modWf_of_verdicts`, `SsaProof.lean`): if the checker's `verdict` accepts every function of
  a module `mI` and the fact certificate `mF`'s skeletons are the translations of `mI`'s functions (`translatesB`), then
  `Facts.ModWf mF`, the hypothesis `hwf` of `Facts.fact_certificates_sound`, exactly as `proofs/facts` defines it. The
  correspondence between the two forms of a function (the certificate has `pre`, phis apart from instructions, no
  copies, and positions that exclude phis and copies) is the definition `Fn.translate`; the proof goes through it and
  `Facts.CtxOK`, whose definitions table, edges and phi edges `prepare` verified.
* **A17 of `proofs/ownership`** (`a17`, `FnProof.lean`): if the checker accepts every function of a module, then under
  the small semantics of function values (`Reaches`) the callee of every `call_indirect` in a reached block holds
  `fn k` for an internal function `k` whose signature is the callee's type, whose result is the call's type and whose
  parameters are the types of the call's arguments (`reaches_holds`: every value a register can hold is well typed).

* **The union-tag rule** (`payload_of_verdict`, `SsaProof.lean`, from `payload_under_tag`, `TagProof.lean`; F-VL-10): in a
  function the checker accepts, every run of the tag semantics (`Exec`, `BlockStep`: V9) that runs a block and reads
  there, by a `union_payload k` or `union_take k`, a value that is not a `list_get` (shape M) holding a union value of case
  `j`, has `j = k`, whether the facts justify it through the value's own tests, a `record_get` twin (R), a stored field
  (S) or a merge of known cases (P). The proof reads the verified check `Fn.tagOK` (the analysis's entry facts, re-checked edge by edge,
  and the homes it reads, re-checked against the listing), not the fixpoint iteration that computed them.

The proofs read, of the checker's verdict, only its three declarative checks (`Skel.ssaCheck` on the translation, and
`Fn.typedCheck` with the verified function-free table `Module.freeOK`, and `Fn.tagOK`), not the imperative mirror of the Zig rules. Of
the operation signatures they read only those of `func_ref`, `param`, `text_sentinel`, the constants made from nothing,
`call`, `call_indirect` and `ret`.

## What is trusted, and how each item is checked

| # | Trusted | Checked by |
| --- | --- | --- |
| V1 | The text is the module: `core-ir-v1` (`src/core/ir_text.zig`) writes every field the verifier reads and reads back into a module the Zig verifier judges as it judged the original. | The round-trip test in `ir_text.zig`; the Debug compiler that wrote each corpus text verified the module in memory, and `selka verify-ir` accepts every text read back. |
| V2 | The text is the final IR: rendered where the certificates are, from the module the passes and emission leave, in a build with no cached stage. | `pipeline.zig` (`certificateFiles`). |
| V3 | The Lean checker's verdict is the Zig verifier's: the theorems are about the Lean checker; the build runs the Zig one. | The differential (`scripts/verify_ir_proof.py`): identical lines on the corpus (443 programs, 18,887 functions) and on every mutant (294 in 50 classes, 11 November). The two Lean-only checks (`ssa-skeleton`, `typed`) never refuse what the mirrored rules accept there. |
| V4 | The rules the copy does not mirror (`build_equality.validateModule`, the three marker declarations, the marker calls in a call's signature, `borrow_result.valid`) are not needed. | The proofs use none of them (above); each only refuses more. |
| V5 | The exported fact certificate's skeleton is the translation of the exported IR (`translatesB`): `fact_export.zig` describes a function as `Fn.translate` does. | `irverify --facts` over the corpus: 18,887 functions, no mismatch (11 November). Not proved of the Zig exporter. |
| V6 | Every operation other than a function reference, a constant, a parameter and a call builds its result from parts of the values its operands hold, at the types the parts have (`Reaches.built`, `Built`, `Part`): the runtime and emission are type safe, as `proofs/facts` takes for its machine (TY1). | Not checked; the typing rules the copy states (`sigOk`) are what make an operation's result type the type of the parts it moves. |
| V7 | **A build does not refuse on the union-tag rule; the gate does** (the user's decision of 11 November, D-VL-18: a build's verifier counts an unjustified read and prints the count under `--stats`; the `verify-ir-proof` action refuses it through `selka verify-ir` and `irverify`, so a program the gate never sees can run with a read the rule does not justify). A payload read in the A17 semantics reads its own case: `Reaches` builds a `union_payload k` or `union_take k` result from `Part.payload` of the operand's value `.tagged j p`, at its case type `cs[j]`, and A17 needs `j = k`. Narrowed (V4) to a modelling step: `Reaches` over-approximates values flow-insensitively, with no run and no tag test, so it cannot itself restrict its payload step; the restriction holds for the runs of the tag semantics (V9), where `payload_of_verdict` proves `j = k` for every read the rule justifies. That the values `Reaches` gives a payload read are values such a run gives it, and that the shape M reads (the `list_get` values the rule lets through) read their own case, is not proved. | `payload_of_verdict` (a Lean theorem, of the tag semantics); the verifier refuses every other unjustified read (`union-tag`, in `verify_ir.zig` and the Lean copy, five mutant classes); the action prints the shape M count and fails above its ceiling (`SHAPE_M_CEILING`, 10 in the corpus). The lowering emits a tag test before each read; for shape M the test is of the list element's tag (`list_get_field`) and the read of the element (`list_get`), which only alias reasoning ties (`experiments/verify-ir-lean-20261111/DECISIONS.md`). |
| V8 | The runtime returns, and passes to the functions it calls back through pointers (`map`, tasks, registered tests), values built from parts of values it was given (`Reaches.external`, `Reaches.callback`). | Part of A5 of `proofs/ownership` (external functions satisfy their signatures' contracts); the runtime's deep copies (`myl_core_owned_copy_*`) copy function pointers bitwise. |

| V9 | **A build does not refuse on the union-tag rule; the gate does** (as V7). The tag semantics (`TagProof.lean`) is the run of a function as far as tags go: a block changes only the instructions it lists; a copy or overlay is the value it forwards (`canonical`); an instruction reads the values its block holds at the block's end (SSA within a block), except a `phi`, which is the value one of its operands held at the block's entry; a `union_make` makes its case, a `union_tag` reads its value's case, a `record_get` reads a field of a record value, a `record_set` makes the record with one field replaced, a `cmp eq|ne` compares the naturals its operands hold and a branch goes to the side its condition (1 or 0) names; a register's value fits its type (a union value's case is below its case count, a `list_get_field` of a tag path reads a case of that union: the run time's type safety, as TY1 of `proofs/facts`). | Not checked; the definitions are short (`RVal`, `Defines`, `Typed`, `BlockStep`, `Takes`, `Exec`). Every other register a block lists may hold any value of its type (calls, loads), so the semantics is weaker than the machine's, not stronger. |

The facts machine's typing (TY1 to TY3 of `proofs/facts/AXIOMS.md`) is a definition of its step relation, not a
hypothesis of its theorem, so no statement of it is discharged here. What the verifier contributes to it (operand types)
is `typedCheck` over every reached instruction, and `proofs/facts` checks the parts its rules read itself (`typedOK`,
`paramsOK`).

Not covered: `verifyPlan` (vector plans are not exported) and `writtenCopies` (rule C; not part of `verifyModule`).
