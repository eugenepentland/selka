### managed-100k semantic budget 0 MiB

| state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| cold | 20 | 1579.4 | 2446.4 | 534156 |
| unchanged | 20 | 134.3 | 143.8 | 40400 |
| no_cache | 20 | 1433.3 | 1545.9 | 531948 |
| implementation_edit | 20 | 1290.9 | 1423.7 | 419136 |
| session_implementation_edit | 20 | 1389.3 | 1424.8 | None |

Implementation-edit exclusive phase p50 (ms):

| phase | p50 ms |
| --- | ---: |
| dependency_key_preparation | 638.9 |
| fresh_body_check | 280.0 |
| source_load_parse | 115.9 |
| syntax_replay | 67.2 |
| source_merge | 43.7 |
| effect_origin_passes | 39.8 |
| syntax_parse | 3.8 |
| ordinary_body_replay | 0.8 |
| warning_derivation | 0.6 |
| retention_store_io | 0.0 |

Last session-probe reply:

- specialization_bodies: `{'checked': 256, 'reused': 0, 'stored': 0}`
- symbolic_templates: `{'checked': 4, 'reused': 0, 'stored': 0}`
- semantic_retention: `{'retained_bytes': 0, 'ordinary_bytes': 0, 'symbolic_bytes': 0, 'specialization_bytes': 0, 'evicted': 0}`
- miss reasons: `{'ordinary': [], 'symbolic': [{'reason': 'symbolic-cache-disabled', 'count': 4}], 'specializations': [{'reason': 'specialization-cache-disabled', 'count': 256}]}`

### managed-100k semantic budget 128 MiB

| state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| cold | 20 | 2189.6 | 3878.8 | 598796 |
| unchanged | 20 | 138.4 | 157.4 | 40460 |
| no_cache | 20 | 1484.6 | 1925.0 | 532076 |
| implementation_edit | 20 | 1650.7 | 1938.1 | 586076 |
| session_implementation_edit | 20 | 1511.7 | 1729.4 | None |

Implementation-edit exclusive phase p50 (ms):

| phase | p50 ms |
| --- | ---: |
| dependency_key_preparation | 676.9 |
| retention_store_io | 406.9 |
| source_load_parse | 123.9 |
| fresh_body_check | 85.0 |
| syntax_replay | 70.7 |
| ordinary_body_replay | 54.2 |
| source_merge | 46.0 |
| effect_origin_passes | 41.3 |
| syntax_parse | 3.8 |
| warning_derivation | 0.5 |

Last session-probe reply:

- specialization_bodies: `{'checked': 192, 'reused': 64, 'stored': 192}`
- symbolic_templates: `{'checked': 2, 'reused': 2, 'stored': 2}`
- semantic_retention: `{'retained_bytes': 59804934, 'ordinary_bytes': 59408970, 'symbolic_bytes': 2116, 'specialization_bytes': 393848, 'evicted': 0}`
- miss reasons: `{'ordinary': [{'reason': 'not-ordinary-body', 'count': 128}, {'reason': 'no-retained-body', 'count': 1}, {'reason': 'declaration-region-length-changed', 'count': 1}, {'reason': 'relocation-failed', 'count': 64}, {'reason': 'generic-specialization', 'count': 2}], 'symbolic': [{'reason': 'symbolic-no-retained-template', 'count': 2}], 'specializations': [{'reason': 'specialization-no-retained-body', 'count': 128}, {'reason': 'specialization-missing-instance-identity', 'count': 64}]}`

### managed-100k semantic budget 16 MiB

| state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| cold | 20 | 1708.1 | 3057.7 | 552716 |
| unchanged | 20 | 131.9 | 142.1 | 40400 |
| no_cache | 20 | 1498.3 | 1609.6 | 532020 |
| implementation_edit | 20 | 1446.7 | 1501.8 | 518312 |
| session_implementation_edit | 20 | 1315.6 | 1402.5 | None |

Implementation-edit exclusive phase p50 (ms):

| phase | p50 ms |
| --- | ---: |
| dependency_key_preparation | 661.8 |
| fresh_body_check | 226.4 |
| retention_store_io | 131.1 |
| source_load_parse | 120.8 |
| syntax_replay | 69.2 |
| source_merge | 44.9 |
| effect_origin_passes | 41.1 |
| ordinary_body_replay | 17.7 |
| syntax_parse | 3.9 |
| warning_derivation | 0.5 |

