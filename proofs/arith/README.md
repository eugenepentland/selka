# Arithmetic lowering proofs (package C8)

A Lake project, core Lean 4 only (no Mathlib), that proves the compiler's LLVM lowering of a few
integer operations computes what the language says. **Lean is a developer and gate tool only**: it
is never in the install graph and never spawned from `src/`; building and using selka still needs
only Zig. The toolchain is the one of `proofs/ownership` (`lean-toolchain`, Lean 4.35.0, see
`../ownership/README.md` for the install commands).

```sh
export PATH="$HOME/.elan/bin:$PATH"
cd proofs/arith
lake build                                   # the proofs, the axiom audit
lake exe arith-templates --check templates.txt
lake exe arith-templates --md FORMULAS.md
lake exe arith-templates > templates.txt     # regenerate after changing Arith/Formulas.lean
lake exe arith-templates --update-md FORMULAS.md
```

## What is proved

For `div`, `rem`, `floor_div`, `floor_rem`, `shift_left`, `shift_right`, `convert`, `float_to_int` and
`saturating_add`, at the widths 8, 16, 32 and 64 and both signednesses: the instruction sequence the
emitter prints, with its trap tests and fix-ups, **equals the operation's mathematical specification on
`Int`** (`Spec.lean`). Each theorem is an equality of outcomes, `formula a b = spec a b`, where an
outcome is `ok r`, `trap kind`, or one of the two ways LLVM can go wrong (`ub`, `poison`). So one
statement says three things: the result is the specified one when the specification does not trap, the
sequence traps exactly (and with the specified kind) when the specification says, and `ub` and `poison`
are never reached. The forms that depend on the compiler's facts (`check = proven`) are proved under the
fact as a hypothesis, which `facts.zig` establishes; see `FORMULAS.md`.

## Files

| File | Content |
| --- | --- |
| `FORMULAS.md` | the formulas: each emitted sequence, the specification, the emitter's line references, the theorems |
| `templates.txt` | the formulas rendered as LLVM text, 409 cases, compared with the emitter by `src/core/arith_lowering_test.zig` |
| `AXIOMS.md` | what the theorems assume (the development declares no Lean `axiom`) |
| `Arith/Basic.lean` | `ival`, `lo`, `hi`, `inRange`: reading a bit vector as an integer |
| `Arith/F64.lean` | the binary64 model (NaN, infinities, rationals), its comparisons and its decoding from bits |
| `Arith/Isa.lean` | the abstract instruction set the formulas are written against |
| `Arith/Exec.lean` | LLVM's semantics of the instructions on `BitVec n`, with undefined behaviour and poison explicit |
| `Arith/Print.lean` | the same instructions rendered as the text the emitter prints |
| `Arith/Formulas.lean` | the lowering formulas, one definition per emitted sequence |
| `Arith/Spec.lean` | the specifications |
| `Arith/IntFacts.lean`, `BVFacts.lean` | integer and bit vector lemmas |
| `Arith/DivUnsigned.lean`, `DivSigned.lean`, `DivProven.lean` | division and remainder |
| `Arith/Shift.lean`, `SatAdd.lean`, `Convert.lean`, `FloatToInt.lean` | shifts, saturating addition, conversion, float to integer |
| `Arith/Coverage.lean` | every theorem instantiated at each emitted width |
| `Arith/Templates.lean`, `Main.lean` | the case enumeration and `lake exe arith-templates` |
| `Arith/Check.lean` | `#assert_axioms`: the build fails if a theorem uses an axiom beyond `propext`, `Classical.choice`, `Quot.sound` |

## How the proof is tied to the emitter

The formulas are written once, against the abstract instruction set `Isa`. Giving the instructions
LLVM's semantics (`Isa.exec`) makes them something to prove things about; giving them a text rendering
(`Isa.print`) makes them the template the Zig test compares the emitter with. A formula that does not
match the emitter fails that test; an emitter change that does not match a formula fails it too. The gate
action `arith-proof` (`scripts/arith_proof.py`) runs `lake build` and checks `templates.txt` and the
generated blocks of `FORMULAS.md` are what Lean renders.
