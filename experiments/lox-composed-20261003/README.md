# Composed85 qualification

This fresh stage qualifies root's round3 composed85 source and actual LLVM/QBE
guests against selected combined84 controls. It uses frozen compiler d14a7040
and adjacent QBE 99ad919d. No prior observations were resumed or copied into
the new executions. Performance, canonical changes and Guardian feedback are
owned by the root lane.

All 340 public directory tests passed freshly: 85 tests across LLVM/QBE and
RC/native-GC-stress, with zero cached, failed, skipped or dropped tests. These
directory commands do not supply `--cases`. Separately, four fresh executions
of `test_run_constant_operand_last_byte` explicitly supply `driver_cases.json`
with `--cases`; each passes and records the same nonempty provider identity.
Full JSON reports are preserved, distinguishing provider-backed execution
from structural fixture preservation.

Actual unaccounted native guests passed 1168 bounded comparisons, 12 VM constant
operand boundary comparisons and 96 AST call/class root/error comparisons.
Each comparison checks exact status, full stdout, full stderr and Lox statistics
against its corresponding immutable backend/Lox-stress RC control. The bounded
matrix has 416 RC, 416 ordinary tracing-GC and 336 native-GC-stress observations;
it includes 13 smokes, 16 focused programs and 23 historical errors per evaluator,
with guest Lox stress off/on. Native stress uses `MYLANG_OPTIONS=--gc-stress`.
All focused programs and historical errors run under native stress. Only
closures, instantiation and properties smoke programs run with native stress;
80 other smoke cells are explicitly unrun and are never counted as passes.

Eight additional RC/native-stress pairs produce identical checked refusals:
status 2, empty stdout and the diagnostic requiring `--gc-runtime`. These are
refusals, not program passes. The AST probes come from the corrected frozen
fixture and run freshly on this composition, including exact VM error traces.

The root source37 composition matches its recorded hash map. Compared with
baseline84, only `vm.my`, `interpreter.my`, `driver_tests.my` and
`driver_cases.json` differ; the other 33 files are unchanged. The VM source
matches the reviewed readonly constant-read candidate. Mechanical source checks
confirm the AST call/class match arms contain the original operation bodies
verbatim after indentation adjustment, retain the original public node getters
and accept readonly Program arguments. Thus the arm extraction preserves callee
and argument order, roots, superclass/environment/method construction and error
propagation. This supplements the fresh runtime comparisons. Internal malformed
AST/bytecode native helper-frame attribution retains the previously reviewed
source-refactor limitation.

Before/after snapshots freeze every file of both source37 trees, all actual
ELFs, manifests, receipts, runtime archives, compiler/QBE, composition/build
receipts, pinned SPEC, helper/cases/historical inputs and qualification runners.
Generated inputs are rehashed against every observation and omission after
execution. Unique/disjoint run and unrun identities cover the complete bounded
matrix. All frozen identities remain unchanged.

The four GC/public/provider/native runners use separate paths and caches under
`.tmp-lox-composed-20261003`; their receipts record full argv and streams. Run
each once in a fresh workspace using the worktree's `scripts/build-slot.sh build`
with private `TMPDIR`: `python3 build-gc.py`, `python3 public.py`,
`python3 provider.py`, then `python3 validate.py`. The build-slot launcher
excludes CPUs 2, 3, 10 and 11. `pack.py` rechecks completed receipts without
executing guests and preserves deterministic gzip copies of the full streams.
`qualification.json` records exact paths, hashes, counts, omissions and limits;
`checks.json` records the explicit Guardian gate. This stage makes no timing,
instruction-count or Rust/Go parity claim.
