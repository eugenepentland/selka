### 10k ReleaseFast matrix (pinned binary)

| workload | state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: |
| ordinary-10k | cold | 20 | 117.3 | 125.1 | 62284 |
| ordinary-10k | unchanged | 20 | 13.1 | 14.1 | 32756 |
| ordinary-10k | no_cache | 20 | 62.6 | 67.9 | 52172 |
| ordinary-10k | implementation_edit | 20 | 76.1 | 88.3 | 53292 |
| ordinary-10k | constant_edit | 20 | 77.9 | 90.4 | 53292 |
| ordinary-10k | signature_edit | 20 | 72.5 | 83.4 | 52492 |
| ordinary-10k | union_edit | unsupported | – | – | – |
| ordinary-10k | provider_edit | unsupported | – | – | – |
| ordinary-10k | effect_edit | unsupported | – | – | – |
| ordinary-10k | session_implementation_edit | 20 | 37.1 | 37.6 | None |
| ordinary-10k | session_constant_edit | 20 | 37.5 | 37.9 | None |
| ordinary-10k | forced_tests | 5 | 330.1 | 356.3 | 80452 |
| ordinary-10k | forced cold_build | 1 | 1696.3 | – | 80452 |
| managed-10k | cold | 20 | 135.0 | 147.4 | 64524 |
| managed-10k | unchanged | 20 | 12.9 | 14.2 | 42516 |
| managed-10k | no_cache | 20 | 84.6 | 90.5 | 53804 |
| managed-10k | implementation_edit | 20 | 99.5 | 107.1 | 60204 |
| managed-10k | constant_edit | 20 | 100.6 | 123.5 | 62092 |
| managed-10k | signature_edit | unsupported | – | – | – |
| managed-10k | union_edit | 20 | 97.5 | 114.3 | 61132 |
| managed-10k | provider_edit | 20 | 98.9 | 109.9 | 62252 |
| managed-10k | effect_edit | 20 | 99.6 | 119.9 | 62604 |
| managed-10k | session_implementation_edit | 20 | 60.2 | 60.6 | None |
| managed-10k | session_constant_edit | 20 | 61.5 | 62.5 | None |
| managed-10k | forced_tests | 5 | 439.2 | 446.9 | 100096 |
| managed-10k | forced cold_build | 1 | 8270.3 | – | 100096 |

### Implementation-edit exclusive phase p50 (ms)

| workload | state | total inclusive | dependency_key_preparation | retention_store_io | source_load_parse | syntax_parse | syntax_replay | ordinary_body_replay | specialization_body_replay | fresh_body_check | source_merge | effect_origin_passes | warning_derivation | entry_adaptation | declarations_interfaces | symbolic_templates | domain_codec_validation |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinary-10k | implementation_edit | 72.6 | 10.1 | 28.7 | 11.0 | 0.5 | 4.8 | 3.4 | – | 0.5 | 3.3 | 2.5 | 0.0 | 0.1 | 0.3 | 0.0 | 0.0 |
| managed-10k | implementation_edit | 95.5 | 9.6 | 27.9 | 10.8 | 0.4 | 4.5 | 3.4 | 3.2 | 21.6 | 2.9 | 3.1 | 0.0 | 0.1 | 0.6 | 0.8 | 0.0 |

### 100k ReleaseFast matrix (pinned binary)

