# Authoring helpers

`verify_task.sh TASK ARM` assembles a verification tree for one task against one
arm and runs `scripts/verify.py` over it, exactly as `run.py` does but without a
session. ARM is either a design name (`B`, `P1`, `P2`) or a path to an arm
directory. It is how each task's fail-on-B / pass-on-reference pair was checked;
the resulting reports are kept outside the repository under
`../mylang-eval/cascade-authoring/evidence/`.

The hidden tests, goldens and input fixtures live outside the repository at
`../mylang-eval/cascade/<task>/`, so this script only works while that tree is in
place; `pack/MANIFEST.sha256` is the record of what it should contain.
