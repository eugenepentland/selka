Forty actual final-source hotspot captures cover ten families, both frozen sizes
and both MyLang backends at exact source
`730a86e62b47c922dc1411d24b5868c3bd2132f3`. They use the receipted final RF
compiler/guests after full acceptance and independent confirmation timing.
Cases: sort_int, sort_records, alloc_retained, mutate_nested, float_math,
call_direct, result_propagate, bytes_scan, json_transform and lox_eval.

All40 completed with exact checksums. Sampling requested user CPU-clock at99Hz,
4seconds, at least200 samples, maximum10million iterations; six hardware counters
were captured separately. Every invocation used CPU2/global timing lock.
Profiles include launcher, fixtures, formatting, teardown and runtime threads;
they are diagnostics, not acceptance timings or kernel-only costs.

Samples range3–369; seven profiles are below200, eight hit iteration caps,
36 miss the requested instrumented duration. All40 have raw throttle records
and zero recorded lost events. Throttle records require caution about the
retained distribution and alone do not establish achieved sampling frequency.
The quality flag is false for every capture. In particular, byte-scan sample
sets are too small for strong hotspot proportions; no repeat timed runs were
added to tune an already successful result. Raw samples, perf data, record dump,
stdout/stderr, counter TSV and complete commands/calibration/quality remain.

Hybrid counters retain cpu_core and cpu_atom rows, including inactive/multiplexed
values. CPU2 is explicitly in cpu_core's sysfs membership. All40 selections have
available counters, with PMU provenance retained. Selected counters include
setup/teardown and do not identify an additive kernel cost. The archive integrity
check verifies160raw hashes, sample-count totals, all40 guest bindings, matching
before/after artifacts and the explicit CPU2 PMU selections; it is not an
independent execution rerun or causal proof.

| Case / size | Backend | Samples | Low / iteration cap / duration miss | Raw throttle records | Leading symbols (sample counts) |
|---|---|---:|---|---:|---|
| sort_int / small | my-llvm | 248 | False / True / True | 248 | myl_native_list_sort (111); main::batch_result (62); main::fold (41) |
| sort_int / small | my-qbe | 360 | False / False / True | 360 | myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934 (159); sort_i64 (86); myl_f_a799210014eaeeec9e6c8f7014ab7e095e787135c5dd999b28e3c172c2e7fc75 (74) |
| sort_int / large | my-llvm | 361 | False / False / True | 361 | myl_native_list_sort (289); main::fold (32); main::batch_result (31) |
| sort_int / large | my-qbe | 361 | False / False / True | 361 | sort_i64 (246); myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934 (76); myl_f_a799210014eaeeec9e6c8f7014ab7e095e787135c5dd999b28e3c172c2e7fc75 (30) |
| sort_records / small | my-llvm | 363 | False / False / True | 363 | main::batch_result (199); keyed_sort_words (106); drain_fast (10) |
| sort_records / small | my-qbe | 355 | False / False / True | 355 | myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934 (220); keyed_sort_words (82); myl_rc_list_plain_ready (8) |
| sort_records / large | my-llvm | 362 | False / False / True | 362 | main::batch_result (241); keyed_sort_words (107); myl_rc_list_plain_ready (10) |
| sort_records / large | my-qbe | 361 | False / False / True | 361 | myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934 (244); keyed_sort_words (98); myl_rc_list_plain_ready (10) |
| alloc_retained / small | my-llvm | 356 | False / False / True | 356 | main::batch_result (105); drain_fast (63); myl_rc_storage_alloc (50) |
| alloc_retained / small | my-qbe | 342 | False / False / True | 342 | myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934 (167); drain_fast (29); drain_one (29) |
| alloc_retained / large | my-llvm | 348 | False / False / True | 348 | main::batch_result (122); drain_fast (38); drain_one (36) |
| alloc_retained / large | my-qbe | 349 | False / False / True | 349 | myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934 (163); myl_rc_storage_alloc (31); drain_fast (25) |
| mutate_nested / small | my-llvm | 357 | False / False / True | 357 | finish_clones (70); transfer_pointer (62); myl_rc_registered_edges_release (28) |
| mutate_nested / small | my-qbe | 356 | False / False / True | 356 | finish_clones (70); transfer_pointer (54); myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934 (47) |
| mutate_nested / large | my-llvm | 358 | False / False / True | 358 | transfer_pointer (136); finish_clones (81); myl_rc_registered_edges_release (56) |
| mutate_nested / large | my-qbe | 351 | False / False / True | 351 | transfer_pointer (132); finish_clones (77); myl_rc_registered_edges_release (51) |
| float_math / small | my-llvm | 163 | True / True / True | 163 | myl_qbe_float_unary (103); main::main (60) |
| float_math / small | my-qbe | 291 | False / False / True | 291 | myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5 (171); myl_qbe_float_unary (120) |
| float_math / large | my-llvm | 268 | False / False / True | 268 | myl_qbe_float_unary (176); main::main (92) |
| float_math / large | my-qbe | 276 | False / False / True | 276 | myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5 (155); myl_qbe_float_unary (121) |
| call_direct / small | my-llvm | 69 | True / True / True | 69 | main::main (69) |
| call_direct / small | my-qbe | 299 | False / False / True | 299 | myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5 (299) |
| call_direct / large | my-llvm | 296 | False / False / True | 296 | main::main (296) |
| call_direct / large | my-qbe | 293 | False / False / True | 293 | myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5 (293) |
| result_propagate / small | my-llvm | 131 | True / True / True | 131 | main::main (115); myl_qbe_error_trace_append_preserve_most (14); myl_qbe_error_trace_origin_preserve_most (2) |
| result_propagate / small | my-qbe | 315 | False / False / True | 315 | myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5 (314); myl_qbe_error_trace_append (1) |
| result_propagate / large | my-llvm | 329 | False / False / True | 329 | main::main (294); myl_qbe_error_trace_append_preserve_most (28); myl_qbe_error_trace_origin_preserve_most (7) |
| result_propagate / large | my-qbe | 302 | False / False / True | 302 | myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5 (299); myl_qbe_error_trace_append (1); myl_qbe_error_trace_origin (1) |
| bytes_scan / small | my-llvm | 3 | True / True / True | 3 | main::kernel (3) |
| bytes_scan / small | my-qbe | 7 | True / True / True | 7 | myl_f_1af80ea2572d9d5f91426ffa7805826aa9a97e2ce757b902d5901fdbfc722f76 (3); myl_f_c930f7926c5a0ca4f5adc54ef7771ccff3aa703c6372e5d6728443a887ee04de (3); myl_native_bytes_sum_xor (1) |
| bytes_scan / large | my-llvm | 68 | True / True / True | 68 | main::kernel (68) |
| bytes_scan / large | my-qbe | 73 | True / True / True | 73 | myl_native_bytes_sum_xor (59); myl_f_1af80ea2572d9d5f91426ffa7805826aa9a97e2ce757b902d5901fdbfc722f76 (12); myl_qbe_heap (1) |
| json_transform / small | my-llvm | 364 | False / False / False | 364 | json::skip_whitespace (38); json::read_object (33); myl_rc_storage_alloc (22) |
| json_transform / small | my-qbe | 364 | False / False / False | 364 | myl_t_0068ff077450168eaf8a2718c52ebcc340ad02ffd61008e2de16e1ce57b74424_rcg_retain (62); myl_f_e291b4a30cc9aef54000a3269f4c113c67d1fbb6730c339f002c61c293faf8c4 (44); myl_f_09dbfb6aaad220aec5de7813a6d84f1656e3a8fab353027a4ceb1c42292cfbdf (22) |
| json_transform / large | my-llvm | 369 | False / False / False | 369 | json::skip_whitespace (43); json::read_object (32); json::read_number (28) |
| json_transform / large | my-qbe | 365 | False / False / False | 365 | myl_t_0068ff077450168eaf8a2718c52ebcc340ad02ffd61008e2de16e1ce57b74424_rcg_retain (56); myl_f_e291b4a30cc9aef54000a3269f4c113c67d1fbb6730c339f002c61c293faf8c4 (30); myl_f_09dbfb6aaad220aec5de7813a6d84f1656e3a8fab353027a4ceb1c42292cfbdf (18) |
| lox_eval / small | my-llvm | 363 | False / False / True | 363 | main::execute (345); drain_fast (4); main::batch_result (3) |
| lox_eval / small | my-qbe | 358 | False / False / True | 358 | myl_f_b615c0e27725def7799e34b024659a47188453e932f9def9389806d20cb9d6b7 (295); myl_rc_list_plain_pop_ready (34); myl_f_4c388c09641a7cf53a57c584f19db2c37bf5f9318d201409d2cca2d83d777934 (5) |
| lox_eval / large | my-llvm | 362 | False / False / True | 362 | main::execute (361); myl_rc_list_plain_ready (1) |
| lox_eval / large | my-qbe | 357 | False / False / True | 357 | myl_f_b615c0e27725def7799e34b024659a47188453e932f9def9389806d20cb9d6b7 (328); myl_rc_list_plain_pop_ready (26); myl_rc_list_plain_ready (2) |

