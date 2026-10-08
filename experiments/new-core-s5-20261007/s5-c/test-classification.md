# S5-C input: classification of `src/*_test.zig` (static read, 2026-10-07, base 7bb4b90b)

This is a static pre-classification for S5-C's two agents. The classes that count are the
ones in the plan (§4 S5-C), decided when a retargeted test fails. Counts are approximate
(±1–2 per file).

**Classes:**
- **R:** builds and runs programs; survives on the new core.
- **F:** front end only; stays as it is.
- **O:** asserts old back-end internals; deleted.
- **X:** a retired feature; deleted.
- **M:** mixed.

| Class | Files | Tests in files with this primary class | Tests of this class across all files |
|---|---|---|---|
| R | 61 | 446 | 445 |
| F | 85 | 675 | 814 |
| O | 112 | 745 | 815 |
| X | 8 | 84 | 126 |
| M | 12 | 250 | — |

**All 109 files that import `native_execute.zig` need the retargeted runner.** That
includes 23 F-majority files with R tests (interfaces R13, embed, prelude_scalar,
python_syntax, domain_equality).

## R (61)

arrays 5 (R2 F2 O1); builtin_context 6 (R5 F1); byte_builder 11 (R10 F1); callbacks 11
(R6 F3 O2); const_lengths 4 (R2 F2); contracts 10 (R6 F3 X1); domain_codecs 7 (R3 F3 O1);
domains 7 (R4 F2 O1); dotted_modules 9 (R6 F3); environment 16 (R12 F4); error_trace 10
(R8 O2); exit_status 6; external_capabilities 9 (R6 F2 O1); for_range 1; generic_arrays 8
(R4 F4); generic_codecs 3 (R2 F1); generic_concrete 9 (R6 F3); generic_execution 7 (R3 F3
O1); generic_inference 2; generic_results 6 (R5 F1); integer_operations 3 (R2 F1);
integers 13 (R9 F4); io_files 16 (R12 F3 O1); iteration_place 10; loop_exit 2 (R1 X1);
managed_values 1; nominal_environment 2; nominal_instances 10 (R6 F4); nominal_providers 4
(R3 O1); prelude_builtins 17 (R13 F4); propagation 5 (R2 F2 O1); python_arrays 4 (R2 F2);
python_assert 4; python_bytes 14 (R10 F2 O1 X1); python_collections 4 (R2 F1 X1);
python_strings 1; python_surface 5 (R4 F1); records 8 (R4 F4); resource_io 6 (R4 F1 O1);
resource_source 17 (R13 F3 O1); results 8 (R7 F1); semantic_cache 55 (R40 F13 X2); sets 9
(R6 F1 X2); stand_ins 6 (R5 F1); standard_library 6 (R3 F3); stdlib_codecs 2; stdlib_json
4 (R3 O1); stdlib_math 3 (R2 F1); stdlib_path 2; stdlib_pool 2; stdlib_sort 4;
stdlib_strings 5; stdlib_time_random 4 (R3 X1); structural_constraints 14 (R7 F7);
surface_statements 3 (R2 F1); syntax_cache_large 1; syntax_cache 7 (R6 F1); tables 4 (R2
F2); typing_papercuts 4 (R2 F2); unit 5 (R3 F1 X1); variants 5 (R2 F2 O1).

## F (85)

affected_tests 2; allocation_budget 2; byte_literal 3 (R1 F2); check_cache 6; check_scale
19 (F18 X1); collections_fidelity 5 (R1 F4); constants 8 (R3 F5); context 12;
declaration_hints 10; declarations 7; diagnostic_fix 10; diagnostic_output 5;
diagnostic_recovery 4 (R1 F3); dictionary_views 9; domain_equality 8 (R3 F4 O1);
duplicates 5; embed 17 (R5 F11 O1); external_resources 12; float_operations 7 (R3 F4);
flow_inference 9 (F8 X1); format_spec 5; formatter 15 (R1 F14); friction_log 6;
frontend_cache 12; generic_api 7; generic_bodies 17 (R2 F15); generic_calls 5;
generic_instances 5; generic_providers 3; generic_requirements 7; generic_syntax 10;
headerless_import 4; import_policy 15; incremental 18; input_manifest 4; input_probe 2;
interface_files 10; interfaces 61 (R13 F47 O1); json_document 3; lint_config 2; lint_reach
2; lint_sentinel 3; lint_store 2; lint 12; memory_budget_frames 4; mut_exclusive 12 (F11
X1); named_constraints_namespace 5; navigation_scale 6; navigation 13; near_duplicates 10;
nominal_bodies 5 (R2 F3); nominal_layouts 11; nominal_provider_contracts 2;
nominal_templates 9; nominal_type_syntax 6 (R2 F4); number_literal 12; number_text 3;
option_methods 5; prelude_scalar 14 (R5 F8 O1); project 15; python_calls 7 (R3 F4);
python_comprehension 2; python_expressions 5 (R1 F4); python_generics 1; python_syntax 29
(R5 F24); python_text_surface 4 (R1 F3); python_variants 8 (R2 F6); quality 6;
recursive_resources 4; reference 13; runtime_values 2; scoped_providers 12;
sema_mut_arguments 2; semantic_project 5 (R2 F3); source_map 4 (R1 F3);
surface_collections 1; timings 1; tokens_dump 2; tuples 12 (R2 F9 X1); type_aliases 5 (R2
F3); typed_holes 7 (R3 F4); typed_json 10; value 5; view_cycles 5; zig_local_cache 1.

