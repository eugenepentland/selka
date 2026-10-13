P6 standalone parity pipeline

`native.py build|qualify|matrix lox|eda --root ROOT --compiler COMPILER --install INSTALL --common-receipt COMMON --prior-root PRIOR --attempt ATTEMPT --source SOURCE [--lox-harness RECOVERED_HARNESS]`

`pipeline.py prepare|schedule|count|report --root ROOT --compiler COMPILER --install INSTALL --prior-root PRIOR --attempt ATTEMPT --lox-build LOX_RECEIPT --eda-build EDA_RECEIPT [--case tree-fib] [--cpu 8] [--resume] [--freeze FREEZE]`

PRIOR is the coordinator's absolute experiments/lox-eda-improvements-20261012 directory. Candidate common receipt, install, compiler and sources are explicit. Prepare privately copies recovered expected outputs after checking recovery pins; full native installation and source/input identities are pinned. It retains the same frozen Zig ReleaseFast and previous last-batch checked binary. An optional newly built previous source with the candidate compiler distinguishes application-only change from combined compiler/application change.

Source the development environment before any native entrypoint:
`source /home/epentland/.config/mylang/dev-env.sh`

Only the scheduler invokes timing admission. Full schedule requires a coordinator freeze JSON with `pins_sha256` equal to the SHA256 of attempt/pins.json; a selected `--case` is a diagnostic stage. One wall pair per lease, separate warmup/calibration lease, and three separate RSS leases minimize long timing holds; 120s process ceilings and initial calibration can still make individual leases longer than the desired 60s target. No hard host-time guarantee is claimed.

The measurement engine preserves strict same-spec/same-identity continuation, independently censored candidate/previous deadlines, output checks, process-group termination and progress journals. It uses three fresh Zig samples, two warmups, nine alternating rounds and three RSS samples. Cutoffs have no exact ratio. Interrupted generated specs stop automatic recovery. All 60 cases remain in final scope; success requires every candidate/Zig median ratio <= 1.0. Counters run separately and preserve native counter receipts; report verifies zero managed exit-live and checked RC counts.

Qualification inventories current source test declarations, validated against the prior frozen source at 75 Lox and 317 EDA declarations. Existing strict qualifier and five-mode matrix execute through private destinations; added declarations automatically raise denominator. Prior Lox external conformance harness/corpus is missing; qualification requires explicit --lox-harness recovery before it can run 974 conformance checks. Historical evidence is never changed.

Preparation syntax and all eight deadline tests passed. No candidate native build or runtime benchmark started by P6. Tests: `python3 -B experiments/lox-eda-parity-20261013/test_timeout.py` (8 passed); `python3 -B -m py_compile .../{native,pipeline}.py`.
e6ba4bb6b651983fe60ffb5fb12fba0942f36108c36afec94e3bbfb36ec39402  experiments/lox-eda-parity-20261013/native.py
2ab759738fd6209269b7b6d04fe7bf62425cc4f2336087d2d9efb20b61b437d7  experiments/lox-eda-parity-20261013/pipeline.py
ebead08898b4eba7885e41451378be14e8d53dc5cf213d66d4230f33130e8c7d  experiments/lox-eda-parity-20261013/measure.py
47c3aa74e7693be6b0683cdb9b6e84e941803ababe24d23477752215367c8d78  experiments/lox-eda-parity-20261013/test_timeout.py
