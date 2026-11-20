# The IR verifier in Lean (lane VL, 11 November 2026)

A Lake project, core Lean 4 only (no Mathlib), that holds **a copy of the Core IR verifier** (`src/core/verify_ir.zig`)
written from what each rule is meant to guarantee, and the differential that compares the two. Lean is a developer and
gate tool only: it is never in the install graph and never spawned from `src/`; building and using selka still needs
only Zig. The toolchain is the one of `proofs/facts` and `proofs/ownership` (`lean-toolchain`, Lean 4.35.0).

The two large proofs take what the verifier checks as hypotheses: `proofs/facts` takes SSA (`ModWf`, H2) and the typed
machine (TY1 to TY3), `proofs/ownership` takes A17 (a function value points to a function of its type's signature). This
copy discharges them for itself: `VerifyIr.modWf_of_verdicts` proves `ModWf` of a build's fact certificate when the
checker accepts the build's final IR and the certificate is the IR's translation, and `VerifyIr.a17` proves A17 under a
small semantics of function values. What stays trusted is in `AXIOMS.md`.

```sh
export PATH="$HOME/.elan/bin:$PATH"
cd proofs/verify_ir
lake build                              # the checker (about 10 s cold)
lake exe irverify DIR_OR_FILE           # one verdict per function, as `selka verify-ir` prints
lake exe irverify --strict DIR_OR_FILE  # plus the candidate rules the Zig verifier does not have
lake exe irverify --facts DIR           # each program's fact certificate is the translation of its IR
python3 scripts/verify_ir_proof.py --compiler zig-out/bin/selka --certificates DIR   # the differential (from the root)
```

## The input: `core-ir-v1`

`--emit-certificates DIR` (the flag the language gate's runs pass) writes, beside each program's ownership and fact
certificates, the program's final IR as `program.core-ir` (`src/core/ir_text.zig`): the compound type table, then each
function's name, span start, loop count, signature, instruction table (every field raw), packed operand list and blocks.
The same build that wrote it verified the module in memory (a Debug compiler always does), and `selka verify-ir`
reads the text back into an `ir.Module` and runs the same Zig verifier on it, so both checkers judge exactly the same
input. The export is written only for `--emit-certificates`, which builds with no cached stage; it never enters a stage
or replay record.

## The verdicts

```
FILE types accept | FILE types reject RULE
FILE NAME accept | FILE NAME reject RULE bB %I      (b- and %- when the failure names no block or instruction)
FILE error line N: REASON
summary files=.. functions=.. accept=.. reject=.. errors=..
```

Each function is judged on its own: its declaration's rules, then, with a body, the body's in the Zig verifier's order
(structure; every constant of the table; then per listed instruction of a reachable block, its signature, the copy rule
and dominance), and the first rule broken is named. `RULE` is the class name `NOTES.md` tabulates; the Zig command
derives it from the verifier's reason (`ruleOf` in `src/core/verify_ir_commands.zig`). A module whose type table is
refused gets its `types` line only.

## The differential and the gate action

The gate action `verify-ir-proof` (`build.zig`) runs `scripts/verify_ir_proof.py --gate`: `lake build`, then both checkers over every `program.core-ir` of the corpus (they must print
the same lines, all acceptances), then over the single-rule mutants of `scripts/verify_ir_mutants.py` (they must print the
same lines, and the mutated function must be refused for the class's rule), then `irverify --facts` over every program
(each fact certificate must be its IR's translation; a changed fixture must be reported), then the same over the C
interop programs it builds. Measured on 11 November over the three
language suites' debug builds: 443 programs, 18,887 functions, identical verdicts; 46 mutation classes, 270 mutants,
identical verdicts. See `NOTES.md` for the rule table, the classes and the findings.

## Files

| File | Content |
| --- | --- |
| `VerifyIr/Types.lean` | the IR as the verifier reads it: types by number, compounds, signatures, instructions, blocks; passing conventions |
| `VerifyIr/Parse.lean` | the reader of `core-ir-v1` |
| `VerifyIr/TypeOps.lean` | what a type is in a module (`valid`, `storageType`, `managed`, `containsBorrow`, `validBorrow`, `pathTarget`, ...) |
| `VerifyIr/Rules.lean` | the typing rule of each operation (`sigOk`), the view rules, the probe rule |
| `VerifyIr/Check.lean` | the checker: module, header, structure, the verified dominator tree, signatures, dominance; the `--strict` candidates |
| `VerifyIr/Ssa.lean` | the skeleton of a fact certificate, the translation from the IR, the SSA rule on a skeleton, `translatesB` |
| `VerifyIr/SsaProof.lean` | `ssaWf_of_check`, `modWf_of_verdicts`: the SSA rule gives `Facts.SsaWf`, so a checked build meets H2 |
| `VerifyIr/FnValues.lean` | the function-free table, values, `Holds`, `Part`, `Built`, the typing check, `verdict` |
| `VerifyIr/FnProof.lean` | `Reaches` (the small semantics), `reaches_holds`, `a17` |
| `VerifyIr/Audit.lean` | `#assert_axioms` over the theorems |
| `Main.lean` | `lake exe irverify` |
| `AXIOMS.md` | what the theorems prove and what is trusted (the development declares no Lean `axiom`) |
| `NOTES.md` | the rule table, the mutation classes, the deviations and the findings |
