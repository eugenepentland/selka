# S4 qualification tools

The initial corrected tool source is frozen at `07cca6157`. These wrappers leave
the inherited S1/S2/S3
harnesses unchanged. They prevent the independently reduced false passes and
own all launched processes through one subreaper supervisor per command. The
root independently reran all eleven local selftests: 11/11 pass in 1.778 seconds,
with all five source files unchanged. This qualifies the tools' local behavior,
not a compiler package or the final S4 bar.

The wrappers require fresh evidence/cache paths and explicit immutable old/Core
binaries plus `--old-source` and `--core-source`. `--zig` and `--qbe` pin the
resolved executables; their environment defaults may be used only with the
recorded immutable inputs. The manifests bind compiler, source, harness and tool
identities and reject changed tracked inputs after a run.

- `conformance_checked.py` retains exact corpus bytes and baseline logs, forces
  Core execution, and requires the exact selected per-file and per-mode coverage.
  The full selection is 332 file rows, including 95 legitimate zero-test support
  rows, and 1,518 comparisons in each mode. Propagation's nine tests already
  belong to that total. Duplicate names, unsupported selected tests, mismatched
  totals, cached forced results and aggregate empty selection fail closed.
- `project_matrix.py` retains original and every edited/provider input snapshot,
  compares both concurrent providers with the distinct frozen old oracle,
  validates forced execution and records warm no-Zig traces.
- `fuzz_matrix.py` defaults to 50 cases for each of the nine inherited kinds.
  S4-X must explicitly use `--cases 200`: 1,800 accepted programs and 25,800
  exact native comparisons across Debug, Release and fact verification. Exact
  typed counts, accepted modes, oracle identity and zero failure categories are
  required for every kind. Full old gates and this matrix remain serialized
  under the shared qualification lock; each worker takes its normal build slot.

Raw process receipts preserve stdout/stderr bytes on timeout, including invalid
UTF-8, and record cleanup. Detached descendants whose immediate parent exits
remain owned by their dedicated supervisor. Concurrent unrelated commands
survive cleanup. The historical orphan hang, its matching reconstructed old
helper bytes, the initial reconstruction whitespace failure and all local
selftest failures remain retained; no historical failure is rewritten as green.

No full conformance, strict fuzz or full old gate is part of this tool repair.

The follow-up argument-forwarding correction disables abbreviation in the
conformance adapter's first parser. Previously historical `--core` overwrote
the adapter's `--core-source` and disappeared from the forwarded command.
`arguments()` is the actual parser used by `main`, and the permanent pure
selftest covers separate/equals forms in both flag orders. The original parser
RED and controls remain retained under `qualification-forwarding-root02`.
Project/fuzz wrappers have their own exact `--core` option and do not need this
repair. Capture and the historical harness stay unchanged.
Root reproduces the original forwarding failure, then passes all twelve local
selftests in 1.811 seconds on the corrected two tool files; all five helper
hashes remain unchanged during that replay. The correction does not qualify
any compiler or conformance sweep.
