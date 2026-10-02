# Lox performance audit, 2026-10-02

The [audit](../../docs/audits/lox-performance-audit-2026-10-02.md) measures compiler
source `6df58b02554401f9d37564cceffd14277a835ae1`, using the checked-in optimized
Lox migration and the original reference ports at `4e48a092`.

`audit.py` checks complete stdout on every run, pins one physical-core thread,
interleaves executable order, records executable/input/output hashes, and saves
each completed sample. `--stats` additionally checks equal Lox collector work.
`profiles.py` samples the same uninstrumented executables and resolves guest
names using the LLVM manifest. Ownership-site instrumentation is separate.

Raw evidence is outside Git at
`/home/epentland/ai/canopy/evidence/lox-performance-audit-20261002` with a
`MANIFEST.sha256`. The original private build workspace is `.tmp-lox-audit/`
in the audit worktree. Its `binaries.json` names the executables and source
identities; `build-commands.json` records equivalent rebuild recipes.

To repeat measurements against the preserved workspace:

```bash
AUDIT_WORK="$PWD/.tmp-lox-audit"
python3 experiments/lox-performance-audit-20261002/audit.py check \
  --work "$AUDIT_WORK" --out "$AUDIT_WORK/recheck.json" --tier smoke --rounds 1 --stats
python3 experiments/lox-performance-audit-20261002/audit.py time \
  --work "$AUDIT_WORK" --out "$AUDIT_WORK/retime.json" --rounds 3
python3 experiments/lox-performance-audit-20261002/audit.py counters \
  --work "$AUDIT_WORK" --out "$AUDIT_WORK/recount.json" --tier tree --engines vm \
  --arms mylang-llvm,mylang-qbe,zig,mylang-gc-llvm --rounds 3 --cpu 10
python3 experiments/lox-performance-audit-20261002/profiles.py --work "$AUDIT_WORK" --cpu 10
```

Run one measurement command at a time. CPU 2 and its sibling 3 are the timing
pair; CPU 10 and its sibling 11 are the counter/profile pair. The build-slot
wrapper excludes all four from builds. No formal 43-program acceptance claim
is made by this focused audit.