Last session-probe reply:

- specialization_bodies: `{'checked': 192, 'reused': 64, 'stored': 192}`
- symbolic_templates: `{'checked': 2, 'reused': 2, 'stored': 2}`
- semantic_retention: `{'retained_bytes': 16775706, 'ordinary_bytes': 16379742, 'symbolic_bytes': 2116, 'specialization_bytes': 393848, 'evicted': 0}`
- miss reasons: `{'ordinary': [{'reason': 'not-ordinary-body', 'count': 128}, {'reason': 'no-retained-body', 'count': 23576}, {'reason': 'declaration-region-length-changed', 'count': 1}, {'reason': 'relocation-failed', 'count': 18}, {'reason': 'generic-specialization', 'count': 2}], 'symbolic': [{'reason': 'symbolic-no-retained-template', 'count': 2}], 'specializations': [{'reason': 'specialization-no-retained-body', 'count': 128}, {'reason': 'specialization-missing-instance-identity', 'count': 64}]}`

### managed-100k semantic budget 32 MiB

| state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| cold | 20 | 1855.2 | 3141.4 | 571068 |
| unchanged | 20 | 125.3 | 133.9 | 40460 |
| no_cache | 20 | 1482.8 | 2027.8 | 532080 |
| implementation_edit | 20 | 1743.7 | 2151.4 | 548932 |
| session_implementation_edit | 20 | 2082.7 | 2140.5 | None |

Implementation-edit exclusive phase p50 (ms):

| phase | p50 ms |
| --- | ---: |
| dependency_key_preparation | 746.5 |
| retention_store_io | 304.6 |
| fresh_body_check | 200.8 |
| source_load_parse | 134.2 |
| syntax_replay | 77.4 |
| source_merge | 49.6 |
| effect_origin_passes | 45.7 |
| ordinary_body_replay | 31.2 |
| syntax_parse | 4.2 |
| warning_derivation | 0.6 |

Last session-probe reply:

- specialization_bodies: `{'checked': 192, 'reused': 64, 'stored': 192}`
- symbolic_templates: `{'checked': 2, 'reused': 2, 'stored': 2}`
- semantic_retention: `{'retained_bytes': 33554402, 'ordinary_bytes': 33158438, 'symbolic_bytes': 2116, 'specialization_bytes': 393848, 'evicted': 0}`
- miss reasons: `{'ordinary': [{'reason': 'not-ordinary-body', 'count': 128}, {'reason': 'no-retained-body', 'count': 14344}, {'reason': 'declaration-region-length-changed', 'count': 1}, {'reason': 'relocation-failed', 'count': 36}, {'reason': 'generic-specialization', 'count': 2}], 'symbolic': [{'reason': 'symbolic-no-retained-template', 'count': 2}], 'specializations': [{'reason': 'specialization-no-retained-body', 'count': 128}, {'reason': 'specialization-missing-instance-identity', 'count': 64}]}`

### managed-100k semantic budget 64 MiB

| state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| cold | 20 | 2194.7 | 2382.3 | 598920 |
| unchanged | 20 | 122.9 | 131.3 | 40044 |
| no_cache | 20 | 1356.8 | 1417.7 | 532088 |
| implementation_edit | 20 | 1535.0 | 1640.3 | 605932 |
| session_implementation_edit | 20 | 1232.5 | 1284.5 | None |

Implementation-edit exclusive phase p50 (ms):

| phase | p50 ms |
| --- | ---: |
| dependency_key_preparation | 608.2 |
| retention_store_io | 387.6 |
| source_load_parse | 111.8 |
| fresh_body_check | 80.0 |
| syntax_replay | 65.5 |
| ordinary_body_replay | 52.2 |
| source_merge | 41.6 |
| effect_origin_passes | 39.0 |
| syntax_parse | 3.7 |
| warning_derivation | 0.5 |

Last session-probe reply:

