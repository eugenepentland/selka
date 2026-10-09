# Repository contents

This repository presents Selka's language goals, compiler source, examples,
tests, and measured progress. It has no GitHub Actions workflows or compiler
downloads. Public compiler builds are not a release commitment at this stage.

The initial public history is a clean snapshot. The original development
repository retains the earlier commits and large experiment archives locally.
Deleting archives from a working tree does not remove them from its Git history;
the separate publication repository avoids uploading that history.

## Retained benchmark evidence

- [`parity-confirm-20261009`](../experiments/parity-confirm-20261009/) contains
  the report, raw samples, invocations, logs, and measurement script behind the
  runtime chart.
- [`parity-measure-20261008`](../experiments/parity-measure-20261008/) contains
  the application profiles and diagnostic measurements cited by the tour.
- [`bench/parity/`](../bench/parity/) contains the current benchmark workloads,
  reference implementations, harness, and small dated result snapshots,
  including the incremental-build measurements.
- [`docs/figures/`](figures/) contains the figures and their renderer. The
  renderer reads the retained data; it does not rerun benchmarks.

The [benchmark page](benchmarks.md) explains which results are comparisons of
ordinary compiler output and which are diagnostic experiments. Recorded hashes,
commands, compiler names, and samples remain as measured. Old commit hashes and
absolute machine paths describe the original experiments, not the clean public
repository's history or a portable build setup.

Other archived runs, copied application trees, large compiler dumps, compressed
receipts, and obsolete benchmark outputs are omitted. Audit Markdown reports and
figures remain as design context; references in those historical reports to
omitted raw runs belong to the local development archive. Current compiler test
fixtures live under `test/` and do not depend on that archive.
