# Checked byte-source screen

This screen measures the corrected `octets-shape-v3` source with the unchanged
selected d14 compiler and QBE99ad. Its control is the accepted callee/table
source84, before the selected AST handler refactor. It isolates byte storage;
the separately qualified AST composition is outside this measurement manifest.
Both backends retain checked casts, bounds, overflow, COW and roots.

All 37 source files match the author maps in `../lox-vm-bytecode-20261003`.
Root rebuilt the two RC guests in fresh private caches; both reproduce the
qualified author binaries byte for byte. Controls and original Rust/Go are
copied from the frozen preceding measurement and verified by byte hash.
Inherited sidecars retain original absolute build paths. No reference is
rebuilt or substituted in this measurement.

The completed smoke has 156 exact output/collector observations across six
arms, all 13 workloads and both engines. The diagnostic one-round counter
matrix has 104 unique cells across four mylang arms. All 416 PMU running-rate
checks equal 100. Matched instruction changes are:

| Byte-source candidate relative to source84 | LLVM | QBE |
| --- | ---: | ---: |
| VM instruction reduction | -1.2402% | 0.2574% |
| Tree instruction reduction | approximately 0% | -0.0391% |

Negative reductions mean more instructions. All 468 matched wall cells are
now complete. LLVM VM is 0.6211% slower and QBE VM is 0.2345% faster, with
median paired spreads 1.402% and 1.098%. LLVM tree moves 0.4788% faster and
QBE tree 0.5773% slower. This does not establish a useful performance gain, so
the byte source and its qualified AST composition remain isolated. The existing
source qualification's fresh 352 accounted public executions, 1396 native pairs,
eight RC refusals and 80 explicit omissions are distinct from this screen.

The private workspace is `.tmp-lox-byte-screen-ready`. `prepared.json`,
`binaries.json`, `octets-build.json`, `guards.json` and the after-screen receipt
bind source, compiler/QBE, actual guests, sidecars, runtime objects, benchmark
inputs and measurement helpers. One earlier private preparation attempt used
the variant metadata object instead of its nested source37 map; it failed an
assertion before building the byte candidate or measuring anything. Its scratch
is retained as `.tmp-lox-byte-screen` and is not a passing receipt.

To replay, reconstruct the source84 control from the fixed archive in
`../lox-ast-constant-20261003/baseline-source.tar.gz`, replay the checked v3 patch
with the byte experiment's `reconstruct.py --base` and verify its recorded 37
hashes. Use `../lox-parity-20261003/build.py` with explicit fixed compiler and
fresh work paths to rebuild. The original reference ELFs must remain pinned
for reproducing these comparisons. The native qualification receipts retain
their separate actual RC/GC guest identities and full streams.

Run only one performance command at a time, using the private frozen manifest:

```bash
LOX_BYTE_WORK=/absolute/path/to/private-frozen-work
python3 experiments/lox-parity-20261003/run.py counters --work "$LOX_BYTE_WORK" \
  --out "$LOX_BYTE_WORK/instruction-screen.json" \
  --arms baseline-llvm,baseline-qbe,octets-llvm,octets-qbe \
  --tier tree --rounds 1 --cpu 10
python3 experiments/lox-byte-source-screen-20261003/analyze.py \
  "$LOX_BYTE_WORK/instruction-screen.json" --screen --metric instructions \
  --out "$LOX_BYTE_WORK/instruction-analysis.json"
python3 experiments/lox-parity-20261003/run.py time --work "$LOX_BYTE_WORK" \
  --out "$LOX_BYTE_WORK/wall.json" \
  --arms baseline-llvm,baseline-qbe,octets-llvm,octets-qbe,rust,go \
  --tier timed --rounds 3 --cpu 2
python3 experiments/lox-byte-source-screen-20261003/analyze.py \
  "$LOX_BYTE_WORK/wall.json" --metric wall_s \
  --out "$LOX_BYTE_WORK/wall-analysis.json"
```

The analyzer checks exact case/arm/round coverage, outputs, statuses and all
counter running rates, then takes within-case paired medians before combining
the 13 ratios geometrically. This screen is separate from the complete AST
factorial and supplies no full compiler performance-gate or Rust/Go parity claim.

`wall-closeout.json` verifies all 152 guarded inputs after the full run.
`finish-wall-worker.py` is the archived private monitor; use the commands above
for a new workspace. The historical diagnostic checkpoint remains a snapshot
from before wall completion and does not count as an additional run.
