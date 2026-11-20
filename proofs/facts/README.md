# Fact certificates in Lean (package C7.3)

A Lake project, core Lean 4 only (no Mathlib), that holds **the checker of fact certificates** and **the proof that
a certificate it accepts is sound**. Lean is a developer and gate tool only: it is never in the install graph and
never spawned from `src/`; building and using selka still needs only Zig. The toolchain is the one of
`proofs/ownership` (`lean-toolchain`, Lean 4.35.0). `proofs/arith` (package C8) is a Lake path dependency: the
proven forms' facts are the hypotheses of its lowering theorems.

```sh
export PATH="$HOME/.elan/bin:$PATH"
cd proofs/facts
lake build                              # the checker, the proofs, the axiom audit (about 25 s cold)
lake exe factcheck DIR_OR_FILE          # one verdict per function, as `selka validate-fact-certificates`
lake exe factcheck --census DIR         # how much of a corpus rests on each kind of acceptance
lake exe factcheck --reductions DIR     # every reduction phi accepted (the open assumption), by what its derivation needs
sh fixtures/check.sh                    # the fixtures' verdicts
```

`factcheck` reads `fact-certificate-v1` files (design `docs/design/fact-certificates.md` section 10) and prints

```
FILE NAME accept
FILE NAME reject F2 b3 %17        (the check, the block or b-, the value or -)
FILE error line N: REASON         (a malformed file)
summary files=.. functions=.. accept=.. reject=.. errors=.. derived=.. assumed=.. proven=.. unchecked=..
```

so that its output can be compared line by line with the Zig validator's (`src/core/validate_facts.zig`). On the
13,200 functions of `tests/lang` the two agree on every line and on the summary.

## The gate

`scripts/fact_proof.py` (the facts half of the gate action `ownership-proof`, `scripts/ownership_proof.py`) runs `lake build` in
this project and compares the Lean checker with the Zig validator over the certificates the language gate's release run
wrote: they must print the same line for every function and the same summary. It does the same over the single-edit
mutants of `test/fixtures/fact-proof/` (which the validator must reject in the function they edit), and checks the verdicts
on `fixtures/` against the `.expected` beside each. The action declares `proofs/facts/` and `proofs/arith/` as inputs
(`build_test_inputs.zig`), so an edit to either reruns it and nothing else does. `python3 scripts/fact_proof.py --compiler
zig-out/bin/selka` runs it alone.

## What is proved

`Facts/Theorem.lean`, `fact_certificates_sound`: if the checker accepts every function of a module and the IR
verifier's rule holds (every use is dominated by its definition), then every execution from an external entry, with
arguments in the stated parameter intervals, that honours the assumptions of `AXIOMS.md`, satisfies at every
configuration it reaches

1. **intervals**: every integer or boolean value of every frame lies in the interval stated for it and in its type's
   range;
2. **reachability**: no block stated dead is entered;
3. **proven checks**: no instruction accepted as `proven` is undefined behaviour (the failing case of its unguarded
   form never arises). `Connect.lean` instantiates the emitter's lowering theorems of C8 (`proofs/arith`) with the facts
   this gives, so for such an instruction the emitted sequence computes what the machine computes (`lower_div`,
   `lower_shift`, `lower_convert`, `lower_arith`).

The model is a small-step machine over the certificate's IR (`Sem.lean`): mathematical integers, lists and opaque
values; blocks with phis, instructions and terminators; direct calls with a call stack; and the three forms of design
section 4 (`none` wraps, `exact` traps, `proven` is undefined behaviour out of range). The machine knows nothing of
facts.

## Files

| File | Content |
| --- | --- |
| `Facts/Types.lean`, `Parse.lean` | the Lean image of `fact_function.zig` and the parser of the text format |
| `Facts/Prep.lean` | the definitions table, the list facts, the dominator tree and its verification (`structOK`, `domOK`) |
| `Facts/View.lean` | the view of a value at a block: the base interval, branch refinement, fill caps, reachability (design 5.1-5.2) |
| `Facts/Rules.lean` | the transfer rule of each operation, counted loops and reductions (design 4, 5.5) |
| `Facts/Run.lean` | list facts, F6, F7, and `checkModule`: the checks in the validator's order |
| `Facts/Sem.lean` | the machine |
| `Facts/Dom.lean`, `Wf.lean`, `Avail.lean`, `Static.lean` | walks and true dominance, what the verified structure gives, SSA availability |
| `Facts/IntLemmas.lean`, `ViewSound.lean`, `Trans.lean` | the integer lemmas, the soundness of views and refinement, the transfer rules |
| `Facts/EnterRegs.lean`, `Reinterpret.lean`, `Accept.lean` | phi entry, the F6 reinterpretation, what an accepted function gives |
| `Facts/ListDefs.lean`, `ListDerive.lean` | the stated list facts, and that every list operation derives a sound one |
| `Facts/Chain.lean` | the reductions by accumulator chains and joins: `jGrowth`, `ChainInfo`, `ChainBound`, `ChainProved` |
| `Facts/Inv.lean` | the frame invariant (`FrameInv`), the assumptions (`AdmFrame`), and its preservation by every step |
| `Facts/Sound.lean` | the invariant holds along every honest execution; intervals and dead blocks |
| `Facts/Proven.lean`, `RowFacts.lean`, `Connect.lean` | no `proven` instruction is undefined behaviour; the link to C8 |
| `Facts/Theorem.lean` | the theorem |
| `Facts/Census.lean`, `ChainLink.lean` | `factcheck --census` and `--reductions`; the census count implies `ChainProved` |
| `Facts/Check.lean` | `#assert_axioms`: the build fails if a theorem uses an axiom beyond `propext`, `Classical.choice`, `Quot.sound` |
| `AXIOMS.md` | what the theorem assumes (the development declares no Lean `axiom`) |
| `NOTES.md` | where the Lean checker differs from the Zig validator, and the findings |
| `fixtures/` | twelve small certificates with their expected verdicts (`fixtures/check.sh`) |

## How the checker and the proof fit

The checker is a Lean function (`checkModule`) written to mirror `validate_facts.zig` rule by rule. Some of what it
computes is found by imperative code (the dominator tree, the reached set); the proofs never use that code. Each such
result is *verified* by a total Boolean function (`domOK`, `reachOK`, `structOK`) the proofs use, so a wrong
computation can only make the checker reject. Every fuel-bounded recursion (views, growth) is written with fuel; the
proofs hold for every fuel, and the checker runs with fuel for the whole tree.
