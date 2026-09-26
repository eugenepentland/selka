# Trapping file-open error ownership

`myl_qbe_file_access` returns one owned managed error string on an ordinary
provider refusal. The `Result` caller publishes that text; the trapping
`with open(...)` caller formerly checked status and unwound without publishing
or releasing it. The QBE emitter now construction-aborts that fresh text on the
error branch before reporting the unchanged `R_FILE`. Success holds a raw
unique resource handle, so the cleanup must not execute on that branch. Arena
products use construction abort as well.

The frozen pre-fix Debug compiler SHA256 is
`4e3cc120f065f63ecb3e8b75ce22c37582c1c4ba623a70853898d8063fd1aedb`.
`before.json` preserves the actual missing-file reproduction: one allocation,
zero retirements, zero owner releases, and the expected located trap.

The fixed Debug compiler SHA256 is
`67bd09043385969dddd1f07e87e9eb1394f8d28e20fa2b848bfcc939a1a0a7c1`.
The focused `open ` unit selection passed 18/18 tests, including both new
ownership checks and existing file behavior. Debug installation and Guardian
passed. The first install caught a test helper's hardcoded testing allocator;
the helper now accepts that allocator explicitly. The first arena test source
had an unreachable trailing return, which was corrected before validation.

Run `run.py COMPILER WORK_DIRECTORY` from this directory or elsewhere to replay
the 28 authoritative file goldens on actual QBE and LLVM, then heap/arena
trapping opens and fallible Result publication under RC counting and GC. LLVM
uses `run --release`, never the overriding `--qbe` flag. Traps and output are
compared to existing goldens. RC counts must balance; a CLI capability refusal
before guest startup is allowed no counter record.

The harness preserves stderr and removes only build-slot scheduling lines for
signature classification. Such a line can precede `mylang:` on an expected CLI
error; treating that prefix as part of the program diagnostic otherwise creates
a false mismatch. It does not alter expected output or trap codes.

Validation completed: all 56 file-golden outcomes match after that scheduling
prefix normalization, and all 12 targeted outcomes pass on actual QBE/LLVM
under RC counting and GC. Every executed RC case has balanced ownership and
allocation counts. The original missing-file case now has one allocation, one
retirement and one owner release on each backend, with no acquisitions and the
same located R_FILE.

`raw-initial.json.gz` preserves the first full run unchanged. It contains the
three scheduling-prefix misclassifications and six rejected attempts to select
GC with the unsupported tag `gc` (the accepted tag is `gc-v1`). The initial
extra Result wrapper also used unsupported `int(bool)` and was rejected by the
checker before execution. `gc-rerun.json.gz` retains the corrected GC selection;
`result-rerun.json.gz` retains the corrected wrapper using an `if`. Neither
rejected attempt is counted as an executed guest test. `normalize.py` joins the
valid runs into `results.json.gz`, preserving raw stderr and original differing
classifications. The compiler binary is identical across all these runs.

Reconstruct the joined evidence with:

```sh
python3 normalize.py raw-initial.json.gz gc-rerun.json.gz result-rerun.json.gz results.json.gz
```

The final driver accepts `--gc-only`, `--result-only`, and `--targets-only` as
optional third arguments to repeat the corresponding focused checks. No full
gate or WP-4 performance acceptance is claimed here; integration owns that gate.
