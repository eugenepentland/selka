
## 10k low-load primary (load 0.7-1.0)

### ordinary-10k  status=measured  lines=9935 bytes=186437 files=66 modules=66 imports=192 module_depth=66 checked_bodies=3139 specializations=0 call_depth=ok

| state | n | p50 ms | p95 ms | max ms | peak RSS KiB | parsed p/r | checked p/r | spec p/r | lowered p/r | emitted p/r | links p/r | bypass |
|---|---:|---:|---:|---:|---:|---|---|---|---|---|---|---|
| cold | 20 | 109.6 | 121.8 | 121.9 | 59424 | 66/0 | 3139/0 | 0/0 | 0/0 | 0/0 | 0/0 |  |
| unchanged | 20 | 12.5 | 13.9 | 14.0 | 32288 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |  |
| no_cache | 20 | 58.1 | 60.9 | 61.1 | 52032 | 66/0 | 3139/0 | 0/0 | 0/0 | 0/0 | 0/0 | semantic-reuse-unavailablex1;cache-disabledx1 |
| implementation_edit | 20 | 66.6 | 68.3 | 79.3 | 51904 | 1/65 | 2/3137 | 0/0 | 0/0 | 0/0 | 0/0 | declaration-region-length-changedx1;relocation-failedx1 |
| constant_edit | 20 | 68.8 | 76.9 | 78.0 | 53824 | 2/64 | 67/3072 | 0/0 | 0/0 | 0/0 | 0/0 | no-retained-bodyx66;declaration-region-length-changedx1 |
| signature_edit | 20 | 67.1 | 73.8 | 73.8 | 51104 | 2/64 | 67/3072 | 0/0 | 0/0 | 0/0 | 0/0 | no-retained-bodyx67 |
| union_edit | - | - | - | - | - | - | - | - | - | - | - | unsupported: no edit recipe for this family |
| provider_edit | - | - | - | - | - | - | - | - | - | - | - | unsupported: no edit recipe for this family |
| effect_edit | - | - | - | - | - | - | - | - | - | - | - | unsupported: no edit recipe for this family |
| session_implementation_edit | 20 | 35.4 | 36.0 | 36.0 | None | session (work deltas in JSON/CSV) | | | | | | |
| session_constant_edit | 20 | 35.7 | 36.1 | 36.4 | None | session (work deltas in JSON/CSV) | | | | | | |
| forced_tests | 3 | 721.9 | 727.5 | 727.5 | 123532 | cold_build=94022ms passed=1 timed_out=False | - | - | - | - | - | - |
### managed-10k  status=measured  lines=10022 bytes=196210 files=68 modules=68 imports=130 module_depth=3 checked_bodies=2756 specializations=128 call_depth=ok

| state | n | p50 ms | p95 ms | max ms | peak RSS KiB | parsed p/r | checked p/r | spec p/r | lowered p/r | emitted p/r | links p/r | bypass |
|---|---:|---:|---:|---:|---:|---|---|---|---|---|---|---|
| cold | 20 | 126.1 | 133.1 | 136.4 | 63584 | 68/0 | 2756/0 | 128/0 | 0/0 | 0/0 | 0/0 | generic-specializationx1;symbolic-no-retained-templatex2 |
| unchanged | 20 | 12.7 | 13.8 | 14.1 | 41368 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |  |
| no_cache | 20 | 77.9 | 80.5 | 80.6 | 53824 | 68/0 | 2756/0 | 128/0 | 0/0 | 0/0 | 0/0 | semantic-reuse-unavailablex1;cache-disabledx1 |
| implementation_edit | 20 | 93.1 | 103.0 | 108.2 | 62144 | 1/67 | 130/2626 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx1;declaration-region-length-changedx1;relocation-failedx64;generic-specializationx1 |
| constant_edit | 20 | 94.9 | 106.9 | 111.2 | 61824 | 2/66 | 195/2561 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx66;declaration-region-length-changedx1;relocation-failedx64;generic-specializationx1 |
| signature_edit | - | - | - | - | - | - | - | - | - | - | - | unsupported: no edit recipe for this family |
| union_edit | 5 | 92.0 | 97.4 | 97.4 | 60704 | 2/66 | 195/2528 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx68;relocation-failedx63;generic-specializationx1 |
| provider_edit | 5 | 92.5 | 94.8 | 94.8 | 61024 | 2/66 | 162/2592 | 126/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx126;no-retained-bodyx36;relocation-failedx63;generic-specializationx1 |
| effect_edit | 5 | 94.4 | 98.6 | 98.6 | 61504 | 2/66 | 130/2626 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx1;relocation-failedx64;generic-specializationx1 |
| session_implementation_edit | 20 | 58.0 | 58.3 | 58.3 | None | session (work deltas in JSON/CSV) | | | | | | |
| session_constant_edit | 20 | 57.9 | 58.3 | 58.3 | None | session (work deltas in JSON/CSV) | | | | | | |
| forced_tests | 3 | 760.0 | 765.5 | 765.5 | 115060 | cold_build=83899ms passed=1 timed_out=False | - | - | - | - | - | - |

