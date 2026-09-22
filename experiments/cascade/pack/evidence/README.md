# Task evidence

`summary.json` records, for every task, whether its verification failed on the
frozen baseline `B` and passed on the author's reference solution. Both must hold
or the task is not measuring a change:

| task | on B | on the reference |
| --- | --- | --- |
| T1 | fails | passes |
| T2 | fails | passes |
| T3 | fails | passes |
| T4 | fails | passes |
| T5 | fails | passes |
| T6 | fails | passes |
| T7 | fails | passes |

The raw `verify.py` reports — every step's commands, exit codes and captured
output — are kept outside the repository at
`../mylang-eval/cascade-authoring/evidence/<task>-on-<arm>.json`, beside the
reference patches, so that nothing in this repository tells a designer or a
maintainer what the hidden tests contain.

Reproduce a row with the runner and the reference patch:

```sh
python3 experiments/cascade/run.py --arm B --task T3 --n 0 --verify-only
builtin cd /tmp && rm -rf ref && cp -r /home/epentland/ai/canopy/mylang/experiments/cascade/designs/B ref
patch -d ref -p1 < ../mylang-eval/cascade-authoring/reference/T3.patch
python3 experiments/cascade/run.py --arm /tmp/ref --task T3 --n 0 --verify-only
```
