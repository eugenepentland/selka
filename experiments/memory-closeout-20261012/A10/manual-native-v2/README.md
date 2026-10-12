# Versioned counter-only native replay for optimized compilers

This is a separate v2 adapter. The v1 adapter, original C0 counter supplement and
failed first Support7 extraction remain unchanged. Both matched C0 and Support7
counter supplements must use this exact v2 adapter revision and preserve their
source/compiler/LLVM/runtime/binary identities. Timing and RSS continue to use
ordinary uninstrumented compiler builds, independently of this method.

Support7 ReleaseFast omits the Debug data symbols used by v1. V2 accepts an
explicit `--number-object` only when preparing a runtime. This file must be the
actual captured input to the frozen compiler build. Its full bytes must occur
exactly once in a read-only file-backed segment of the frozen compiler ELF;
its independent x86_64 ET_REL section extent must equal its full file length;
and its exported symbols must exactly match the compiler's number helper list.
The complete runtime text reconstructed from the exact Git revision must also
occur uniquely in a read-only file-backed segment. No object is rebuilt or
substituted. The receipt records offsets, lengths, file hashes, compiler hash
and extraction method. Debug compilers retain the named-symbol extraction path.

The actual Support7 input is `core_number_text.o`, 409160 bytes,
SHA256 `7cafd8f15b9d865346ab77b26e254d55d93520ffcef564c1f9968dab5085f249`.
Its unique embedded offset is 620952. The exact443129-byte runtime text is at
1326549. Support7 compiler SHA256 is
`540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`, source
`bed11cf3bf3102ffec44487e431a1573fdf02ad5`.

`extraction_test.py` validates the real input and refuses truncated/extra-byte
ELF inputs, a foreign machine, an altered object, duplicate embeddings,
writable-segment embeddings and unrelated runtime text. `pipeline-equivalence.json`
records identical ASTs for native link, command execution and environment code
between v1/v2; target, CPU, compilation flags and object-selection behavior are
unchanged. `C0-runtime-equivalence.json` additionally proves exact equal hashes
for base.c, counted.c, runtime.o and number.o from independently prepared C0
v1/v2 runtimes. These checks establish method continuity, not performance results.

The normal/manual Support7 JSON and task controls, raw preparation and final
qualification status are published separately after execution. Never infer
successful ordinary C0 compilation from a successful replay: its eight original
native driver failures remain in the denominator and retain distinct evidence.

The exact Support7 normal/manual controls now pass: the JSON array and one-worker
managed task workload produce identical full counter documents and outputs, with
RC0 and managed exit-live0 in both arms. `validation.json` binds both compiler
preparations and both control artifacts; compressed raw inputs/commands/results
are under `raw/`. A09 must still execute the full15 C0 and candidate workloads
with this v2 revision before paired census evidence is complete.