| workload | state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: |
| ordinary-100k | cold | 20 | 1246.7 | 1262.2 | 544724 |
| ordinary-100k | unchanged | 20 | 101.3 | 103.3 | 40108 |
| ordinary-100k | no_cache | 20 | 1031.2 | 1047.8 | 524216 |
| ordinary-100k | implementation_edit | 20 | 998.0 | 1016.5 | 442308 |
| ordinary-100k | constant_edit | 20 | 1004.0 | 1014.2 | 447788 |
| ordinary-100k | signature_edit | 20 | 1001.5 | 1020.5 | 442836 |
| ordinary-100k | union_edit | unsupported | – | – | – |
| ordinary-100k | provider_edit | unsupported | – | – | – |
| ordinary-100k | effect_edit | unsupported | – | – | – |
| ordinary-100k | session_implementation_edit | 20 | 1017.0 | 1041.2 | None |
| ordinary-100k | session_constant_edit | 20 | 1025.4 | 1044.1 | None |
| ordinary-100k | forced_tests | 5 | 2822.2 | 2846.0 | 684660 |
| ordinary-100k | forced cold_build | 1 | 15617.0 | – | 684660 |
| managed-100k | cold | 20 | 1314.4 | 1331.0 | 551844 |
| managed-100k | unchanged | 20 | 103.1 | 108.5 | 39628 |
| managed-100k | no_cache | 20 | 1074.7 | 1142.0 | 531672 |
| managed-100k | implementation_edit | 20 | 1088.5 | 1102.3 | 517840 |
| managed-100k | constant_edit | 20 | 1089.0 | 1093.8 | 522072 |
| managed-100k | signature_edit | unsupported | – | – | – |
| managed-100k | union_edit | 20 | 1072.9 | 1104.0 | 516804 |
| managed-100k | provider_edit | 20 | 1086.8 | 1094.2 | 517464 |
| managed-100k | effect_edit | 20 | 1087.2 | 1091.3 | 514324 |
| managed-100k | session_implementation_edit | 20 | 1075.4 | 1079.9 | None |
| managed-100k | session_constant_edit | 20 | 1079.7 | 1083.5 | None |
| managed-100k | forced_tests | 5 | 3035.3 | 3173.7 | 692176 |
| managed-100k | forced cold_build | 1 | 11345.7 | – | 692176 |

### Implementation-edit exclusive phase p50 (ms)

| workload | state | total inclusive | dependency_key_preparation | retention_store_io | source_load_parse | syntax_parse | syntax_replay | ordinary_body_replay | specialization_body_replay | fresh_body_check | source_merge | effect_origin_passes | warning_derivation | entry_adaptation | declarations_interfaces | symbolic_templates | domain_codec_validation |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinary-100k | implementation_edit | 994.3 | 518.6 | 75.9 | 94.7 | 3.1 | 52.7 | 14.3 | – | 113.6 | 34.9 | 27.6 | 0.4 | 3.9 | 3.2 | 0.2 | 0.0 |
| managed-100k | implementation_edit | 1083.8 | 495.8 | 98.7 | 92.6 | 3.0 | 51.3 | 15.2 | 18.5 | 170.4 | 33.3 | 31.4 | 0.4 | 3.5 | 3.3 | 12.7 | 0.0 |

### Implementation-edit exclusive phase p50 (ms)

| workload | state | total inclusive | dependency_key_preparation | retention_store_io | source_load_parse | syntax_parse | syntax_replay | ordinary_body_replay | specialization_body_replay | fresh_body_check | source_merge | effect_origin_passes | warning_derivation | entry_adaptation | declarations_interfaces | symbolic_templates | domain_codec_validation |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinary-100k | unchanged | 99.1 | – | – | 95.9 | – | – | – | – | – | – | – | – | – | – | – | – |
| managed-100k | unchanged | 100.3 | – | – | 97.3 | – | – | – | – | – | – | – | – | – | – | – | – |

### Direct native-test probe (`mylang test --report`; C4 selective lowering)

