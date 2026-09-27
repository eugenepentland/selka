# Certified fresh return diagnostic

The admission/cleanup proof and results are in
`docs/audits/d9-rc-fresh-return-proof-2026-09-26.md`.

`measure.py` compares immutable Debug compilers for `ecccc02c` and the fresh-return
candidate on depth-12 binary trees with actual QBE and LLVM O3/full LTO guests.
It archives median-three retired instructions, all raw samples and complete counts.
`validate.py` exercises standalone GC/RC output, arena lifetime, allocation,
arithmetic, logical frame/step and native stack-floor refusal controls.
`guests.py` exercises existing constructor/history/aggregate guest tests.

`verify-final.py` compares the measured candidate with the final compiler after
adding the explicit (currently redundant) hidden-output ABI refusal. Its receipts
record whole emitted-program and native-binary identity, so final-source evidence
does not silently reuse measurements for different guest code.

The local paths identify preserved immutable installations and binaries. This is
an isolated diagnostic; parent integration and full-corpus acceptance remain
separate. No main-branch update or push is part of this experiment.
