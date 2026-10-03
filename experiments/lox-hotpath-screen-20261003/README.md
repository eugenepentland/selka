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

The revised equality helper manually spells the existing pure comparison in its readonly body. Its separate complete qualification remains344 public tests/348 exact native VM pairs. Root reproduced both revised qualified RC guests byte for byte and completed another156-observation smoke plus104-cell diagnostic counter screen. LLVM VM instruction reduction stays0.3165%; QBE VM now increases0.0923%, including0.7222%/0.6645% increases in equality/string-equality. Tree counts remain effectively unchanged. Removing the nested call reduces the QBE regression but does not establish a useful cross-backend gain. V2 remains unselected with no full wall run. `equality-v2.json` and `equality-v2-qualification-review.json` bind this separate complete screen, root native/build/public receipt review and immutable archive; neither V1 nor its failed preparation/GC recipe is counted as new V2 coverage.

The numeric result-shaping trial has separate348 fresh public passes,1096 exact native program pairs and8 checked RC refusals, with80 explicit expensive native-smoke omissions. Root independently reconciled those streams/build flags/input hashes and rebuilt both qualified RC ELFs exactly. Its completed central156-observation smoke and104-cell instruction screen preserve205 guards and416 fully running PMU checks. VM instructions decrease0.0246% LLVM/0.0560% QBE across13 cases; fib decreases0.1870%/0.3797%. Tree LLVM instructions increase0.0093%, while QBE tree is effectively unchanged. These small diagnostic gains accompany larger static cold code and establish no wall-time benefit. The numeric source stays isolated; no full wall run or equality/numeric composition qualification follows this screen. `numeric.json` and `numeric-qualification-review.json` retain its separate immutable archive and root review. All three complete screens contain312 counter cells and468 smoke observations in total; none is a multi-round timing acceptance matrix.