| workload | state | n | p50 ms | p95 ms | lowered | emitted | links | executed | cached | select-file |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| ordinary-10k | first_build_cold_cache | 3 | 1701.3 | 1734.1 | 50/0 | 50/0 | 1/0 | 1/0 | 0 | 1 |
| ordinary-10k | warm_unchanged_cached | 5 | 49.5 | 114.5 | 0/0 | 0/0 | 0/0 | 0/1 | 1 | 0 |
| ordinary-10k | forced_run | 5 | 327.4 | 346.0 | 50/0 | 50/0 | 1/0 | 1/0 | 0 | 1 |
| ordinary-10k | used_helper_edit | 5 | 350.3 | 357.3 | 50/0 | 50/0 | 1/0 | 1/0 | 0 | 1 |
| ordinary-10k | unused_helper_edit | 5 | 138.9 | 148.7 | 0/0 | 0/0 | 0/0 | 0/1 | 1 | 0 |
| ordinary-10k | no_cache_control | 1 | 303.5 | 303.5 | 50/0 | 50/0 | 1/0 | 1/0 | 0 | – |
| ordinary-100k | first_build_cold_cache | 3 | 15906.6 | 15907.4 | 524/0 | 524/0 | 1/0 | 1/0 | 0 | 1 |
| ordinary-100k | warm_unchanged_cached | 5 | 423.6 | 1316.4 | 0/0 | 0/0 | 0/0 | 0/1 | 1 | 0 |
| ordinary-100k | forced_run | 5 | 2731.7 | 2752.4 | 524/0 | 524/0 | 1/0 | 1/0 | 0 | 1 |
| ordinary-100k | used_helper_edit | 5 | 2785.6 | 2848.0 | 524/0 | 524/0 | 1/0 | 1/0 | 0 | 1 |
| ordinary-100k | unused_helper_edit | 5 | 1533.2 | 1576.2 | 0/0 | 0/0 | 0/0 | 0/1 | 1 | 0 |
| ordinary-100k | no_cache_control | 1 | 2781.7 | 2781.7 | 524/0 | 524/0 | 1/0 | 1/0 | 0 | – |
| managed-10k | first_build_cold_cache | 3 | 8457.0 | 8518.7 | 322/0 | 322/0 | 1/0 | 1/0 | 0 | 1 |
| managed-10k | warm_unchanged_cached | 5 | 53.6 | 130.2 | 0/0 | 0/0 | 0/0 | 0/1 | 1 | 0 |
| managed-10k | forced_run | 5 | 413.6 | 426.2 | 322/0 | 322/0 | 1/0 | 1/0 | 0 | 1 |
| managed-10k | used_helper_edit | 5 | 2125.7 | 2271.4 | 322/0 | 322/0 | 1/0 | 1/0 | 0 | 1 |
| managed-10k | unused_helper_edit | 5 | 152.8 | 155.9 | 0/0 | 0/0 | 0/0 | 0/1 | 1 | 0 |
| managed-10k | provider_edit | 5 | 605.2 | 733.4 | 317/0 | 317/0 | 1/0 | 1/0 | 0 | 1 |
| managed-10k | no_cache_control | 1 | 382.3 | 382.3 | 322/0 | 322/0 | 1/0 | 1/0 | 0 | – |
| managed-100k | first_build_cold_cache | 3 | 11502.9 | 11756.8 | 322/0 | 322/0 | 1/0 | 1/0 | 0 | 1 |
| managed-100k | warm_unchanged_cached | 5 | 479.9 | 1603.2 | 0/0 | 0/0 | 0/0 | 0/1 | 1 | 0 |
| managed-100k | forced_run | 5 | 3136.8 | 3396.1 | 322/0 | 322/0 | 1/0 | 1/0 | 0 | 1 |
| managed-100k | used_helper_edit | 5 | 4925.4 | 5554.5 | 322/0 | 322/0 | 1/0 | 1/0 | 0 | 1 |
| managed-100k | unused_helper_edit | 5 | 2036.5 | 2254.4 | 0/0 | 0/0 | 0/0 | 0/1 | 1 | 0 |
| managed-100k | provider_edit | 5 | 3450.6 | 4070.3 | 317/0 | 317/0 | 1/0 | 1/0 | 0 | 1 |
| managed-100k | no_cache_control | 1 | 3244.6 | 3244.6 | 322/0 | 322/0 | 1/0 | 1/0 | 0 | – |

### 100k ordinary semantic-budget phase check (implementation_edit)

| budget MiB | edit checked/reused | dep-key prep p50 ms | retention/store p50 ms | fresh body check p50 ms | total p50 ms |
| ---: | --- | ---: | ---: | ---: | ---: |
| 0 | 33475/0 | 586.3 | 0.0 | 178.4 | 1078.0 |
| 16 | 24655/8820 | 600.4 | 90.4 | 132.0 | 1140.4 |
| 64 | 2/33473 | 560.1 | 322.3 | 1.1 | 1255.4 |

