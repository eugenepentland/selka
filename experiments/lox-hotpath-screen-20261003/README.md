# Matched Lox hot-path screens

The first readonly equality helper saves copying on LLVM but adds executed work on QBE. It remains isolated. The central diagnostic counter screen reports LLVM VM instructions0.3165% lower and QBE VM0.1494% higher across13 workloads. LLVM equality/string-equality are1.7119%/2.1069% lower; QBE's same cases are1.0157%/0.9960% higher. Tree instruction counts are effectively unchanged. These are one-round instruction diagnostics, not wall-time gains or a completed multi-round counter matrix.

Root freshly rebuilt both checked RC guests from the qualified37-file source with frozen d14/99ad; they reproduced the author's actual qualified ELF hashes exactly. Selected AST controls and original Rust/Go guests were copied and verified. The author qualification has344 fresh accounted public tests and348 exact native VM comparisons with distinct explicit RC/GC builds, error/equality cases, Lox stress and native-GC stress. Those scopes are separate from the central156 smoke/output/collector observations and104 counter cells. All416 PMU running-rate checks equal100; all205 guarded inputs remain unchanged after measurement. The native qualification's initial GC build-recipe error and failed partial runner remain excluded and preserved in the author experiment.

QBE's first helper adds a call before its existing `values_equal` call. Its lower total static code size did not establish a cheaper executed path. A separate source trial is being investigated to remove that additional call by spelling the existing pure tagged comparison inside the readonly helper. This screen does not qualify, measure or select that subsequent trial. No full wall run was started for the first shape after its QBE instruction regression; the selected source/compiler and `main` remain unchanged.

`equality-v1.json` binds a separate immutable archive of every original guarded input, central measurement rows/commands/logs, copied37-file sources, reference fixtures, six actual RC/reference guests and rebuilt runtime objects. Input paths are identity keys; payloads are stored by SHA256 and may share an object. `qualification-review.json` separately records root's reconciliation of all348 native rows, runtime flags, four actual guests and stimulus hashes. The first root preparation preflight used `builds` instead of the author's `runs` receipt key and therefore did not write the source map; preparation then failed on the missing map before creating a workspace or building/measuring. The corrected preflight and preparation completed. The failed preparation log is retained; it is not a passing build.

`prepare.py` verifies exact37-file maps, frozen tools and previously reviewed qualification inputs, copies the selected controls/references, rebuilds the candidate in private caches and refuses nonidentical qualified guests. Qualification review is separate from this preparer. `analyze.py` checks exact26-case/arm/round coverage, statuses, expected output hashes, all PMU running percentages and original guards before using paired per-case medians and geometric means. `close-screen.py` verifies completed diagnostic evidence and freezes all inputs without running guests. Helpers refuse to overwrite accepted measurements or archive directories.

For a new qualified candidate, prepare a new private workspace and run one performance command at a time:

```bash
LOX_HOTPATH_WORK=/absolute/path/to/new-private-work
python3 experiments/lox-parity-20261003/run.py check --work "$LOX_HOTPATH_WORK" \
  --out "$LOX_HOTPATH_WORK/smoke.json" \
  --arms baseline-llvm,baseline-qbe,candidate-llvm,candidate-qbe,rust,go \
  --tier smoke --rounds 1 --stats --cpu 10
python3 experiments/lox-parity-20261003/run.py counters --work "$LOX_HOTPATH_WORK" \
  --out "$LOX_HOTPATH_WORK/instruction-screen.json" \
  --arms baseline-llvm,baseline-qbe,candidate-llvm,candidate-qbe \
  --tier tree --rounds 1 --cpu 10
python3 experiments/lox-hotpath-screen-20261003/analyze.py \
  "$LOX_HOTPATH_WORK/instruction-screen.json" --screen --metric instructions \
  --out "$LOX_HOTPATH_WORK/instruction-analysis.json"
```

All13 workloads are checked under both engines; counter inputs use the calibrated tree tier. Broader timing and counter acceptance follow only when a candidate warrants them. The earlier selected AST factorial and sealed checkpoint remain independent evidence.
