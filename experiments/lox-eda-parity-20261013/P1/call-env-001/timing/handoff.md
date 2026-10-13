All three four-arm diagnostics completed: CPU8, two initial warmups, nine alternating rounds in three resumable chunks, fresh Zig calibration and 3× guest cutoff. All108 measured invocations passed pinned output checks; zero censors. Exact commands, admissions, raw receipts/progress, hashes and paired samples are retained here. Original six pair specifications remain unchanged.

| Case | C1/Zig | Call-env/Zig | Getters/Zig | paired call-env/C1 | paired getters/C1 |
|---|---:|---:|---:|---:|---:|
| fib | 1.1841 | 1.1588 | 1.1368 | 0.97867 | 0.96024 |
| invocation | 1.0516 | 1.0472 | 1.0167 | 0.99764 | 0.96847 |
| string_equality | 1.9007 | 1.8936 | 1.7237 | 0.99682 | 0.90517 |

Call-env wins all9 fib pairs (median2.13% reduction), but invocation/string equality effects are subpercent and noisy: respective paired ranges0.98246–1.01495 and0.98618–1.00817. Getter shaping wins all9 pairs in each case (median3.98%,3.15%,9.48% reductions). These bounded diagnostics do not establish all60-case parity or combined-overlay effects. C1 median drift versus earlier runtime001 is visible; paired observations are the comparison basis. Getter-only merits combined qualification; no adoption is asserted.

Read-only string-equality path review: exact runtime001 input executes two10000-iteration loops, resetting i; first contains1280 discarded local reads per iteration, second640 discarded equalities and1280 operand reads. Total25.6M local reads and6.4M equality evaluations. values_equal compares ObjRef scalars; string hashing/interning occurs during literal setup, not repeated equality. Baseline native evaluate7906B/execute5606B have get_variable/env_at/values_equal inlined; baseline env_slot/env_enclosing remain functions, removed in getter-only. execute_block allocates each lexical environment, including empty loop-body scopes. A separate C1-derived discarded-resolved-local-expression prototype is the next bounded proposal; no string-hash optimization is justified by this workload path. Skipping lexical scopes would require preserving resolver hop semantics and is broader.