## 100k ordinary low-load primary (load 0.8-3.1)

### ordinary-100k  status=measured  lines=100943 bytes=1969413 files=66 modules=66 imports=192 module_depth=66 checked_bodies=33475 specializations=0 call_depth=unsupported

| state | n | p50 ms | p95 ms | max ms | peak RSS KiB | parsed p/r | checked p/r | spec p/r | lowered p/r | emitted p/r | links p/r | bypass |
|---|---:|---:|---:|---:|---:|---|---|---|---|---|---|---|
| cold | 10 | 1249.0 | 1255.9 | 1255.9 | 544200 | 66/0 | 33475/0 | 0/0 | 0/0 | 0/0 | 0/0 |  |
| unchanged | 10 | 97.2 | 99.3 | 99.3 | 40128 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |  |
| no_cache | 10 | 1026.8 | 1042.4 | 1042.4 | 524016 | 66/0 | 33475/0 | 0/0 | 0/0 | 0/0 | 0/0 | semantic-reuse-unavailablex1;cache-disabledx1 |
| implementation_edit | 20 | 1001.5 | 1013.6 | 1017.3 | 444432 | 1/65 | 24655/8820 | 0/0 | 0/0 | 0/0 | 0/0 | no-retained-bodyx24653;declaration-region-length-changedx1;relocation-failedx1 |
| constant_edit | 20 | 1057.5 | 1113.7 | 1114.9 | 447792 | 2/64 | 24637/8838 | 0/0 | 0/0 | 0/0 | 0/0 | no-retained-bodyx24636;declaration-region-length-changedx1 |
| signature_edit | 20 | 1021.8 | 1074.5 | 1086.5 | 447480 | 2/64 | 24636/8839 | 0/0 | 0/0 | 0/0 | 0/0 | no-retained-bodyx24636 |
| session_implementation_edit | 20 | 1001.4 | 1009.6 | 1010.5 | None | session (work deltas in JSON/CSV) | | | | | | |
| session_constant_edit | 20 | 997.0 | 999.2 | 999.4 | None | session (work deltas in JSON/CSV) | | | | | | |

## 100k managed low-load primary (load 0.7-1.1)

### managed-100k  status=measured  lines=99878 bytes=1954866 files=68 modules=68 imports=130 module_depth=3 checked_bodies=32708 specializations=128 call_depth=unsupported

