"""Public-only maintenance source review bundle; excludes timings and grades."""
import shutil,json
from pathlib import Path
R=Path(__file__).parent
for run in sorted((R/'runs').glob('*-stage*')):
 assert (run/'seal.json').exists(),'all stages must seal first'
 out=R/'source-review'/run.name;out.mkdir(parents=True,exist_ok=False)
 shutil.copytree(run/'sealed',out/'submitted');shutil.copytree(run/'commands/001/before',out/'baseline')
 for name in ('TASK.md','cases.json','check.py'):shutil.copy2(run/'public'/name,out/name)
(R/'source-review/REVIEW.md').write_text('Review all six staged changes using only public tasks, baseline and submitted sources. No parent trial state, private grades, timing data, transcript or historical solution access. Check exact behavior, ownership cleanup, generic append and mutable borrow, module boundaries, error propagation, no fixed-case shortcuts, continuity of staged code and maintainability. Static review only unless root explicitly provides an untimed test method. Write quality-review.json here with per-stage verdicts/findings/limitations.\n')
print(R/'source-review')
