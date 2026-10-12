# Lox / EDA improvement audit

Source and existing-counter audit on development-line commit
`5f1701b13f243ca1fcc05c0b38ce73b8c9c3cd4d`. No application or compiler changes,
new benchmark executions, or new performance claims are included.

The [ranked implementation plan](../../docs/audits/lox-eda-improvement-plan-2026-10-12.md)
identifies VM frame copies, tree AST copies, object-payload reads, EDA AST copies,
and EDA overlap suffixes. It includes source locations, dependencies, ownership
constraints, correctness coverage and measurement criteria.

[attribution.json](attribution.json) retains all function buckets, per-case
traffic and managed peaks, compiler identities, missing cases, and SHA256 hashes
of the input profiles and inspected source. It uses one fresh profile and 54
historical completed profiles; the six missing historical VM profiles and 59
fresh runtime cutoffs remain explicit. It does not combine different compiler
runs or treat allocation shares as CPU-time shares.

Reproduce from the repository root:

```sh
source /home/epentland/.config/mylang/dev-env.sh
scripts/build-slot.sh build python3 -B experiments/lox-eda-improvement-audit-20261012/audit.py
```

The Python script uses only the standard library and writes only this directory's
`attribution.json`. In a fresh checkout it reads the single fresh counter directly
from the existing rerun archive; when the raw counter is already restored, its
hash must match the archive manifest. Historical gzip files are read in place.

Validation: all 55 completed profiles' exclusive function traffic equals their
total traffic; all have zero managed exit-live bytes. Coverage assertions preserve
all 60 current runtime cases and all 26 historical Lox cases. Production source
continues to match the compiler revision used for the fresh rerun. Audit-only
changes do not rerun the compiler's full verification gate.