| state | n | p50 ms | p95 ms | max ms | peak RSS KiB | parsed p/r | checked p/r | spec p/r | lowered p/r | emitted p/r | links p/r | bypass |
|---|---:|---:|---:|---:|---:|---|---|---|---|---|---|---|
| cold | 10 | 1215.2 | 1230.3 | 1230.3 | 551352 | 68/0 | 32708/0 | 128/0 | 0/0 | 0/0 | 0/0 | generic-specializationx1;symbolic-no-retained-templatex2 |
| unchanged | 10 | 92.5 | 95.2 | 95.2 | 39648 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |  |
| no_cache | 10 | 1017.4 | 1023.5 | 1023.5 | 531500 | 68/0 | 32708/0 | 128/0 | 0/0 | 0/0 | 0/0 | semantic-reuse-unavailablex1;cache-disabledx1 |
| implementation_edit | 20 | 1045.7 | 1057.0 | 1057.8 | 515832 | 1/67 | 24137/8571 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx24055;declaration-region-length-changedx1;relocation-failedx17;generic-specializationx1 |
| constant_edit | 20 | 1057.1 | 1069.9 | 1079.1 | 519536 | 2/66 | 24089/8619 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx24007;declaration-region-length-changedx1;relocation-failedx17;generic-specializationx1 |
| union_edit | 5 | 1084.3 | 1118.6 | 1118.6 | 510620 | 2/66 | 23678/8529 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx23597;relocation-failedx17;generic-specializationx1 |
| provider_edit | 5 | 1068.1 | 1073.7 | 1073.7 | 516656 | 2/66 | 24139/8567 | 126/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx126;no-retained-bodyx24059;relocation-failedx17;generic-specializationx1 |
| effect_edit | 5 | 1057.7 | 1064.9 | 1064.9 | 514364 | 2/66 | 24137/8571 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx24055;relocation-failedx17;generic-specializationx1 |
| session_implementation_edit | 20 | 1055.6 | 1057.6 | 1057.7 | None | session (work deltas in JSON/CSV) | | | | | | |
| session_constant_edit | 20 | 1059.1 | 1067.0 | 1076.5 | None | session (work deltas in JSON/CSV) | | | | | | |

## 10k first pass (load ramp 7->14; do not use p95)

### ordinary-10k  status=measured  lines=9935 bytes=186437 files=66 modules=66 imports=192 module_depth=66 checked_bodies=3139 specializations=0 call_depth=ok

| state | n | p50 ms | p95 ms | max ms | peak RSS KiB | parsed p/r | checked p/r | spec p/r | lowered p/r | emitted p/r | links p/r | bypass |
|---|---:|---:|---:|---:|---:|---|---|---|---|---|---|---|
| cold | 20 | 410.0 | 478.8 | 480.8 | 62112 | 66/0 | 3139/0 | 0/0 | 0/0 | 0/0 | 0/0 |  |
| unchanged | 20 | 20.3 | 24.5 | 27.1 | 39660 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |  |
| no_cache | 20 | 103.9 | 113.1 | 116.6 | 52192 | 66/0 | 3139/0 | 0/0 | 0/0 | 0/0 | 0/0 | semantic-reuse-unavailablex1;cache-disabledx1 |
| implementation_edit | 20 | 116.1 | 377.0 | 379.0 | 52704 | 1/65 | 2/3137 | 0/0 | 0/0 | 0/0 | 0/0 | declaration-region-length-changedx1;relocation-failedx1 |
| constant_edit | 20 | 279.7 | 383.2 | 384.6 | 51424 | 2/64 | 67/3072 | 0/0 | 0/0 | 0/0 | 0/0 | no-retained-bodyx66;declaration-region-length-changedx1 |
| signature_edit | 20 | 123.3 | 383.1 | 391.9 | 53184 | 2/64 | 67/3072 | 0/0 | 0/0 | 0/0 | 0/0 | no-retained-bodyx67 |
| union_edit | - | - | - | - | - | - | - | - | - | - | - | unsupported: no edit recipe for this family |
| provider_edit | - | - | - | - | - | - | - | - | - | - | - | unsupported: no edit recipe for this family |
| effect_edit | - | - | - | - | - | - | - | - | - | - | - | unsupported: no edit recipe for this family |
| session_implementation_edit | 20 | 59.1 | 69.2 | 69.3 | None | session (work deltas in JSON/CSV) | | | | | | |
| session_constant_edit | 20 | 65.0 | 68.3 | 69.2 | None | session (work deltas in JSON/CSV) | | | | | | |
| forced_tests | 3 | 2661.9 | 2855.6 | 2855.6 | 120796 | cold_build=117100ms passed=1 timed_out=False | - | - | - | - | - | - |
### managed-10k  status=measured  lines=10022 bytes=196210 files=68 modules=68 imports=130 module_depth=3 checked_bodies=2756 specializations=128 call_depth=ok

