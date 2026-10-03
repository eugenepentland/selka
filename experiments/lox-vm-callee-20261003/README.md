VM call dispatch now reads a plain callee descriptor before mutating Runtime.
The preceding match held a managed Obj carrier, including unused code,
upvalue, table and string collections. The descriptor contains only ObjRef
indices, NativeObj integers, or BoundMethodObj's plain Value/ObjRef fields.
The read-only helper finishes before any handler changes the stack or heap.

The class path still allocates first, publishes the instance to the callee
stack slot, then checks the class tag and looks up the initializer. Arguments
and the original class remain rooted across allocation. Bound receivers still
replace the callee before the unchanged closure arity/frame checks. Native
arity still precedes native execution; invalid values preserve the ordinary
error. All object/stack bounds and arithmetic traps remain checked. Object
layout, COW behavior, opcodes, algorithms and collector roots are unchanged.
No cache or speculative path is added.

The fixed combined compiler is SHA256
`d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040`.
Historical first-emission receipts use compiler `9007d053...`; both compilers
produce byte-identical LLVM/QBE RC/GC guests for this candidate. First-emission
and failed fixture receipts remain immutable in the private workspace.

QBE emission removes the one managed callee loan. Cleanup unloan/drop sites
fall from 38 each to 9 each across the handler and reader. Combined SSA size
falls from 2,052 to 1,429 lines. All three normalized bounds failure sites
remain: two in the handler, one in the reader. The reader contains no managed
glue calls. LLVM call_value machine code falls from 2,234 to 2,055 bytes;
QBE call_value falls from 5,041 to 2,941 bytes, with its separate plain reader.
These are emission observations; no performance claim is made here.

Three regressions cover Runtime snapshots across all four callee kinds,
argument evaluation before inherited initializer arity errors, and argument
evaluation before invalid object callee errors. All 83 public tests pass
freshly in each of four configurations: QBE Debug/default checked RC,
LLVM release/default checked RC, and each with native tracing GC stress.
There are 332 passes and zero failed, cached, skipped, missing or unexpected
tests. Existing driver result locals use vm_run because importing vm reserves
that module name even with an import alias. Earlier failed fixtures emitted
compiler E_SHADOWING/status1 with empty stdout; they were not runtime failures.

Bounded end-to-end validation matches 1,168 candidate observations against
the immutable canonical-80 controls: status, stdout, complete stderr and
all Lox collector statistics. Both engines/backends, ordinary RC, ordinary
tracing GC, native tracing GC stress and Lox stress on/off are covered.
Native executable stress uses MYLANG_OPTIONS=--gc-stress; Lox stress uses
guest --gc-stress. The native-stress smoke subset is closures, instantiation
and properties; 80 other smoke cells are explicitly unrun. All 16 focused
programs and 23 historical errors per engine run in every selected mode.
Eight candidate/control RC native-stress combinations refuse identically
with status2 and the --gc-runtime diagnostic; they are not program passes.

The exact 37-file final source manifest is source.json; builds.json records
argv, source/compiler hashes, symbols, LLVM O3/full LTO, runtime archive and
binary hashes. qualification.json records fresh test names and commands.
Full matrix observations are validation-observations.json.gz. Matrix guests
and the subsequently rebuilt final source guests have identical SHA256.
The only changed source/metadata files are vm.my, driver_tests.my and
driver_cases.json. The preceding canonical overlay is SHA256
`233332c7b4fd1325f3ec1251406b0b433e87520f5abc4db9cfcc70e79813445b`.

To reproduce, reconstruct that canonical --optimized port using
docs/audits/d9-stage3d-migrations/apply-lox.sh in private storage, assert
source.json's baseline_files, and apply vm-callee.patch with patch -p1.
Assert source.json's final files before building or running tests. Use:

```sh
python3 experiments/lox-vm-callee-20261003/build.py --source PRIVATE_SOURCE --compiler FIXED_COMPILER --work PRIVATE_BUILD --backend llvm --runtime rc
python3 experiments/lox-vm-callee-20261003/qualify.py --source PRIVATE_SOURCE --compiler FIXED_COMPILER --work PRIVATE_TESTS --expected-count 83
```

Repeat the build for QBE and both separate GC artifacts. Build/test recipes
use scripts/build-slot.sh, private caches/output/TMPDIR and exclude the
reserved timing CPUs. The bounded validation recipe is the existing
experiments/lox-parity-tree-20261003/validate.py with regressions.json, the
immutable pinned benchmark controls and native cases named above.
Root owns central performance, selection, canonical integration and Guardian
feedback. This lane has run no performance measurement.
