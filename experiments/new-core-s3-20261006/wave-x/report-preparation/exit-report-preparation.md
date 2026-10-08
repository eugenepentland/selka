# Preparation for the S3 §7 exit report

Read-only snapshot of integration `b2ab4462a85c5c6aafbffdd346ab3a6e0da40abe` on `codex/new-core-s3-integration`, 2026-10-06. This file collects completed Wave A/B facts. It does **not** qualify S3-A, claim S3-X complete, or authorize S4. No integration/shared/Guardian file or compiler was changed, and no build/gate was run for this preparation.

## Exact package identities

Requested foundation: `92590700cb0bf5e4dc19cc1f0c836c3a41693f64` on `codex/new-core-s2-integration`. Wave A review report: `3d0bfd23b73b3a90bd6ce8af4caa8fcba18a51b2`. The user’s Wave B go starts there; bootstrap `8918de74720f0832dabe5802c110cd0518324cf5` changes default core shards 4→8 and records the bootstrap evidence.

| Package | Foundation | Final source | Qualification/evidence | Integration merge |
|---|---|---|---|---|
| S3-0 | `92590700cb0bf5e4dc19cc1f0c836c3a41693f64` | `dc1a583109be06c3e699a433be24cbcd6e5d3816` | `643858e3da7b1e3a2c4f31b1a13430ab3906cd0e` | `e39ad11d3b2d95d537b1526f7e4abfb4b0feeb76` |
| S3-L | `92590700cb0bf5e4dc19cc1f0c836c3a41693f64` | `225bee07da44dc57ae322d3b6c1f0f68aebb404f` | `225bee07da44dc57ae322d3b6c1f0f68aebb404f` | `f5ba28e585a7c06cb80dc6c81b96fa946c55ad2a` |
| S3-T1 | `8918de74720f0832dabe5802c110cd0518324cf5` | `ade0ce29d743aa5168ce14417e2aee6bb11a11f6` | `0b48e921766b31dc70a8f1b66374bb8c7973bc5c` | `2e4f0f512a6d8a1f5df70602861890360ee6e2ec` |
| S3-T2 | `8918de74720f0832dabe5802c110cd0518324cf5` | `52a9e1ef8ca00775a5d4ac1e24b6f920eacf9766` | `5d2849ff54351cfa03d6797c6454ca376274ce7f` | `fb9bff998fb1d31f056ad0fe0ace9230bd033391` |
| S3-C | `8918de74720f0832dabe5802c110cd0518324cf5` | `9637eb9a1aa4af8ee0ecd88838ceed09b228d812` | `6bac5b165b1f526127c93dcc1dbd157b0ed6334d` | `f1319a774d638c664de9f02bb27098650a13249b` |
| S3-M | `8918de74720f0832dabe5802c110cd0518324cf5` | `93030b84e1538abc35aefa6984e3b00cc7dcc958` | `d5be46e4719596080683e87e0638967a3301a6d8` | `da321c5711dff87fc5bc5aca9fca072647847025` |
| S3-C runner | `722fe485165028ce04480c52791c5dc7b4cacfe3` | `d54e3dae0b477255841a23d3207f2d458aa42057` | `e69c9f9855ff0d00877f3f279c640a1d3551aa64` | `f1319a774d638c664de9f02bb27098650a13249b` |

S3-T2 first implementation is `71cfa45aecf9a81027494989d0c4bdb17a613b00`; `52a9e1ef8` adds the final fixture correction. M scalar foundation is `8535295d958c7522c58ed1e8106eb4df95cc92d5`, graph/place checkpoint `c87e4fb0276fdaf1b9d91de6da2b6e54106010c0`. C initial source is `722fe485165028ce04480c52791c5dc7b4cacfe3`, after copied scalar dependencies `10ee0ab8`/`c553177e`. Runner forks that C checkpoint and later qualifies on combined C/M source `9637eb9a1aa4af8ee0ecd88838ceed09b228d812`; its evidence commit is the second parent of C qualification `6bac5b165`. Thus runner has no separate integration merge.

The user’s review decisions are `e50e508a4c4da2aefb69e0bcc0ed39f0b855b9f4`. Approved old ENV correction: `4747ad071803589f99137d2ecf7641203120e09f`; qualified old source: `65036fe792ef540392d0eb00c41c9ec71c7b2c82`. Old full gate04 passed 138/138 steps, 3522/34118 tests (30596 intentional skips), exit0 with RSS validation clean. It qualifies the ENV oracle, **not** later runner SPEC/manifests/fixtures or the final stage.

Qualified corrected oracle hashes: compiler `d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`; QBE `b6139650a99b39131cd791fa1fdc84c09472dc303930bbadd3f8a5348487af4c`. Preserve the original invalid context-as-name answer only as historical evidence.

## Completed gates, distinct from final exit gates