| state | n | p50 ms | p95 ms | max ms | peak RSS KiB | parsed p/r | checked p/r | spec p/r | lowered p/r | emitted p/r | links p/r | bypass |
|---|---:|---:|---:|---:|---:|---|---|---|---|---|---|---|
| cold | 20 | 405.7 | 487.4 | 496.5 | 64224 | 68/0 | 2756/0 | 128/0 | 0/0 | 0/0 | 0/0 | generic-specializationx1;symbolic-no-retained-templatex2 |
| unchanged | 20 | 22.2 | 24.5 | 25.7 | 46472 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |  |
| no_cache | 20 | 145.5 | 160.1 | 171.0 | 53824 | 68/0 | 2756/0 | 128/0 | 0/0 | 0/0 | 0/0 | semantic-reuse-unavailablex1;cache-disabledx1 |
| implementation_edit | 20 | 353.4 | 414.6 | 424.3 | 59744 | 1/67 | 130/2626 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx1;declaration-region-length-changedx1;relocation-failedx64;generic-specializationx1 |
| constant_edit | 20 | 371.5 | 428.7 | 431.1 | 60384 | 2/66 | 195/2561 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx66;declaration-region-length-changedx1;relocation-failedx64;generic-specializationx1 |
| signature_edit | - | - | - | - | - | - | - | - | - | - | - | unsupported: no edit recipe for this family |
| union_edit | 5 | 144.6 | 158.2 | 158.2 | 60544 | 2/66 | 195/2528 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx68;relocation-failedx63;generic-specializationx1 |
| provider_edit | 5 | 386.5 | 416.5 | 416.5 | 60704 | 2/66 | 162/2592 | 126/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx126;no-retained-bodyx36;relocation-failedx63;generic-specializationx1 |
| effect_edit | 5 | 352.3 | 371.3 | 371.3 | 59744 | 2/66 | 130/2626 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx1;relocation-failedx64;generic-specializationx1 |
| session_implementation_edit | 20 | 104.5 | 107.4 | 108.5 | None | session (work deltas in JSON/CSV) | | | | | | |
| session_constant_edit | 20 | 105.4 | 111.7 | 112.0 | None | session (work deltas in JSON/CSV) | | | | | | |
| forced_tests | 3 | 791.2 | 797.5 | 797.5 | 115860 | cold_build=96638ms passed=1 timed_out=False | - | - | - | - | - | - |

## 100k first pass (ordinary under load ~12.5; managed load ~12.9->3.5)

### ordinary-100k  status=measured  lines=100943 bytes=1969413 files=66 modules=66 imports=192 module_depth=66 checked_bodies=33475 specializations=0 call_depth=unsupported

