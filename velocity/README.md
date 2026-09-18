# velocity/

The closed loop that measures and improves agent development speed. The design is
[`docs/velocity-loop.md`](../docs/velocity-loop.md); the goal, metrics and baselines are
[`goal.json`](goal.json) (user-owned); the ranked work is [`backlog.json`](backlog.json);
an iteration starts from [`LOOP-PROMPT.md`](LOOP-PROMPT.md). `suites/idioms/` holds the
110 first-try probes with their oracle tags and the 17 September baseline in
`manifest.json`. `score.py`, `gen_project.py` and `solve.py` are backlog items V0 to V2
and do not exist yet.