## O (112 files, 745 tests)

- **All `qbe_rc_*`** (52 files, 232 tests).
- **All other `qbe_*`, including `qbe`** (25 files, 278 tests).
- **All `rc_*`** (11 files, 108 tests).
- **C-runtime verify files:** `native_rc_codecs`, `native_rc_collections`, `native_rc_contract`,
  `native_rc_fast`, `native_rc_hold`, `native_rc_image`, `native_rc_stats` and `native_argv`.
- **Others:** aggref_abi 4, bytecode_inline 17, instruction 1, invalidation_matrix 4,
  invalidation 16, module_compile 8, module_physical 15, module_symbols 6, mut_abi 5,
  native_file_cleanup 4, native_ir 4, native_types 1, native_variant_policy 8, ownership
  18, python_values 3, scalar_lowering_policy 3.

**Run-only tests inside O files: 34 in 15 qbe files.**
- qbe_loop_facts 6, qbe_rc_index_update 5, qbe_loop_remainder_bias 4.
- 2 each: qbe_list_literal, qbe_literals, qbe_loop_bounded_write, qbe_positive_index,
  qbe_rc_append_version, qbe_rc_field_inout, qbe.
- 1 each: constant_divisor, loop_unswitch, rc_native_variant, rc_unique_capture, qbe_text.
- bytecode_inline has 4 run-only trap-frame tests.

Move each of these to `tests/lang` or an R file if its behaviour is not already covered
there. Otherwise delete it with its file.

## X (8 files, 84 tests)

arena_managed 26; cow 22 (`--gc-runtime` COW, mostly IL); cow_rebox_roots 1;
host_declarations 7; invoke 22; managed_cell 4; native_rc_arena 1; native_rc_host 1.

## M (12 files, 250 tests)

- array_places 13: R2 F3 O8.
- c_abi 5: O3 F2.
- compiler 36: R12 F17 O6 X1.
- effects 67: R15 F36 O1 X15. Of the X, 11 are "legacy sharing:" tests and 4 have
  `host def` fixtures, which can be rewritten as F.
- io_print 23: R13 F6 O3 X1.
- managed_frontend 5: R1 F2 X2.
- managed_lists 19: R11 F2 O3 X3.
- module_interface 10: F8 O2 (uncertain).
- mut_callback_abi 13: O7 R3 X3.
- python_core 19: R7 F9 O1 X2.
- python_format 11: R3 F5 O3.
- value_semantics 29: F15 O13 X1.

## Helpers to retarget alongside `native_execute.zig`

- **`stdlib_fixture.zig` (11 files).** It wraps `embedded_project.Program` and
  `native.runWithOptions`; its `stress()` sets `gc_stress`.
- **`io_files_test.zig` `Sandbox` (4 files).**
- **Direct `native.program` callers (2):** io_print's R_OUTPUT test and
  qbe_rc_index_update.
- **Project compilations handed to `native.run`:** `language.embedded_project` (18
  importers) and `project_compile.zig` (14).
- **`native_test_options` build module (6 files).**
- **`test_support.zig`'s `LegacySharing` (25 files):** goes with legacy sharing (S5-D4).

**`gc_stress`** is passed by 32 files. In surviving files it is incidental: drop or ignore
`Options.gc_stress`.

**`runUnaccounted` / `runWithPolicy`:** the only surviving user is contracts.

**Bytecode lowering inside surviving tests:** about 35 R/F files call
`Compilation.emit()`, `.dump()` or `.code` as an extra step. Examples: effects' `accept`
helper, and the allocation-failure scenarios in environment, resource_source and
interfaces. Those calls go away with `lower.zig`.

## Uncertain

- **invalidation:** O or F. It is the old `--explain-invalidation` report.
- **module_interface, module_symbols:** module interface digests.
- **native_types:** used only by old modules.
- **memory_budget_frames:** asserts the old runtime's stack-mapping constants.
- **scoped_providers, external_resources:** F, but possibly dead with the host apps.
- **cow:** X or O.
- **qbe_rc_field_inout:** O by subject, though 2 of its 3 tests are run-only.
- **declarations and c_abi:** they have `host def` fixtures.