| state | n | p50 ms | p95 ms | max ms | peak RSS KiB | parsed p/r | checked p/r | spec p/r | lowered p/r | emitted p/r | links p/r | bypass |
|---|---:|---:|---:|---:|---:|---|---|---|---|---|---|---|
| cold | 10 | 3644.6 | 3679.7 | 3679.7 | 544620 | 66/0 | 33475/0 | 0/0 | 0/0 | 0/0 | 0/0 |  |
| unchanged | 10 | 167.0 | 184.0 | 184.0 | 40128 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |  |
| no_cache | 10 | 1259.1 | 2002.4 | 2002.4 | 524056 | 66/0 | 33475/0 | 0/0 | 0/0 | 0/0 | 0/0 | semantic-reuse-unavailablex1;cache-disabledx1 |
| implementation_edit | 20 | 1505.9 | 3075.7 | 3087.0 | 450748 | 1/65 | 24655/8820 | 0/0 | 0/0 | 0/0 | 0/0 | no-retained-bodyx24653;declaration-region-length-changedx1;relocation-failedx1 |
| constant_edit | 20 | 3094.9 | 3155.6 | 3156.1 | 450588 | 2/64 | 24637/8838 | 0/0 | 0/0 | 0/0 | 0/0 | no-retained-bodyx24636;declaration-region-length-changedx1 |
| signature_edit | 20 | 3132.4 | 3170.3 | 3200.6 | 451172 | 2/64 | 24636/8839 | 0/0 | 0/0 | 0/0 | 0/0 | no-retained-bodyx24636 |
| union_edit | - | - | - | - | - | - | - | - | - | - | - | unsupported: no edit recipe for this family |
| provider_edit | - | - | - | - | - | - | - | - | - | - | - | unsupported: no edit recipe for this family |
| effect_edit | - | - | - | - | - | - | - | - | - | - | - | unsupported: no edit recipe for this family |
| session_implementation_edit | 20 | 1954.3 | 1985.7 | 1988.7 | None | session (work deltas in JSON/CSV) | | | | | | |
| session_constant_edit | 20 | 1957.3 | 1991.2 | 1995.8 | None | session (work deltas in JSON/CSV) | | | | | | |
### managed-100k  status=measured  lines=99878 bytes=1954866 files=68 modules=68 imports=130 module_depth=3 checked_bodies=32708 specializations=128 call_depth=unsupported

| state | n | p50 ms | p95 ms | max ms | peak RSS KiB | parsed p/r | checked p/r | spec p/r | lowered p/r | emitted p/r | links p/r | bypass |
|---|---:|---:|---:|---:|---:|---|---|---|---|---|---|---|
| cold | 10 | 3798.6 | 3827.0 | 3827.0 | 551816 | 68/0 | 32708/0 | 128/0 | 0/0 | 0/0 | 0/0 | generic-specializationx1;symbolic-no-retained-templatex2 |
| unchanged | 10 | 161.0 | 190.6 | 190.6 | 39808 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |  |
| no_cache | 10 | 2048.3 | 2126.2 | 2126.2 | 531696 | 68/0 | 32708/0 | 128/0 | 0/0 | 0/0 | 0/0 | semantic-reuse-unavailablex1;cache-disabledx1 |
| implementation_edit | 20 | 1127.0 | 1189.8 | 1216.8 | 519384 | 1/67 | 24137/8571 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx24055;declaration-region-length-changedx1;relocation-failedx17;generic-specializationx1 |
| constant_edit | 20 | 1120.8 | 1125.0 | 1137.0 | 516404 | 2/66 | 24089/8619 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx24007;declaration-region-length-changedx1;relocation-failedx17;generic-specializationx1 |
| signature_edit | - | - | - | - | - | - | - | - | - | - | - | unsupported: no edit recipe for this family |
| union_edit | 5 | 1147.2 | 1161.2 | 1161.2 | 514848 | 2/66 | 23678/8529 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx23597;relocation-failedx17;generic-specializationx1 |
| provider_edit | 5 | 1126.6 | 1148.8 | 1148.8 | 519416 | 2/66 | 24139/8567 | 126/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx126;no-retained-bodyx24059;relocation-failedx17;generic-specializationx1 |
| effect_edit | 5 | 1120.0 | 1140.8 | 1140.8 | 513032 | 2/66 | 24137/8571 | 128/0 | 0/0 | 0/0 | 0/0 | not-ordinary-bodyx128;no-retained-bodyx24055;relocation-failedx17;generic-specializationx1 |
| session_implementation_edit | 20 | 1118.2 | 1138.3 | 1138.9 | None | session (work deltas in JSON/CSV) | | | | | | |
| session_constant_edit | 20 | 1113.1 | 1135.0 | 1138.4 | None | session (work deltas in JSON/CSV) | | | | | | |
