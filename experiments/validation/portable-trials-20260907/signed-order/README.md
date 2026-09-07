# Signed composite ordering readiness fixture

Untimed reusable standard-library verification; no planner-specific algorithm or
compiler change. Runs the embedded `std_order` implementation in the installed VM.

The fixture assigns payload IDs to `(signed primary, ASCII secondary)` keys:

| ID | Primary | Secondary |
|---|---:|---|
| 0 | -1000 | z |
| 1 | 0 | z |
| 2 | 1000 | a |
| 3 | -1000 | a |
| 4 | 0 | a |
| 5 | 1000 | z |
| 6 | 0 | aa |

Independent ascending lexicographic expectation is `3,0,4,6,1,2,5`:
negative priorities precede zero and positive priorities; ties compare ASCII
secondary text, including the prefix relation `a < aa < z`.

Heap operations push 2,1,0; pop 0; push 4,3; pop 3,4; push 6,5;
then pop 6,1,2,5. Thus the independent interleaved pop sequence is
`0,3,4,6,1,2,5`. A later negative insertion must become the next minimum even
after an earlier negative minimum was removed. The active heap visits odd and
even sizes, and an empty pop must report not found. The same storage is reused
after sort with the heap count explicitly reset to zero.

Both expected sequences are literals in the fixture, not generated using the
implementation under test. Successful execution prints `42`; distinct negative
return values identify failures.

Validation command (from repository root):

```sh
/home/epentland/ai/canopy/mylang/zig-out/bin/mylang run-project experiments/validation/portable-trials-20260907/signed-order/main.my
```

Observed exit 0 and stdout `42\n`. Executable and source SHA-256 values are
retained in `receipt.json`; raw stdout is `vm.stdout`. This is a functional
readiness check, not a development-time or application-performance comparison.
