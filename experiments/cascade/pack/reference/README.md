# Reference solutions

Each `T<n>.patch` is the smallest change to design `B` that satisfies that task's
`request.md` and passes its hidden tests and goldens. They exist for two reasons:
to prove the tasks are solvable, and to generate the goldens in the pack. They are
**not** model answers: no designer and no maintainer session ever sees them.

They are kept outside the repository at
`../mylang-eval/cascade-authoring/reference/`, together with the validation
reports, so the repository itself never tells an agent what a hidden task expects.
Apply one to a scratch copy of the arm with `patch -p1`:

```sh
rm -rf /tmp/ref && cp -r experiments/cascade/designs/B /tmp/ref
patch -d /tmp/ref -p1 < ../mylang-eval/cascade-authoring/reference/T3.patch
python3 experiments/cascade/run.py --arm /tmp/ref --task T3 --n 0 --verify-only
```

The patched arms were also run through `arm_gate.py` where the change does not
alter the port's expected behaviour (T1, T2, T5, T6, T7 pass it unchanged; T3 and
T4 deliberately change visible printer expectations, which their requests name).