- specialization_bodies: `{'checked': 192, 'reused': 64, 'stored': 192}`
- symbolic_templates: `{'checked': 2, 'reused': 2, 'stored': 2}`
- semantic_retention: `{'retained_bytes': 59804934, 'ordinary_bytes': 59408970, 'symbolic_bytes': 2116, 'specialization_bytes': 393848, 'evicted': 0}`
- miss reasons: `{'ordinary': [{'reason': 'not-ordinary-body', 'count': 128}, {'reason': 'no-retained-body', 'count': 1}, {'reason': 'declaration-region-length-changed', 'count': 1}, {'reason': 'relocation-failed', 'count': 64}, {'reason': 'generic-specialization', 'count': 2}], 'symbolic': [{'reason': 'symbolic-no-retained-template', 'count': 2}], 'specializations': [{'reason': 'specialization-no-retained-body', 'count': 128}, {'reason': 'specialization-missing-instance-identity', 'count': 64}]}`

### ordinary-100k semantic budget 0 MiB

| state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| cold | 20 | 1483.1 | 2399.8 | 526692 |
| unchanged | 20 | 134.2 | 209.7 | 40720 |
| no_cache | 20 | 1424.6 | 1798.6 | 524500 |
| implementation_edit | 20 | 1406.3 | 2237.8 | 410920 |
| session_implementation_edit | 20 | 1462.3 | 1742.4 | None |

Implementation-edit exclusive phase p50 (ms):

| phase | p50 ms |
| --- | ---: |
| dependency_key_preparation | 762.0 |
| fresh_body_check | 206.6 |
| source_load_parse | 141.3 |
| syntax_replay | 123.9 |
| source_merge | 47.2 |
| effect_origin_passes | 39.1 |
| syntax_parse | 8.8 |
| ordinary_body_replay | 0.8 |
| warning_derivation | 0.6 |
| retention_store_io | 0.0 |

Last session-probe reply:

- specialization_bodies: `{'checked': 0, 'reused': 0, 'stored': 0}`
- symbolic_templates: `{'checked': 0, 'reused': 0, 'stored': 0}`
- semantic_retention: `{'retained_bytes': 0, 'ordinary_bytes': 0, 'symbolic_bytes': 0, 'specialization_bytes': 0, 'evicted': 0}`
- miss reasons: `{'ordinary': [], 'symbolic': [], 'specializations': []}`

### ordinary-100k semantic budget 128 MiB

| state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| cold | 20 | 2432.2 | 5402.2 | 592064 |
| unchanged | 20 | 156.5 | 186.2 | 40720 |
| no_cache | 20 | 1501.3 | 1913.3 | 524496 |
| implementation_edit | 20 | 1807.9 | 3252.8 | 534328 |
| session_implementation_edit | 20 | 1806.0 | 1986.8 | None |

Implementation-edit exclusive phase p50 (ms):

| phase | p50 ms |
| --- | ---: |
| dependency_key_preparation | 825.8 |
| retention_store_io | 443.2 |
| source_load_parse | 138.9 |
| syntax_replay | 85.8 |
| ordinary_body_replay | 66.9 |
| source_merge | 56.1 |
| effect_origin_passes | 42.1 |
| syntax_parse | 4.6 |
| fresh_body_check | 1.5 |
| warning_derivation | 0.7 |

Last session-probe reply:

- specialization_bodies: `{'checked': 0, 'reused': 0, 'stored': 0}`
- symbolic_templates: `{'checked': 0, 'reused': 0, 'stored': 0}`
- semantic_retention: `{'retained_bytes': 60639212, 'ordinary_bytes': 60639212, 'symbolic_bytes': 0, 'specialization_bytes': 0, 'evicted': 0}`
- miss reasons: `{'ordinary': [{'reason': 'declaration-region-length-changed', 'count': 1}, {'reason': 'relocation-failed', 'count': 1}], 'symbolic': [], 'specializations': []}`

### ordinary-100k semantic budget 16 MiB

| state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| cold | 20 | 1769.7 | 3313.9 | 544924 |
| unchanged | 20 | 137.5 | 148.7 | 40720 |
| no_cache | 20 | 1436.2 | 1459.3 | 524492 |
| implementation_edit | 20 | 1550.8 | 2278.2 | 446680 |
| session_implementation_edit | 20 | 1373.5 | 1512.2 | None |

Implementation-edit exclusive phase p50 (ms):