| Source/checkpoint | Core suite | Strict conformance per mode | Uncontended Core rebuild |
|---|---|---|---|
| Wave A integration `f5ba28e5` | 219 tests,8 shards,68.31s,max66.81s | 1243 matching/0 mismatching/275 unsupported of1518 | 1.67s |
| T1 merge `2e4f0f512` | 221 tests,16 shards,75.67s,max71.68s | 1310/0/208 | 0.87s |
| T2 merge `fb9bff998` | 228 tests,16 shards,80.98s,max71.16s | 1405/0/113 | 3.42s |
| Combined C package `9637eb9a1` | 254 tests,32 shards,127.03s,max68.26s | 1518/0/0 | 3.30s |
| C integration `f1319a774` | 254 tests,32 shards,103.18s,max50.77s | 1518/0/0 | 3.52s |
| M integration `da321c571` | 254 tests,32 shards,97.92s,max59.22s | 1518/0/0 | cached0.02s |

Last two integration receipts are `wave-b/integration/resume-after-{c,m}-run01/summary.json`; installed Core hash `1efc118073106ded6c124376af3920968498c335b983f6f1d31472149ede1038`. Times exclude admission. Core tests have gate+build slots and checked RSS; meaningful rebuild excludes concurrent builds/gates. Default8 remains a convenience: package evidence required16 and then32 to keep every shard<90s. Final new tests require a fresh held suite under300s/90s; the cached M install is not a fresh dev-loop rebuild measurement.

T1 text50:750 comparisons,0 mismatches/refusals/facts/leaks. T2 number50:750/0. M final s0/s1/functions50 each:750/0 (150 sources,2250 comparisons total). C37 deterministic provider checks and runner24 complete-report matches pass; I/O adds no random fuzz kind. Runner exact evidence checks every reason/property field, actual shrinking/discards, Result grading, reset of clock/entropy/files/environment, default name seeds and signals/silent native exits. Trial overhead at default100 runs is median11.81ms (1000 runs104.40ms); `processes` counts outer batches, while Core also forks each actual trial.

These package checks do not replace the fresh nine-kind200 matrix, final integrated old gate, 40-row/per-size ratio and inner-loop count checks, or final full leak/fact sweeps. S3-X tooling documents25800 required native comparisons for1800 sources, plus a supplementary split-key200 sweep/3000 comparisons. Tool preparation is not executed qualification.

## Float cold cost and complete cache key

T2 binding Wave A obligation is satisfied in `wave-b/s3-t2/float-cold-final/summary.json` and `runtime-cache-key.json`:

- First program, fresh object directory and fresh Zig global cache for the unit:3.116963197942823s total; formatter unit0.9655902560334653s; one compilation.
- Different next source reusing the object:0.11394167505204678s total; zero formatter compilations.
- Simulated version suffix invalidates the object:1.0238852428738028s total; formatter0.8814565688371658s. This is not a second installed Zig version.
- Executing Zig:`0.17.0-dev.1683+5ceec001b`. Object key:`714db03fe3fa391c9b5a852fe8b845a55a788be7cbede44ff2b90ac1dbe77348`.
- Fingerprint:Blake3 domain-v1+NUL, executing Zig version+NUL, every target/build option+NUL, helper name+NUL and its complete Blake3 digest. Recorded SHA256 helpers: `core_number_text.zig=e2e4b6ce5941c0e80dac7f064196f93869a1f2c325bb9b3e8914805e8ffee046`; `core_number_parse.zig=53ad97811d5888d72102b60cb7a6535ba8718900b360ca39d5b30f01df3e0e1e`; `core_number_format.zig=002d54fdcf9409c54c43006ffc5da860cf730e6c80eb77021f1278f1719424a7`.
- Explicit options:`-target x86_64-linux-gnu -mcpu baseline -O ReleaseFast -fPIC -fno-stack-check -fno-stack-protector -lc`. Per-program staging, unique partial objects and atomic publication avoid concurrent cache misses corrupting the shared object. Content/target/options invalidation also have pure tests. Integer-only programs do not pay the float unit.

## Coverage and named exclusions

Inherited four-corpus counts: S2 base3185/3627; D2/Wave A3213/3595; T1 3324/3595; T2 3456/3595; C combined3589/3595. D2 removed46 names (6 accepted), added14 accepted names and admitted20 retained names; no accepted-name regression, denominator-32. The active conformance total changes1540→1518 because archived35 stored-view tests become12 snapshots and one immediate-membership case is added.

Later asset-preserving tool check at `42e9a564dc50a694177fef6d1708ba91689b92f0` is separate: per-corpus sums **3633/3639** (examples202/207,parity123/123,language3168/3168,runtime140/141), globally deduplicated **3410/3416**. Four children exit0. Do not compare these directly with earlier sums without retaining the changed asset/scratch-entry context and name accounting. The restored assets clear the four old scratch `E_EMBED` failures. Final source still owes fresh before/after coverage evidence.

All six remaining function refusals are bodyless declarations: extern `abs`, `floor`, `main::runtime_bench_now`; Host `io::length`, `io::byte`, `io::put`. They produce11 raw occurrences across imports; linked calls are exercised by provider fixtures/benchmarks. No language-test or parity function is refused. Seven example frontend `E_MODULE_NAME` failures remain from flattened user-module context: `examples/corpus/invoice/{catalog,money,pricing}.my`, `examples/interface-files/shop/{billing,money}.my`, `examples/input-values/config/values.my`, `examples/modules/shared/units.my`. Treat them as coverage context failures, not executed successes.

