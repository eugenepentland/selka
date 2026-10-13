# P1 final common-001 bounded requalification

**Passed** on compiler SHA256 `955f311e1dbf65b55f4c148ab03cdcb4881bc5668289aea93336dbfd7985206a` at `/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/coordinator/common-001/install/bin/mylang`. The complete bin/libexec/tools installation was used. Integrated source commit: `be33ce79b5b58c3e254e73709c9dd7eb97e5a849`.

The local P1 `heap.my`, `object.my` and `table.my` were asserted byte-for-byte equal to that integrated commit before building. All six imported modules were staged from the integrated commit, and the existing bounded probe sources were copied unchanged into private scratch. `input-identity.json` records the compiler, imported-source, probe and binary hashes. Old P1 evidence and production files were not modified.

All three builds passed with checked zero RC, release and counters. Four normal runs passed output checks, with runtime/shared retain/release counts zero and zero live bytes at exit. All nine prevalidation subprocess cases exited 1 with the expected diagnostic before extraction; their fatal assertions retain 269,344 setup bytes at process exit because normal scope cleanup does not run. No zero-live claim is made for fatal failures. Exact counters, stdout/stderr, runner scripts, build/run logs and `qualification.json` are preserved here.

| reduced probe arm | allocations | allocated bytes | list copies | copied bytes |
|---|---:|---:|---:|---:|
| fresh allocation |131|1,651,544|2|63|
| snapshot allocation |232|3,297,240|102|1,638,463|
| owned mutation |5,181|747,632|0|0|
| snapshot mutation |5,482|15,514,928|300|14,745,600|

Allocation probe: 100 environments of 1024 slots; both arms print `100 True`. Per-helper rows isolate 100 full slot-array copies / 1,638,400 bytes in `heap::allocate`; `heap::allocate_env` reports zero copies/allocations, while `object::new_env` construction traffic is identical. Overall totals also include setup and the snapshot arm's extra command-line argument allocation.

Mutation probe: 100 updates each to instance fields, class methods and environment slots, after common setup with 1024 keys and 1024 slots; both arms print `True True True`. Owned mutation has zero array copies; the fallback snapshot arm performs 300 copies /14,745,600 bytes. Per-function rows are retained in `mutation-summary.json`; overall allocation totals include common setup and the extra snapshot argument, so they are not presented as isolated helper allocations.

Commands were run from the P1 worktree after sourcing `/home/epentland/.config/mylang/dev-env.sh`, with `TMPDIR=$PWD/.tmp/lox-eda-parity/P1/final-common-001/tmp`, private caches below that scratch root, and shared build-slot admission:

```sh
compiler=/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/coordinator/common-001/install/bin/mylang
scripts/build-slot.sh build "$compiler" build .tmp/lox-eda-parity/P1/final-common-001/source/p1_allocation_probe.my -o .tmp/lox-eda-parity/P1/final-common-001/allocation-probe --experimental-zero-rc --release --counters --cache-dir .tmp/lox-eda-parity/P1/final-common-001/caches/allocation
scripts/build-slot.sh build "$compiler" build .tmp/lox-eda-parity/P1/final-common-001/source/p1_mutation_probe.my -o .tmp/lox-eda-parity/P1/final-common-001/mutation-probe --experimental-zero-rc --release --counters --cache-dir .tmp/lox-eda-parity/P1/final-common-001/caches/mutation
scripts/build-slot.sh build "$compiler" build .tmp/lox-eda-parity/P1/final-common-001/source/p1_mutation_failure_probe.my -o .tmp/lox-eda-parity/P1/final-common-001/failure-probe --experimental-zero-rc --release --counters --cache-dir .tmp/lox-eda-parity/P1/final-common-001/caches/failure
scripts/build-slot.sh build python3 experiments/lox-eda-parity-20261013/P1/final-common-001/run-allocation-probe.py .tmp/lox-eda-parity/P1/final-common-001/allocation-probe
scripts/build-slot.sh build python3 experiments/lox-eda-parity-20261013/P1/final-common-001/run-mutation-probes.py .tmp/lox-eda-parity/P1/final-common-001/mutation-probe .tmp/lox-eda-parity/P1/final-common-001/failure-probe
```

These results requalify the bounded probes on the final common compiler. They are allocation/ownership evidence, not runtime timings or a 60-case benchmark claim. The coordinator owns the combined 93-test application suite, which P1 did not duplicate. No Guardian feedback log was written.