The large residual collection captures locate named work without changing
thresholds: sort_int has native sort in roughly80%LLVM/68%QBE of retained samples;
sort_records has batch construction plus keyed_sort_words, retained allocation
has batch_result and allocation/drain work, nested mutation has transfer_pointer,
finish_clones and registered-edge release in roughly77%LLVM/75%QBE. These are
whole-process retained-sample observations with throttle records, not causal
cost fractions or common-code CPU coverage. Application/generated bodies stay
unclassified when the rule/manifest cannot attribute their inline work.

Large LLVM float shows176/268 retained samples in myl_qbe_float_unary; QBE
121/276. The source-bound helper dispatch covers conversions and arithmetic,
so the name alone does not isolate which operation caused the confirmed5–6%
LLVM regression. QBE call/Result samples concentrate in the generated compute
entry; inlining erases distinct primitive symbols. Existing-IP annotations of
final call/Result QBE entry and LLVM float helper are included for review, with
binary/raw-sample hashes. They introduce no new measurement or causal claim.

JSON samples include parsing functions and ownership work; Lox concentrates in
execute, with QBE plain-pop readiness also visible. The independently paired
application gains and the separate counting-mode JSON event reductions are
consistent evidence of improved behavior, but these profiles do not apportion
those gains by mechanism. Counting instrumentation can disable ordinary
optimizations and does not validate P7 ordinary-path admission.

Versioned primitive rules and classifier hashes are recorded by the profile
report. Exact final native sort/transfer/walk/alloc, float, byte and JSON source
hashes are supplied as named-source bindings. Earlier main profiles and d348
component diagnostics remain separate immutable artifacts; their different
workloads and sampling conditions are not paired timings. No sort-threshold,
CPU-coverage, broad distribution, common-ISA or compile-time claim follows from
these captures. The safe P2 capability admits no compute fixture specialization;
alloc_short and most parity targets remain open.

Profile JSON SHA256: `9564257c84960b0dca1f3ce6135c470fa2f4b8f4a4cc9492df15df8bd1cd1607`.
