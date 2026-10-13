# P3 EDA tokenizer and parser

The scalar suffix classifiers no longer construct a singleton byte buffer or
an SI-scale list. The shared scanner returns scalar `OffsetToken` metadata and
has a compiler-verified `noalloc` contract. The parser borrows the caller's
source plus a separate scalar cursor, avoiding the public tokenizer's initial
source clone, each token-text slice, and atom/string/literal constructor recopy.
Numeric conversion uses the pinned compiler's fused byte-range parse. SI
multipliers use scalar selection instead of constructing the exported scale
list. Public `Token`, `Tokenizer`, `tokenizer_init`, `next`, and all public AST
constructors retain their independently owned text/children contracts. No view
is stored or returned. The scalar scanner helper is exported only to allow the
parser module to call the shared scanner.

`parse_list` retains its already-existing move of fresh children. Its child
append/growth and final AST storage are legitimate output allocations. P3 does
not change that storage, pre-count source tokens, flatten diagnostics, or weaken
the depth cap. Counters will distinguish saved intermediate traffic from
remaining necessary output traffic; this microprobe is not a CPU or full-app
parity measurement.

Base: `2525a66f61838086f5327d74db7412926ce4a221`.
Character classifier commit: `83e487092` (normal Guardian: 88 checks passed).
Offset parser commit: `21033b9ee` (normal Guardian: 88 checks passed).
Compiler: `/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install/bin/mylang`.
Compiler SHA256: `2dcba1cb1a98846bb8c1319575da1b3564e60af70162e195c2fbb6ec3af0f329`.

All native builds/tests use `scripts/build-slot.sh build`, after sourcing
`/home/epentland/.config/mylang/dev-env.sh`. Scratch/caches live under
`/home/epentland/ai/canopy/mylang/.tmp/lox-eda-parity/P3`. Slot directory:
`~/.cache/mylang/slots`; 3 build slots, 2 gate slots, jobs 4, configured maximum
RSS 8 GiB. Shared timing leases are honored. No compiler edits, RC fallback,
Guardian feedback entries, peer merges, or pushes.

Static validation passed:

```
$COMPILER check experiments/lox-eda-parity-20261013/source/eda/p3_parser_tests.my --experimental-zero-rc
$COMPILER check experiments/lox-eda-parity-20261013/source/eda/sexpr_parser_test.my --experimental-zero-rc
$COMPILER check experiments/lox-eda-parity-20261013/source/eda/main.my --experimental-zero-rc
git diff --check
```

Native qualification commands (checked suite passed; counters pending):

```
scripts/build-slot.sh build "$COMPILER" test experiments/lox-eda-parity-20261013/source/eda/sexpr_tokenizer_test.my --jobs 4 --cache-dir "$SCRATCH/cache" --json
scripts/build-slot.sh build "$COMPILER" test experiments/lox-eda-parity-20261013/source/eda/p3_parser_tests.my --jobs 4 --cache-dir "$SCRATCH/cache" --json
scripts/build-slot.sh build "$COMPILER" test experiments/lox-eda-parity-20261013/source/eda --experimental-zero-rc --verify-facts --jobs 4 --max-steps 1000000000 --max-frames 40000 --max-memory 2G --timeout-ms 120000 --cache-dir "$SCRATCH/zero-cache" --json
scripts/build-slot.sh build "$COMPILER" build experiments/lox-eda-parity-20261013/P3/baseline/parser_probe.my -o "$SCRATCH/baseline-probe" --experimental-zero-rc --release --counters --cache-dir "$SCRATCH/build-cache"
scripts/build-slot.sh build "$COMPILER" build experiments/lox-eda-parity-20261013/P3/candidate/parser_probe.my -o "$SCRATCH/candidate-probe" --experimental-zero-rc --release --counters --cache-dir "$SCRATCH/build-cache"
```

The first two compatibility receipts lack the checked-ownership flag and are
not checked qualification. The full EDA suite explicitly repeats those tests
with `--experimental-zero-rc`. New tests exhaust all 256 suffix bytes against
the public tables; compare owned/offset tokens, spans, and cursor state; exercise
Unicode and invalid quoted bytes, escapes, negative SI/dimension values,
overflow diagnostics, and output independence. Existing parser tests retain
fuzz, too-deep, list-error, and caret diagnostics coverage.

The frozen baseline/candidate microprobe parses the identical mixed fixture
1000 times and must print `16000`. After builds/tests finish, run:

```
scripts/build-slot.sh build python3 experiments/lox-eda-parity-20261013/P3/collect.py
```

`collect.py` records binary/source/counter hashes, exact run commands, raw
counter totals and functions, stdout, and raw build/test receipts. No timings
are pooled with this counted probe. Coordinator owns fresh full-application
qualification, output comparison, timing/RSS, and root test registration.

The first checked suite used default execution budgets and produced 311/322
passes: ten `R_STEP_LIMIT` and one `R_FRAME_LIMIT` (the 10000-depth guard).
`zero-suite-default-budgets.json` preserves that receipt. The repeated checked
suite uses exactly the existing EDA qualification budgets from
`experiments/lox-eda-zero-rc-20261012/eda/qualify-tests.sh`, including
`MYL_CORE_LEAKCHECK=1` and `--verify-facts`. Focused compatibility mode receipts
passed 16/16 tokenizer tests and 5/5 new regressions; those are separately
labelled and not used as checked-mode qualification.

The checked EDA repeat passed **322/322**, with zero failures, skips, cached
results, or unsupported tests. `zero-suite.json` and `zero-suite.stderr` preserve
the raw receipt and admitted-build diagnostics. All tests were executed again
under the established budgets. Initial probe builds exposed a missing output
capability in the probe's `print` call; the corrected identical probe uses
`main(out: Stream)` and `out.print(total)`. Both corrected probe modules passed
checked frontend validation before retrying native builds. The original
missing-output build logs are retained separately.
