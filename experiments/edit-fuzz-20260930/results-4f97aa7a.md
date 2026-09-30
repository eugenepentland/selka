# Edit-fuzz results against compiler 4f97aa7a

Compiler: ReleaseFast build of `claude/symbol-invalidation` 4f97aa7a
(`.tmp/rf-symbol/bin/mylang`, built 12:12 UTC). Tool: `edit_fuzz.py` at commit 447ee10e (the last
edits after the runs launched removed one unused function and made the generated `replay.sh` use
`cp -rL`; no edit logic changed). Lox port: 18 modules, 5.5k lines, copy of
`benchmarks/lox/ports/mylang`. The box was heavily loaded by other agents (load average 30-46),
so wall-clock numbers below are noisy and only the module counts are meaningful.
Data: `results-4f97aa7a.json` (`standard` and `follow_up` groups, every row kept).

## Verdict

**One bug found, no silent stale link.** In all three standard Lox `--gc-runtime` runs the
incremental module-by-module build failed with `mylang: host failure: InvalidNativeManifest`
after a `record-field-add` edit while `--whole-program` built the same tree (verdict
`incremental-failed`). It is loud, not a byte mismatch, it predates the symbol-cutoff commits,
and it reproduces with three tiny modules under RC and GC. Details, reproducers and the
minimized edit list: `finding-invalid-native-manifest/README.md`.

Everything else matched: 589 of 592 standard steps and 660 of 660 follow-up steps produced
byte-identical executables, or failed identically in both builds with identical error sets (no
step had different diagnostics in the two builds). No executable differed byte for byte in any run.

## Standard matrix (3 seeds x 60 steps, Lox and synthetic, RC and `--gc-runtime`)

`run_matrix.sh COMPILER OUT 60`; seeds 1-3. The three Lox `--gc-runtime` runs stop at the
finding (steps 19, 18 and 15, reproducers kept), so they contribute 52 of their 180 steps.
Synthetic projects have 6 to 10 modules including `main` (seed 1: 8, seed 2: 7, seed 3: 9).

### Runs

| project | runtime | seed | modules | steps | built | on module path | off path | matched | findings | compiled mean/median/max | wall s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| lox | gc | 1 | 18 | 19 | 14 | 14 | 0 | 18 | 1 | 1.6 / 1 / 6 | 62.3 |
| lox | rc | 1 | 18 | 60 | 51 | 51 | 0 | 60 | 0 | 5.0 / 4 / 13 | 203.7 |
| lox | gc | 2 | 18 | 18 | 16 | 16 | 0 | 17 | 1 | 2.7 / 1 / 16 | 61.9 |
| lox | rc | 2 | 18 | 60 | 56 | 56 | 0 | 60 | 0 | 6.1 / 4 / 16 | 214.5 |
| lox | gc | 3 | 18 | 15 | 11 | 11 | 0 | 14 | 1 | 1.7 / 1 / 7 | 53.0 |
| lox | rc | 3 | 18 | 60 | 48 | 48 | 0 | 60 | 0 | 4.5 / 4 / 13 | 184.5 |
| synthetic | gc | 1 | 8 | 60 | 52 | 52 | 0 | 60 | 0 | 4.4 / 5 / 8 | 100.0 |
| synthetic | rc | 1 | 8 | 60 | 52 | 52 | 0 | 60 | 0 | 4.7 / 5 / 8 | 27.3 |
| synthetic | gc | 2 | 7 | 60 | 55 | 55 | 0 | 60 | 0 | 2.6 / 1 / 7 | 104.1 |
| synthetic | rc | 2 | 7 | 60 | 55 | 55 | 0 | 60 | 0 | 3.1 / 2 / 7 | 35.3 |
| synthetic | gc | 3 | 9 | 60 | 56 | 56 | 0 | 60 | 0 | 3.6 / 3 / 9 | 144.2 |
| synthetic | rc | 3 | 9 | 60 | 56 | 56 | 0 | 60 | 0 | 4.1 / 4 / 9 | 36.3 |

Total: 592 edit steps, 522 built (88%), 589 matched the oracle, 3 findings, 67 revert checks.

### Edit kinds

