# Independent dispatch artifact and qualification review

This extends the proof-only review in commit `36ba38d1` to frozen compiler
`1eea98da` and pinned QBE `99ad919d`. No compiler, guest or performance command
was run by this reviewer. There are no actionable correctness or artifact
findings in this scope. Performance selection remains with the root agent.

The read-only verifier binds all 871 compiler source files (866 under `src`,
five root files), all 37 selected AST port files, the four actual RC/GC guest
ELFs, build argv, sidecars, runtime archives and complete tool prefixes. It
independently compares the LLVM RC ELF's 26 allocated sections, header, entry
and program layout with the selected control. These are identical; separate
GC guests have actual execution coverage, rather than a claimed GC ELF
equivalence result. LLVM release guests use O3/full LTO; QBE uses pinned QBE.

Fresh public coverage is 336 checks (84 named tests in four modes), with no
cached, skipped, failed, dropped or unloaded checks. Public LLVM uses
`--release`; QBE uses `--mode ReleaseFast`. Both retain the established
one-billion-step/120-second limits. Provider cases were not invoked. Full
public streams are retained; LLVM RC build stderr includes an `ar` command.

The bounded native receipt contains 1,168 exact status/stdout/stderr/stat
pairs: 416 RC, 416 ordinary GC and 336 native-GC-stress. Four AST cases add
96 exact pairs. Eight RC native-stress requests return the exact checked
refusal. Eighty expensive native-stress smoke cells remain explicitly unrun.
The verifier reconstructs complete tuple coverage, validates case bytes and
compares full streams with the control. Guest `--gc-stress` and native
`MYLANG_OPTIONS=--gc-stress` are independently represented.

Native before/after maps directly bind the active validator, `freeze.py` and
final five-helper descriptor `9d7f4ce2`; a separate postflight confirms all
five helper hashes. Earlier public and GC windows bind their active helper,
source maps and prefixes. They do not retrospectively acquire a five-helper
window. The first public attempt without an explicit private Zig global
cache, earlier GC postflight `NameError`, and superseded helper descriptor
are retained and excluded. Broad compiler/QBE acceptance was still pending
at this freeze and is not claimed here.

`review.json` names original paths and hashes; `inputs/` stores deterministic
gzip copies of the receipts, full streams and active helpers. Re-run the
read-only checks with the original artifacts present:

```sh
taskset -c 16 python3 -B experiments/lox-qbe-dispatch-qualification-review-20261003/verify.py
```

`verification.json` records the successful check. It reports qualification
coverage only; it does not imply a speedup, promotion or Rust/Go parity.
