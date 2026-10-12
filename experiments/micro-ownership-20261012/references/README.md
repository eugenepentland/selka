Fresh foreign runtime references for the unchanged expanded40 suite

`prepare.py` copies canonical foreign sources, builds the sixteen group/arm
executables via shared `scripts/build-slot.sh build` admission, and runs only
correctness qualification under one batch admission. There is no calibration, timing round, RSS probe,
optimization, reduced workload, or reuse of archived samples. Raw stdout includes
the protocol's kernel clock field; this is qualification evidence, never a
performance observation. Each case uses registry EDGE_PROBES and both documented
sizes at seven iterations. Guest stderr must be empty after admission receipt
lines are removed. The manifest records exact commands, private cache locations,
source/tool/build-log/binary hashes, and executable paths (mode 0555). The actual
rustc and Cargo toolchain binaries are hashed separately from rustup invocation
paths. No source migration was required; every copied source/dependency file matches
its canonical hash. The sixteen binary files remain in private scratch and are not committed.

Reproduce from repository root:

```
source /home/epentland/.config/mylang/dev-env.sh
python3 experiments/micro-ownership-20261012/references/prepare.py
```

Build policy: portable Rust -O edition2021; locked Cargo release for text; normal
Go build with GOMAXPROCS1, GOGC100, GOMEMLIMIT off, GOAMD64v1; pinned Zig host-default
ReleaseSafe/ReleaseFast with libc. Tuning wrapper environment is removed.

Historical comparison inventory is read-only. The complete recent comparable
run is `benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz`
(schema mylang-runtime-expanded-v2, 7200 raw samples). The October3 original
expanded baseline has schema mylang-runtime-expanded-v1 and 7200 samples. The
October4 B1 normalized and G2/G4 accepted reports retain independently confirmed
expanded-v2 subsets. G4 (`6cf7bdce11bc205862bf75b9d9ce72e46caad0a2`) is the later
confirmed six-case subset, including string_join, bytes_scan, string_search,
string_equal, sort_int, mutate_nested. It is a candidate for per-case history,
not a complete replacement baseline. `history-inventory.json` inventories stored
schemas/keys, and `history-confirmations.json` records exact external paths,
availability and SHA256 for the accepted reports' raw confirmations and checks.
All linked confirmation bytes were available when scanned. Prior times must stay
labeled by their original source/tool/host identities; no archived round is reused
or paired with this experiment.