| kind | applied | built | failed | off module path | compiled mean/median/max |
|---|---|---|---|---|---|
| int-literal | 63 | 63 | 0 | 0 | 3.3 / 3 / 10 |
| wrap-return | 36 | 36 | 0 | 0 | 3.8 / 3 / 9 |
| use-added | 36 | 36 | 0 | 0 | 3.0 / 2 / 9 |
| add-private-fn | 34 | 34 | 0 | 0 | 1.4 / 1 / 6 |
| const-value | 34 | 34 | 0 | 0 | 6.4 / 6 / 14 |
| record-field-add | 31 | 28 | 3 | 0 | 5.7 / 6 / 12 |
| helper-call | 30 | 30 | 0 | 0 | 6.8 / 6 / 16 |
| add-public-fn | 28 | 28 | 0 | 0 | 5.4 / 5 / 12 |
| insert-statement | 27 | 27 | 0 | 0 | 2.5 / 2 / 7 |
| remove-added | 25 | 25 | 0 | 0 | 3.8 / 4 / 12 |
| add-default-param | 21 | 21 | 0 | 0 | 5.6 / 5 / 13 |
| start-alloc | 21 | 21 | 0 | 0 | 5.0 / 4 / 13 |
| float-literal | 19 | 19 | 0 | 0 | 3.4 / 4 / 10 |
| rename-public-def | 19 | 7 | 12 | 0 | 5.7 / 4 / 14 |
| add-required-param | 19 | 0 | 19 | 0 | - |
| drop-record-field | 17 | 0 | 17 | 0 | - |
| add-const | 14 | 14 | 0 | 0 | 2.1 / 1 / 12 |
| noop | 14 | 14 | 0 | 0 | 0.0 / 0 / 0 |
| remove-public-fn | 13 | 6 | 7 | 0 | 3.3 / 4 / 4 |
| move-function | 13 | 13 | 0 | 0 | 1.8 / 1 / 6 |
| toggle-visibility | 12 | 12 | 0 | 0 | 6.2 / 5 / 13 |
| rename-added | 11 | 11 | 0 | 0 | 4.3 / 4 / 8 |
| whitespace | 11 | 11 | 0 | 0 | 1.2 / 1 / 2 |
| comment | 10 | 10 | 0 | 0 | 1.8 / 1 / 4 |
| record-field-remove | 8 | 8 | 0 | 0 | 7.6 / 8 / 13 |
| change-return-type | 7 | 0 | 7 | 0 | - |
| change-field-default | 6 | 6 | 0 | 0 | 7.0 / 7 / 8 |
| break-type | 5 | 0 | 5 | 0 | - |
| stop-alloc | 5 | 5 | 0 | 0 | 6.0 / 8 / 9 |
| change-default | 3 | 3 | 0 | 0 | 9.0 / 9 / 9 |

### Compiled-module counts (engaged incremental builds)

| compiled | builds |
|---|---|
| 0 | 14 |
| 1 | 134 |
| 2 | 66 |
| 3 | 49 |
| 4 | 74 |
| 5 | 44 |
| 6 | 33 |
| 7 | 36 |
| 8 | 24 |
| 9 | 19 |
| 10 | 4 |
| 11 | 2 |
| 12 | 9 |
| 13 | 7 |
| 14 | 3 |
| 16 | 4 |

### Why edits failed to build

| kind | diagnostic | count |
|---|---|---|
| add-required-param | E_ARITY | 19 |
| rename-public-def | E_UNKNOWN_SYMBOL | 12 |
| drop-record-field | E_UNKNOWN_FIELD | 9 |
| drop-record-field | E_ARITY | 8 |
| remove-public-fn | E_UNKNOWN_SYMBOL | 7 |
| change-return-type | E_TYPE | 7 |
| break-type | E_TYPE | 5 |

Failed steps where the two builds reported different error sets: 0.

### Findings

- lox seed 1 step 19 `record-field-add`: incremental-failed - incremental: mylang: host failure: InvalidNativeManifest | whole: built ok
- lox seed 2 step 18 `record-field-add`: incremental-failed - incremental: mylang: host failure: InvalidNativeManifest | whole: built ok
- lox seed 3 step 15 `record-field-add`: incremental-failed - incremental: mylang: host failure: InvalidNativeManifest | whole: built ok

## Follow-up runs (past the finding)