The S4 execution exception is `tests/lang/migrated/propagation.my`, importing `propagation_case_1` through `_9`. Its nine exact top-level names are:
- `test_nested_results_can_be_propagated_repeatedly_1`
- `test_nested_results_can_be_propagated_repeatedly_2`
- `test_nested_results_can_be_propagated_repeatedly_3`
- `test_option_propagation_unwraps_some_and_forwards_1`
- `test_option_propagation_unwraps_some_and_forwards_2`
- `test_try_unwraps_success_and_remaps_errors_betwee_1`
- `test_try_unwraps_success_and_remaps_errors_betwee_2`
- `test_try_wraps_a_mismatched_error_into_the_matchi_1`
- `test_try_wraps_a_mismatched_error_into_the_matchi_2`

N6 excludes **118 retired arena cases**. Entire retired modules: `arena_class_escape`, `arena_managed`, `arena_regions`, `arena_scopes`, `rc_arena_values`; individual arena-named cases also occur in other modules. The complete exact127-name exception inventory (118 arena+9 S4) is `wave-b/integration/resume-exceptions-run01.json`; do not describe only the five modules as the whole retirement list.

## Remaining compiler/runtime limits and invariants

- User modules/interfaces, `.myi`/per-module Core IR caches and incremental compilation are S4. Standard-library `strings`/`json` use whole-program merged checked source and original source/asset authority. Lox/EDA ports remain S4. External Lox two-statement migrations remain unapplied: `resolver.my:195,251,259`, `heap.my:300`.
- Aggregates occupy the first64 parameter positions (`E_PARAMETER_POSITION`); scalars are unlimited. Source extern remains its scalar/pointer Host-erasing contract. Direct scalar Option C/Zig return ABI is qualified only on frozen x86-64 SysV. Host copied-value lowering rejects recursive/boxed or unsupported copied types, including Unit parameters; no generic Host aggregate ABI is implied.
- Two precise interior-mut refusals remain: `interior mut place changed while its index or key was evaluated`; `interior mut argument ancestor changed by a later interior write`. All41 required existing places execute. Deeper pin/publication protocols were deliberately not guessed from callee effects or value equality.
- Text case/classification preserves old ASCII rules. Immutable byte views materialize owned slices; D2 dictionary projections are immediate-use only (`E_VIEW_STORED` at declarations/storage), with key membership hash probes and value/item scans. Existing old view-storage implementation is unreachable and may remain until S5.
- Environment:64 distinct raw names,128bytes/name,16KiB getter values. Names collect bounded raw entries before UTF8 filtering. An explicit built-in getter allowlist filters even without `--restrict`. Provider opaque context is never a name source (`ENV-NAMES-GRANT-1`).
- Scoped FS/network:8roots,8endpoints,256provider handles,64KiB transfer/snapshot,256snapshot entries,4094byte paths. In-memory stand-ins:256handles,64MiB backing,matching path/snapshot bounds. Runtime owners:1024open handles per filesystem/network family; file/read-all accumulation64MiB. Deterministic tests use private directories and stand-ins, with no real network.
- Host defaults:10000calls,1000000work,65536nodes,64levels,1MiB payload. Published hard bounds:100000nodes,128levels,64MiB payload; fixed packed scratch<=1MiB. Registry-specified budgets remain enforced.
- Property runner retains old default100runs,10xdiscard ceiling,2000shrink attempts,4096input batch,60s whole-batch timeout; generation max top-level size100,node budget4096,variant depth12; candidate ceiling1024 (nested128),batch transport500000nodes. Class identity values, constructor-only domains, function values and Host are deliberately nongeneratable under the old primary type contract. Each actual trial forks and resets stand-ins.
- IR stays byte-identical to `dc1a5831`; no record phi is emptied. Formats remain `module-interface-v5`, `check-summaries-v6`, `mutation-v2`. Runtime metadata is transient and only exact compiler `runtime_c` linkage confers authority; ordinary extern/name/string lookalikes do not. Every fact/uniqueness optimization retains verification of its premise. Unit-shard RSS ceiling2.5GiB remains checked separately from a green build summary.
- No push or main merge is allowed. The old compiler remains default until S5. S3 must finish with the final §7 report and stop for the user’s S4 go/stop.

Primary evidence: `wave-a/REPORT.md`; `wave-b/s3-t1/README.md`; `wave-b/s3-t2/README.md` and cache/cold JSON; `wave-b/s3-c/REPORT.md` and `resume-combined-qualification.json`; `wave-b/s3-m/REPORT.md` and `final-source-contract.json`; `wave-b/s3-runner/REPORT.md`; integration merge receipts, exception inventory and asset-preserving coverage receipt. Use fresh A/X identities/results when they arrive rather than relabeling these historical package results.
