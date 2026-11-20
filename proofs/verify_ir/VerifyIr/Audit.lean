import Facts.Check
import VerifyIr.SsaProof
import VerifyIr.FnProof

/-!
# Axiom audit

`#assert_axioms` (from `proofs/facts`, `Facts/Check.lean`) fails the build unless each named constant depends only on
`propext`, `Classical.choice` and `Quot.sound`. A `sorry` and `native_decide` are refused. The development declares no
`axiom`; `AXIOMS.md` says what the lemmas assume instead.
-/

namespace VerifyIr

#assert_axioms
  -- H2 of `proofs/facts` (`ModWf`) for a checked build
  modWf_of_verdicts modWf_of_skeletons ssaWf_of_check ssaCheck_of_verdict
  -- A17 of `proofs/ownership` (a function value at an indirect call points to a function of the call's signature)
  a17 reaches_holds holds_fn built_holds part_holds free_of_storage
  -- the pieces
  avail_of_availS tdom_of_walkUp walk_reached reached_of_reach
  -- F-VL-10: a payload read the union-tag rule justifies sees its own case, on every run of the tag semantics
  payload_of_verdict payload_under_tag tagOK_of_verdict exec_inv edgeTest_holds step_inv fresh_killed homes_exact
  -- the checker is a function, so its verdict is computed
  verdict translatesB

end VerifyIr