To keep hunting beyond the known bug the Lox `--gc-runtime` runs were repeated with
`--exclude-kinds record-field-add,record-field-remove,change-field-default,drop-record-field`
(seeds 1-5, 60 steps, run before `--edits-per-step` existed; the logic is otherwise identical),
plus Lox RC seeds 4-5 (60 steps), and runs with several edits per step: Lox seed 6 RC (2 edits per
step, 40 steps), Lox seed 6 `--gc-runtime` (2 edits, same exclusions, 40 steps), synthetic seeds 5-6
RC and `--gc-runtime` (3 edits per step, 40 steps). With several edits in a step a kind's `failed`
count is shared by every kind in that step, so the per-kind failure counts overstate.

### Runs

| project | runtime | seed | modules | steps | built | on module path | off path | matched | findings | compiled mean/median/max | wall s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| lox | gc | 1 | 18 | 60 | 50 | 50 | 0 | 60 | 0 | 4.0 / 1 / 16 | 475.0 |
| lox | gc | 2 | 18 | 60 | 56 | 56 | 0 | 60 | 0 | 2.5 / 1 / 16 | 269.7 |
| lox | gc | 3 | 18 | 60 | 55 | 55 | 0 | 60 | 0 | 4.9 / 1 / 17 | 532.2 |
| lox | gc | 4 | 18 | 60 | 51 | 51 | 0 | 60 | 0 | 2.9 / 1 / 13 | 489.7 |
| lox | rc | 4 | 18 | 60 | 54 | 54 | 0 | 60 | 0 | 5.7 / 4 / 16 | 263.1 |
| lox | gc | 5 | 18 | 60 | 51 | 51 | 0 | 60 | 0 | 4.2 / 1 / 16 | 216.3 |
| lox | rc | 5 | 18 | 60 | 56 | 56 | 0 | 60 | 0 | 4.9 / 4 / 16 | 565.4 |
| lox | gc | 6 | 18 | 40 | 28 | 28 | 0 | 40 | 0 | 7.2 / 3 / 15 | 112.2 |
| lox | rc | 6 | 18 | 40 | 32 | 32 | 0 | 40 | 0 | 8.8 / 10 / 15 | 135.8 |
| synthetic | gc | 5 | 8 | 40 | 30 | 30 | 0 | 40 | 0 | 6.0 / 7 / 8 | 52.5 |
| synthetic | rc | 5 | 8 | 40 | 30 | 30 | 0 | 40 | 0 | 6.1 / 7 / 8 | 18.4 |
| synthetic | gc | 6 | 6 | 40 | 33 | 33 | 0 | 40 | 0 | 4.5 / 4 / 6 | 92.2 |
| synthetic | rc | 6 | 6 | 40 | 33 | 33 | 0 | 40 | 0 | 4.7 / 5 / 6 | 20.2 |

Total: 660 edit steps, 559 built (85%), 660 matched the oracle, 0 findings, 101 revert checks.

### Edit kinds

| kind | applied | built | failed | off module path | compiled mean/median/max |
|---|---|---|---|---|---|
| int-literal | 95 | 85 | 10 | 0 | 3.8 / 3 / 14 |
| wrap-return | 77 | 73 | 4 | 0 | 4.2 / 4 / 16 |
| use-added | 74 | 73 | 1 | 0 | 4.1 / 3 / 16 |
| add-private-fn | 70 | 59 | 11 | 0 | 3.7 / 2 / 13 |
| const-value | 68 | 63 | 5 | 0 | 8.8 / 8 / 15 |
| insert-statement | 68 | 68 | 0 | 0 | 3.9 / 4 / 14 |
| add-public-fn | 56 | 54 | 2 | 0 | 7.3 / 6 / 16 |
| add-default-param | 49 | 44 | 5 | 0 | 7.2 / 7 / 14 |
| start-alloc | 45 | 40 | 5 | 0 | 5.3 / 4 / 16 |
| rename-added | 38 | 35 | 3 | 0 | 5.9 / 5 / 16 |
| float-literal | 36 | 34 | 2 | 0 | 4.3 / 5 / 10 |
| add-const | 31 | 27 | 4 | 0 | 6.3 / 5 / 15 |
| toggle-visibility | 31 | 27 | 4 | 0 | 7.3 / 6 / 17 |
| record-field-add | 31 | 28 | 3 | 0 | 6.2 / 5 / 13 |
| helper-call | 29 | 26 | 3 | 0 | 4.4 / 3 / 14 |
| remove-public-fn | 29 | 8 | 21 | 0 | 6.6 / 6 / 13 |
| add-required-param | 26 | 2 | 24 | 0 | 8.0 / 8 / 8 |
| remove-added | 26 | 23 | 3 | 0 | 5.9 / 4 / 16 |
| move-function | 25 | 22 | 3 | 0 | 3.8 / 3 / 13 |
| break-type | 23 | 0 | 23 | 0 | - |
| whitespace | 23 | 21 | 2 | 0 | 4.5 / 4 / 12 |
| rename-public-def | 22 | 2 | 20 | 0 | 5.0 / 5 / 5 |
| change-return-type | 20 | 0 | 20 | 0 | - |
| comment | 16 | 16 | 0 | 0 | 2.8 / 3 / 6 |
| change-field-default | 13 | 9 | 4 | 0 | 5.6 / 5 / 10 |
| change-default | 12 | 12 | 0 | 0 | 5.3 / 4 / 13 |
| stop-alloc | 9 | 9 | 0 | 0 | 3.9 / 3 / 8 |
| record-field-remove | 8 | 6 | 2 | 0 | 6.0 / 3 / 14 |
| noop | 6 | 5 | 1 | 0 | 4.4 / 0 / 15 |
| drop-record-field | 4 | 0 | 4 | 0 | - |