| phase | p50 ms |
| --- | ---: |
| dependency_key_preparation | 760.0 |
| syntax_replay | 172.2 |
| fresh_body_check | 156.0 |
| source_load_parse | 144.3 |
| retention_store_io | 106.6 |
| source_merge | 47.7 |
| effect_origin_passes | 38.7 |
| ordinary_body_replay | 18.0 |
| syntax_parse | 14.8 |
| warning_derivation | 0.6 |

Last session-probe reply:

- specialization_bodies: `{'checked': 0, 'reused': 0, 'stored': 0}`
- symbolic_templates: `{'checked': 0, 'reused': 0, 'stored': 0}`
- semantic_retention: `{'retained_bytes': 16776636, 'ordinary_bytes': 16776636, 'symbolic_bytes': 0, 'specialization_bytes': 0, 'evicted': 0}`
- miss reasons: `{'ordinary': [{'reason': 'no-retained-body', 'count': 24200}, {'reason': 'declaration-region-length-changed', 'count': 1}, {'reason': 'relocation-failed', 'count': 1}], 'symbolic': [], 'specializations': []}`

### ordinary-100k semantic budget 32 MiB

| state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| cold | 20 | 1703.1 | 1801.7 | 563008 |
| unchanged | 20 | 114.0 | 117.7 | 40464 |
| no_cache | 20 | 1264.2 | 1391.9 | 524424 |
| implementation_edit | 20 | 1338.4 | 2057.2 | 485032 |
| session_implementation_edit | 20 | 1254.2 | 1594.2 | None |

Implementation-edit exclusive phase p50 (ms):

| phase | p50 ms |
| --- | ---: |
| dependency_key_preparation | 664.0 |
| retention_store_io | 193.2 |
| source_load_parse | 122.5 |
| fresh_body_check | 94.0 |
| syntax_replay | 70.1 |
| source_merge | 43.3 |
| effect_origin_passes | 34.1 |
| ordinary_body_replay | 28.4 |
| syntax_parse | 3.9 |
| warning_derivation | 0.5 |

Last session-probe reply:

- specialization_bodies: `{'checked': 0, 'reused': 0, 'stored': 0}`
- symbolic_templates: `{'checked': 0, 'reused': 0, 'stored': 0}`
- semantic_retention: `{'retained_bytes': 33554386, 'ordinary_bytes': 33554386, 'symbolic_bytes': 0, 'specialization_bytes': 0, 'evicted': 0}`
- miss reasons: `{'ordinary': [{'reason': 'no-retained-body', 'count': 14909}, {'reason': 'declaration-region-length-changed', 'count': 1}, {'reason': 'relocation-failed', 'count': 1}], 'symbolic': [], 'specializations': []}`

### ordinary-100k semantic budget 64 MiB

| state | n | p50 ms | p95 ms | peak RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| cold | 20 | 1927.5 | 1979.9 | 592428 |
| unchanged | 20 | 127.1 | 139.6 | 40720 |
| no_cache | 20 | 1386.8 | 1877.7 | 524500 |
| implementation_edit | 20 | 1541.4 | 3849.7 | 555256 |
| session_implementation_edit | 20 | 1729.7 | 1955.9 | None |

Implementation-edit exclusive phase p50 (ms):

| phase | p50 ms |
| --- | ---: |
| dependency_key_preparation | 714.3 |
| retention_store_io | 383.7 |
| source_load_parse | 123.5 |
| syntax_replay | 73.3 |
| ordinary_body_replay | 56.2 |
| source_merge | 47.0 |
| effect_origin_passes | 36.8 |
| syntax_parse | 3.9 |
| fresh_body_check | 1.3 |
| warning_derivation | 0.5 |

Last session-probe reply:

- specialization_bodies: `{'checked': 0, 'reused': 0, 'stored': 0}`
- symbolic_templates: `{'checked': 0, 'reused': 0, 'stored': 0}`
- semantic_retention: `{'retained_bytes': 60639212, 'ordinary_bytes': 60639212, 'symbolic_bytes': 0, 'specialization_bytes': 0, 'evicted': 0}`
- miss reasons: `{'ordinary': [{'reason': 'declaration-region-length-changed', 'count': 1}, {'reason': 'relocation-failed', 'count': 1}], 'symbolic': [], 'specializations': []}`
