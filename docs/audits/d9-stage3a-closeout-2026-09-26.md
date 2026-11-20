# D9 stage 3a close-out, 2026-09-26

Stage 3a implements the opt-in `--value-semantics` rules on the tracing collector. The switch is off by default. It is accepted by check, build, run, run-project and test, and by project configuration. The switch is part of compiler and test cache identities. Transfers of mutable collections use one `myl_qbe_value_copy` hook after stage 2's move and borrow analysis. `mut` record parameters are inout; writes through copied loop and match bindings or call results receive the new diagnostics. `class` and `Cell` remain shared. The full rule and its limits are in [value-semantics.md](../value-semantics.md).

The branch began at `60b668cf`, then merged current main `b292660a` with real two-parent merge `6b5950de`. Gate testing found that the new copy runtime unit can call `myl_qbe_fail_allocation` but was built without the frame pointers a QBE trap trace needs. Commit `9cfdf551` adds that unit to the frame-pointer build group and pins the rule with `VALUE-SEMANTICS-9`. This preserves the runtime's trap trace across an allocation failure.

## Correctness and compatibility

- The dedicated value-semantics guest suite passes **31/31** under `--value-semantics --gc-stress`. Zig and CLI checks of the switch, checker rules, ownership placement and project configuration are part of the full gate below.
- With the switch off, emitted code-bearing IL is byte-identical to clean main for **44/44** parity source files. The [hash record](../../experiments/d9-stage3a-20260926/il-identity.json) compares each function, entry and runtime-data section from `emit-qbe` or `emit-project-qbe`.
- `tests/lang` with the switch off passes the **same 642 named tests** as clean main: 642 passed, none failed or dropped, across 113 programs.
- `tests/lang --value-semantics` passes 558 tests, fails 18 tests whose assertions observe aliases, and refuses 5 programs at check time under the new rules. The legacy tests are left for stage 3f, where the default changes.

The 18 alias-dependent failures are:

| Program | Test names |
|---|---|
| `arena_managed` | `test_escape_preserves_a_cycle_through_a_record_field`; `test_escape_shares_objects_that_already_live_in_the_enclosing_region` |
| `byte_buffer` | `test_a_buffer_alias_observes_appends_while_a_snapshot_does_not`; `test_buffers_are_traced_through_record_fields_lists_and_generics`; `test_growth_past_the_segment_threshold_keeps_every_octet` |
| `dictionary_hashing` | `test_a_missed_read_never_shadows_a_key_inserted_before_the_write` |
| `field_augmented` | `test_augmented_addition_to_a_list_field_extends_in_place` |
| `keyed_sorting` | `test_sort_key_orders_in_place_and_keeps_equal_keys_in_input_order` |
| `managed_values` | `test_managed_dictionary_source_literals_indexing_1` |
| `surface_collections` | `test_list_methods_indexing_and_indexed_assignment` |
| `option_narrowing` | `test_option_narrowing_collection_methods_and_index_writes` |
| `option_niche` | `test_an_escaped_graph_keeps_its_optional_links` |
| `python_values` | `test_python_values_dictionary_literal_growing_aliases_and_arbitrary_method_receivers` |
| `scalable_sorting` | `test_in_place_sort_scales_and_preserves_aliases`; `test_text_sort_in_place_matches_sorted_through_aliases_and_fields` |
| `sets` | `test_a_set_is_shared_on_assignment_and_written_through_mut` |
| `stable_sorting` | `test_sort_orders_a_large_list_in_place_for_every_alias`; `test_text_sorts_in_place_through_every_alias` |

The five checker refusals are `builtin_context.my:38` (`E_MUTATION_MARKER`: a copy of a `mut` class field is changed without storing it back), `properties.my:131` and `test_capabilities.my:28` (`E_IMMUTABLE`: a match-bound record is passed as `mut`), and `python_collections.my:130` and `python_core.my:112` (`E_VALUE_TEMPORARY_WRITE`: a returned value is changed). Each follows a documented value-semantics rule.

## Switch cost

Instruction ratios are switch on divided by switch off, using the same Debug compiler and the same source. The harness built 27 parity programs, three schematic inputs and 13 scripts of the adapted Lox VM port for each backend, checked their outputs, and then took the median of three `perf stat -e instructions:u` runs pinned to CPU 10. QBE used the default guest build. LLVM used `--backend llvm --llvm-opt 3 --lto`; the compiler itself was Debug, not ReleaseFast. The raw [QBE](../../experiments/d9-stage3a-20260926/qbe-instructions.json) and [LLVM](../../experiments/d9-stage3a-20260926/llvm-instructions.json) samples are committed. QBE was rebuilt and remeasured after the frame-pointer fix.

| Workload | Programs | QBE geomean | LLVM geomean |
|---|---:|---:|---:|
| Parity | 27 | 1.0740× | 1.0003× |
| Schematic | 3 | 60.6477× | 133.4558× |
| Lox VM | 13 | 1.3977× | 1.6988× |

All 43 measured program outputs matched in both modes and both backends, including each schematic SVG. The largest parity ratio is QBE `matmul` at 2.9153×; the largest Lox VM ratio is `closures` at 1.9296× on QBE and 2.7700× on LLVM. Schematic has only three static copy calls in emitted IL. Two are in `schematic::build`, where the returned record takes independent copies of the read-only `nodes` and `pinout` document trees. These eager deep copies account for most of the schematic cost; stage 3b replaces the hook with copy-on-write. These ratios are informational for stage 3a, with no performance threshold in its acceptance criteria.

## Gate

After the frame-pointer correction, the full gate passed: `zig build test --summary all` (91/91 steps, 2,066 executed tests, including doc coverage and doctests), `zig build test-qbe --summary all` (49/49 steps, 424 tests), `zig build test-qbe-build --summary all` (29/29 steps), and `zig build fmt-check`. The four commands ran under the shared D9 gate lock, with worktree-local `TMPDIR` and Zig cache, through `scripts/build-slot.sh`.