### Compiled-module counts (engaged incremental builds)

| compiled | builds |
|---|---|
| 0 | 3 |
| 1 | 183 |
| 2 | 54 |
| 3 | 35 |
| 4 | 61 |
| 5 | 37 |
| 6 | 38 |
| 7 | 14 |
| 8 | 29 |
| 9 | 6 |
| 10 | 4 |
| 11 | 21 |
| 12 | 15 |
| 13 | 35 |
| 14 | 9 |
| 15 | 3 |
| 16 | 11 |
| 17 | 1 |

### Why edits failed to build

| kind | diagnostic | count |
|---|---|---|
| (several edits in one step) | E_TYPE | 21 |
| (several edits in one step) | E_UNKNOWN_SYMBOL | 18 |
| (several edits in one step) | E_ARITY | 15 |
| add-required-param | E_ARITY | 12 |
| remove-public-fn | E_UNKNOWN_SYMBOL | 10 |
| change-return-type | E_TYPE | 9 |
| rename-public-def | E_UNKNOWN_SYMBOL | 8 |
| break-type | E_TYPE | 7 |
| drop-record-field | E_UNKNOWN_FIELD | 1 |

Failed steps where the two builds reported different error sets: 0.

## Notes

- Valid-edit rate 88% (standard) and 85% (follow-up; several edits per step fail more often). Every
  failing step is one of the deliberately interface-breaking kinds (`add-required-param`,
  `remove-public-fn`, `rename-public-def`, `change-return-type`, `drop-record-field`, `break-type`) and
  only when something uses the symbol; those give the error-path coverage: a caller nobody edited
  reports the error in the incremental build exactly as in the whole-program build, and the
  incremental build of the reverted tree reproduced the last good executable in every one of the
  168 revert checks.
- No edit left a warning in any run, so every build stayed on the module path (`off path` 0). The
  tool reverts such an edit (a warning anywhere, for example `W_UNUSED_BINDING` on an unused
  parameter or `W_UNUSED_IMPORT`, makes `--report` omit `module_build` and the build takes the
  whole-program path even on unchanged rebuilds; found while building the tool, see README).
- Compiled-module counts (of 18 on the Lox port, modules recompiled by the incremental build):
  under RC the per-run median is 4 (range 4 to 9.5 with two edits per step) and the maximum 16;
  under `--gc-runtime` the per-run median is 1 (3 with two edits per step) and the maximum 17.
  RC recompiles more because allocation facts fan out to callers; that difference is what the
  `start-alloc`, `stop-alloc` and helper edits expose. A comment, whitespace or private-body edit
  typically compiles 1 module, a `noop` 0, adding a public function or changing a widely used
  const 5 to 14. Synthetic projects (6 to 10 modules): per-run medians 1 to 7.
- The mismatch path itself was checked with `sabotage.sh` (a wrapper compiler that corrupts the
  incremental executable after a `start-alloc` edit): the fuzzer reported `binary-differs`,
  wrote the reproducer, `replay.sh` reproduced it, and `--minimize` reduced 12 patches to the one
  `start-alloc` patch.
- Determinism: two runs of synthetic seed 3 produced identical rows; the three Lox
  `--gc-runtime` finding runs were repeated with the final tool and stopped at the same steps.
