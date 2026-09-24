| program | vectorized loops before | after | vector widths after | reasons (before → after) |
|---|---:|---:|---|---|
| matmul | 1 | 3 | 4, 4, 4 | CantComputeNumberOfIterations 2→2; TooManyUncountableEarlyExits 6→6; EarlyExitNotLatchPredecessor 2→2; CantVectorizeLibcall 7→7; NonReductionValueUsedOutsideLoop 4→4 |
| nbody | 0 | 0 |  | CantComputeNumberOfIterations 2→2; TooManyUncountableEarlyExits 4→4; CantVectorizeLibcall 5→7 |
| spectral_norm | 0 | 3 | 4, 4, 4 | CantComputeNumberOfIterations 1→1; TooManyUncountableEarlyExits 1→1; EarlyExitNotLatchPredecessor 6→6; CantVectorizeLibcall 16→22; NonReductionValueUsedOutsideLoop 1→1 |
| sieve | 1 | 3 | 4, 4, 4 | CantComputeNumberOfIterations 6→6; TooManyUncountableEarlyExits 5→5; EarlyExitNotLatchPredecessor 3→3; UnsupportedUncountableLoop 1→1; CantVectorizeLibcall 3→3; NonReductionValueUsedOutsideLoop 6→6 |
| fannkuch_redux | 1 | 5 | 4, 4, 4, 4, 4 | CantComputeNumberOfIterations 4→4; TooManyUncountableEarlyExits 5→5; EarlyExitNotLatchPredecessor 5→5; UnsupportedUncountableLoop 1→1; CantVectorizeLibcall 9→9; NonReductionValueUsedOutsideLoop 2→2 |
| fannkuch_redux_array | 0 | 0 |  | CantComputeNumberOfIterations 2→2; TooManyUncountableEarlyExits 3→3; UnsupportedUncountableLoop 1→1; CantVectorizeLibcall 2→2; NonReductionValueUsedOutsideLoop 3→3 |
| bytes_scan | 1 | 2 | 4, 4 | CantComputeNumberOfIterations 6→6; TooManyUncountableEarlyExits 5→5; EarlyExitNotLatchPredecessor 3→3; UnsupportedUncountableLoop 2→2; CantVectorizeLibcall 2→2; NonReductionValueUsedOutsideLoop 8→8 |
| list_append_sum | 1 | 3 | 4, 4, 4 | CantComputeNumberOfIterations 4→4; TooManyUncountableEarlyExits 3→3; EarlyExitNotLatchPredecessor 1→1; UnsupportedUncountableLoop 1→1; CantVectorizeLibcall 3→5; NonReductionValueUsedOutsideLoop 6→8 |
