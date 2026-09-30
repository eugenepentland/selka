# Module lane evidence

Read `identity.json` for checkpoint attribution and compiler hashes. The final
module lane is native RC ABI 3; acceptance of the combined ABI 5 source needs
the integrator's final gate. `raw-manifest.json` gives the original path, length
and SHA256 of every raw archive member. Failure logs remain alongside corrected
attempts, with their original names.

Extract the deterministic receipt bundle into an owned scratch directory:

```bash
mkdir -p .tmp/module-evidence
tar -xzf docs/audits/evidence/codex-next-modules-20260930/raw-receipts.tar.gz -C .tmp/module-evidence
```

The `inputs/scale-200k` directory contains the exact measured scale fixture;
`inputs/lox-corpus` and `inputs/lox-a3` contain the frozen corpus and project test
sources. `harnesses/` preserves the original oracle implementations. Portable
drivers are also checked in under `experiments/module-scale-20260929/`.

Run from repository root, with a fresh work directory and compiler built from
the source being verified. All heavy commands require build-slot admission:

```bash
scripts/build-slot.sh build python3 experiments/module-scale-20260929/corpus_byte.py \
  /absolute/frozen/bin/mylang .tmp/corpus-byte-replay \
  --lox-entry .tmp/module-evidence/inputs/lox-corpus/main.my \
  --source FROZEN_REVISION --jobs 2 --json .tmp/corpus-byte-replay.json
```

Claim the reserved timing CPUs with other agents before replaying measurements;
provide frozen ReleaseFast control/candidate compilers and a fresh work root:

```bash
scripts/build-slot.sh build python3 experiments/module-scale-20260929/check_pair.py \
  /absolute/control/bin/mylang /absolute/candidate/bin/mylang \
  .tmp/module-evidence/inputs/scale-200k .tmp/check-pair-replay \
  --control-revision CONTROL_REVISION --candidate-revision CANDIDATE_REVISION \
  --cpus 2,3,10,11 --samples 7 --json .tmp/check-pair-replay.json
```

The strict byte corpus does not execute guests. Runtime behavior evidence comes
from the recorded guest tests and Differential invalidation matrices. Legacy
receipts, inferred checkpoint labels and independent read-only inspections do
not assert acceptance of later runtime sources.
