//! Unit test entry point, separate from the production compiler module.
/// The compiler's language module, for command files this root compiles that
/// reach the front end through `compiler_root`.
pub const compiler_language = @import("compiler.zig");
test {
    _ = @import("frontend_migration_test.zig");
    _ = @import("iteration_place_test.zig");
    _ = @import("input_probe_test.zig");
    _ = @import("compiler.zig").module_syntax;
    _ = @import("view_cycles_test.zig");

    _ = @import("doc_coverage.zig");
    _ = @import("tokens_dump_test.zig");
    _ = @import("doc_coverage_command.zig");
    _ = @import("doctest_command.zig");
    _ = @import("docs_command.zig");
    _ = @import("packages_command.zig");
    _ = @import("reference_test.zig");
    _ = @import("context_test.zig");

    _ = @import("native_execute.zig");
    _ = @import("wiring/process_start.zig");
    _ = @import("exit_status_test.zig");
    _ = @import("error_trace_test.zig");
    _ = @import("wiring/core_runner.zig");
    _ = @import("zig_local_cache_test.zig");
    _ = @import("value_semantics_test.zig");
    // The manifest's own tables were described here but never reached this root,
    // so the QBE-TEXT/QBE-LIST checks that pin them existed without running.

    _ = @import("prelude_builtins_test.zig");
    _ = @import("python_core_test.zig");
    _ = @import("python_calls_test.zig");
    _ = @import("python_syntax_test.zig");
    _ = @import("python_variants_test.zig");
    _ = @import("python_generics_test.zig");
    _ = @import("python_arrays_test.zig");
    _ = @import("python_assert_test.zig");
    _ = @import("contracts_test.zig");
    _ = @import("python_strings_test.zig");
    _ = @import("python_text_surface_test.zig");
    _ = @import("python_format_test.zig");
    _ = @import("python_comprehension_test.zig");
    _ = @import("collections_fidelity_test.zig");
    _ = @import("python_expressions_test.zig");
    _ = @import("format_spec_test.zig");
    _ = @import("python_surface_test.zig");
    _ = @import("unit_test.zig");
    _ = @import("declarations_test.zig");
    _ = @import("stdlib_time_random_test.zig");
    _ = @import("stdlib_math_test.zig");
    _ = @import("stdlib_strings_test.zig");
    _ = @import("stdlib_sort_test.zig");
    _ = @import("stdlib_path_test.zig");
    _ = @import("stdlib_codecs_test.zig");
    _ = @import("stdlib_json_test.zig");
    _ = @import("stdlib_pool_test.zig");
    _ = @import("const_lengths_test.zig");
    _ = @import("callbacks_test.zig");
    _ = @import("typed_holes_test.zig");
    _ = @import("allocation_budget_test.zig");
    _ = @import("float_operations_test.zig");
    _ = @import("integer_operations_test.zig");
    _ = @import("io_print_test.zig");
    _ = @import("io_files_test.zig");
    _ = @import("byte_literal_test.zig");
    _ = @import("nominal_provider_contracts_test.zig");
    _ = @import("generic_codecs_test.zig");
    _ = @import("nominal_providers_test.zig");
    _ = @import("nominal_instances_test.zig");
    _ = @import("nominal_bodies_test.zig");
    _ = @import("nominal_layouts_test.zig");
    _ = @import("chunked_arena.zig");
    _ = @import("nominal_templates_test.zig");
    _ = @import("nominal_type_syntax_test.zig");
    _ = @import("generic_arrays_test.zig");
    _ = @import("domain_equality_test.zig");
    _ = @import("diagnostic_output_test.zig");
    _ = @import("diagnostic_fix_test.zig");
    _ = @import("fix_plan_test.zig");
    _ = @import("diagnostic_recovery_test.zig");
    _ = @import("generic_inference_test.zig");
    _ = @import("flow_inference_test.zig");
    _ = @import("generic_execution_test.zig");
    _ = @import("generic_instances_test.zig");
    _ = @import("generic_calls_test.zig");
    _ = @import("generic_bodies_test.zig");
    _ = @import("generic_concrete_test.zig");
    _ = @import("generic_results_test.zig");
    _ = @import("generic_providers_test.zig");
    _ = @import("generic_requirements_test.zig");
    _ = @import("generic_syntax_test.zig");
    _ = @import("syntax_cache_test.zig");
    _ = @import("declaration_hints_test.zig");
    _ = @import("headerless_import_test.zig");
    _ = @import("frontend_cache_test.zig");
    _ = @import("check_cache_test.zig");
    _ = @import("semantic_cache_test.zig");
    _ = @import("check_scale_test.zig");
    _ = @import("module_interface_test.zig");
    _ = @import("semantic_key.zig");
    _ = @import("sema_builtins.zig");
    _ = @import("sema_places.zig");
    _ = @import("sema_collections.zig");
    _ = @import("sema_calls.zig");
    _ = @import("sema_operators.zig");
    _ = @import("sema_expressions.zig");
    _ = @import("sema_loops.zig");
    _ = @import("sema_statements.zig");
    _ = @import("sema_specialize.zig");
    _ = @import("invalidation_matrix_test.zig");
    _ = @import("semantic_project_test.zig");
    _ = @import("import_policy_test.zig");
    _ = @import("lint_config_test.zig");
    _ = @import("lint_test.zig");
    _ = @import("lint_sentinel_test.zig");
    _ = @import("lint_reach_test.zig");
    _ = @import("lint_store_test.zig");
    _ = @import("source_map_test.zig");
    _ = @import("project_test.zig");
    _ = @import("interfaces_test.zig");
    _ = @import("interface_files_test.zig");
    _ = @import("compiler_test.zig");
    _ = @import("duplicates_test.zig");
    _ = @import("near_duplicates_test.zig");
    _ = @import("quality_test.zig");
    _ = @import("affected_tests_test.zig");
    _ = @import("affected_tests.zig");
    _ = @import("navigation_test.zig");
    _ = @import("navigation_scale_test.zig");
    _ = @import("context_test.zig");
    _ = @import("ref_diff.zig");
    _ = @import("api_diff.zig");
    _ = @import("generic_api_test.zig");
    _ = @import("syntax_cache_large_test.zig");
    _ = @import("structural_constraints_test.zig");
    _ = @import("named_constraints_namespace_test.zig");
    _ = @import("formatter_test.zig");
    _ = @import("records_test.zig");
    _ = @import("integers_test.zig");
    _ = @import("number_literal_test.zig");
    _ = @import("arrays_test.zig");
    _ = @import("array_places_test.zig");
    _ = @import("domains_test.zig");
    _ = @import("variants_test.zig");
    _ = @import("tables_test.zig");
    _ = @import("effects_test.zig");
    _ = @import("mutation.zig");
    _ = @import("input_manifest_test.zig");
    _ = @import("external_capabilities_test.zig");
    _ = @import("external_resources_test.zig");
    _ = @import("resource_source_test.zig");
    _ = @import("environment_test.zig");
    _ = @import("resource_io_test.zig");
    _ = @import("results_test.zig");
    _ = @import("propagation_test.zig");
    _ = @import("option_methods_test.zig");
    _ = @import("domain_codecs_test.zig");
    _ = @import("runtime_values_test.zig");
    _ = @import("managed_values_test.zig");
    _ = @import("python_bytes_test.zig");
    _ = @import("managed_lists_test.zig");
    _ = @import("python_collections_test.zig");
    _ = @import("managed_frontend_test.zig");
    _ = @import("sema_mut_arguments_test.zig");
    _ = @import("mut_exclusive_test.zig");
    _ = @import("recursive_resources_test.zig");
    _ = @import("surface_collections_test.zig");
    _ = @import("builtin_context_test.zig");
    _ = @import("standard_library_test.zig");
    _ = @import("stand_ins_test.zig");
    _ = @import("byte_builder_test.zig");
    _ = @import("loop_exit_test.zig");
    _ = @import("constants_test.zig");
    _ = @import("embed_test.zig");
    _ = @import("typing_papercuts_test.zig");
    _ = @import("incremental_test.zig");
    _ = @import("timings_test.zig");
    _ = @import("invalidation_test.zig");
    _ = @import("for_range_test.zig");
    _ = @import("type_aliases_test.zig");
    _ = @import("tuples_test.zig");
}
test {
    _ = @import("surface_statements_test.zig");
}
test {
    _ = @import("dotted_modules_test.zig");
}

test {
    _ = @import("number_text.zig");
    _ = @import("number_text_test.zig");
}

test {
    _ = @import("memory_budget");
    _ = @import("memory_budget_frames_test.zig");
}

test {
    _ = @import("c_abi_test.zig");
    _ = @import("friction_log_test.zig");
}

test {
    _ = @import("prelude_scalar_test.zig");
    _ = @import("dictionary_views_test.zig");
    _ = @import("sets_test.zig");
    _ = @import("retired_features_test.zig");
}
