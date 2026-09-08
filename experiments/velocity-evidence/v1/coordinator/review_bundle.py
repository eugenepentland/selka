"""Export only public task materials and sealed code for timing-blind quality review."""
import sys,shutil,json
from pathlib import Path
sys.path.insert(0,'/home/epentland/ai/canopy/mylang')
from experiments.application_comparison import session
from experiments.application_comparison.storage import verify_snapshot
R=Path(__file__).parent
def export(task):
 r=R/task;m=session.load(r/'my');idx=m['final_submission']
 assert idx is not None and m['seal_reason'] is not None
 source=r/'my/submissions'/f'{idx:03}'/'source'
 verify_snapshot(source,m['submissions'][idx]['source'])
 out=R/'source-reviews'/task;out.mkdir(parents=True,exist_ok=False)
 shutil.copytree(source,out/'submitted',ignore=shutil.ignore_patterns('__pycache__'))
 shutil.copytree(r/'my-baseline',out/'baseline',ignore=shutil.ignore_patterns('__pycache__'))
 (out/'REVIEW.md').write_text('Review only these public materials and source trees. Do not inspect parent trial state, timings, private cases, grading, or participant transcript. Assess requested behavior, edge cases, ownership/generic structure, regression risk, test quality, unnecessary scope and fixed-case workarounds. Record concrete file/line findings and severity. Output quality-review.json here with verdict, findings, limitations; do not modify submitted or baseline code. This review is separate from hidden behavioral grading.\n')
 print(out)
if __name__=='__main__':export(sys.argv[1])
