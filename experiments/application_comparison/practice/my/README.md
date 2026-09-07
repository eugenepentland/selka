# .my practice construction

`starter/` is participant-visible draft practice material for
`../../contracts/practice-v1.md`. `solution/` is coordinator-only and must never
be included in a participant snapshot or tool mount. No pilot task, application
baseline, oracle, or other-language implementation was consulted to author it.

The starter differs from the corrected `main.my` at exactly three expressions:
the helper argument, the failed-parse branch result, and the undefined identifier
in the diagnostic branch. Its named constant uses an immutable `let` binding.
Parsing is a typed result with an exhaustive success/failure match. Both versions
share the same local `helper.my` and raw-byte `io.my` declarations.

Run from the language checkout without any Zig build or Guardian invocation:

```sh
python3 experiments/application_comparison/practice/my/solution/check_practice.py \
  --host zig-out/bin/mylang-io
```

Construction verification passed 28 raw CLI cases, including all digits, invalid
UTF-8, exact input shape and 256/257-byte boundaries. The unmodified starter
fails with located `E_UNKNOWN_NAME` and emits no stdout. A temporary copy fixing
only that name returns 36 for `m`, 0 for `fx`, and the correct results for `d`
and `f7`. Fixing the remaining two expressions produces the exact solution
source. Starter files are never modified by verification.

The installed host accepted these source files directly. No host or language
changes were required. These checks are construction evidence, not timed
participant data or proof of onboarding equivalence; review and calibration
remain necessary.
