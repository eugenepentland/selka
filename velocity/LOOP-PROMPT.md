You are running one iteration of the mylang velocity loop. Read `docs/velocity-loop.md`
and `velocity/goal.json` first; they define the goal, the metrics, the acceptance rule and
the stop rules. Follow `CLAUDE.md` for build, test and Guardian rules.

Do exactly one candidate change per iteration:

1. Measure. From a clean checkout of `main`: `zig build`, then
   `python3 velocity/score.py --lanes B,C,D --out velocity/current.json`. If `score.py`
   does not exist yet, the iteration is backlog item V0: build it to the spec in
   `docs/velocity-loop.md` §2 and §6, and accept it when it reproduces the baselines in
   `goal.json` within the noise floor. Compare `current.json` with `velocity/baseline.json`;
   if any metric is red beyond tolerance on clean `main`, fixing that regression is the
   iteration.
2. Pick. Read `velocity/backlog.json` and the newest files under `velocity/friction/`.
   Choose in this order: any C2 silent wrong answer; any red ratchet; the `todo` item with
   the highest `expected_gain / cost` whose prerequisites are `done`. Before changing
   anything, append `velocity/history/<UTC timestamp>-<item id>.json` with the item, the
   metrics you expect to move and their current values.
3. Change. Work in a worktree off `main`. Add a `// spec:` tag and a `SPEC.md` bullet per
   behavioral line, a doc section with a runnable example for any new feature, and an
   idiom probe with a CPython oracle tag under `velocity/suites/idioms/` for any new Python
   construct. Iterate with focused tests (`python3 scripts/focused_test.py units NAME`).
4. Gate and score. Run the full gate from `CLAUDE.md`, then `score.py` again. Apply the
   acceptance rule in `docs/velocity-loop.md` §3: every gate green, no B/C/D metric worse
   than baseline beyond its tolerance, at least one metric improved beyond its noise floor
   or the commit names the prerequisite it completes.
5. Record. On accept: commit on `main` with the before and after values of every metric
   that moved in the message body, write `velocity/baseline.json`, mark the backlog item
   `done`, update the history file with the result. On reject: update the history file with
   the numbers and the reason, mark the item `failed` with a one-line cause, discard the
   worktree, and stop the iteration.
6. Use. If this is a fifth iteration or the nightly slot, run
   `python3 velocity/solve.py --pack velocity/tasks/public` after step 5 and append its
   friction records; turn every `unclassified` record into a backlog item with its count as
   `expected_gain`. Never read `../mylang-eval/tasks/heldout/`.

Never edit `velocity/goal.json`. Never delete a probe or a history file. Never commit red.
Stop and write a report under `velocity/history/` if a gate fails on clean `main`, if the
chosen item has already failed three times, or if the daily budget in `goal.json` is spent.
