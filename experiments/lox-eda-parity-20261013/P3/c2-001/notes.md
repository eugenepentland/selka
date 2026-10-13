This is a rejected private C2 tokenizer prototype. Checked suite, boundary,
allocation, and full application output qualification pass, but both approved
nine-pair diagnostics regress. Preserve source-002 and do not integrate V2.

`inputs.json` pins source-002 and compiler C2. `tokenizer-v2.patch` changes only
the scanner. The original byte-by-byte implementations remain as cold helpers.
Normal runs scan whitespace/comments, string contents, digit runs, and atom
tails in scalar locals, committing the cursor at the end of each run. Numeric
suffix classification and suffix advancement retain the frozen behavior.

`scan_counters_fit` admits only nonnegative positions whose line/column can
advance by the entire source length without overflow. Unusual public cursors
retain the original helper updates and failure order. An unterminated string
commits its partially advanced cursor and stores the opening span, including
escaped newlines and a final backslash. Successful scans preserve error_span.
Neither public token storage nor independently owned final AST output changes.

The C1 P5 580-sample profile motivates inspection; it is not a C2 profile or
runtime comparison. C2 LLVM and native assembly excerpts are pinned in
`static-inputs.json`. They show repeated signed index normalization, bounds
checks, newline tests, and cursor field writes in the old per-byte scanner.

The initial V1 focused checked differential receipt passed 2/2. The initial V1
full-suite receipt reports 330 assertion passes and one `SourceChanged` wrapper
failure because a probe was added during directory discovery. That receipt is
retained as invalid qualification. V1 also predates the near-limit cursor guard.
Final V2 qualification repeats the entire frozen directory with checked zero RC,
verify-facts, and force: 330/330 passed, zero failed/cached/skipped/unsupported.
No sources in that directory changed during the run.

The differential tests compare token tag, owned bytes, span, cursor, and previous
error_span against the frozen public tokenizer: all 256 bytes in seven contexts,
corpus prefixes, escaped/raw invalid UTF8, negative wrapped cursors, and EOF.
`qualify_probes.py` independently builds both final parser and boundary probes,
compares nine checked boundary modes, requires zero RC and zero exit-live, and
compares managed allocation/copy/peak counters. All nine modes match. Both parser
arms allocate 18,000 objects / 2,432,000 bytes, peak 2,336 bytes, zero copies or
reallocations, zero live bytes at exit, zero RC/share/unique-test events. Total
instrumented calls fall 596,001 to 381,001; advance 103,000 to 17,000 and peek
197,000 to 35,000; the guard adds 33,000 calls. This is not a runtime comparison.

`qualify_application.py` built the checked uninstrumented application with C2.
Both rds3+flat and cyclops-digital-pcb pass: baseline/candidate stdout, stderr,
and six-file emitted trees match, and both case trees match Zig and golden.

`measure_pairs.py` ran only the six coordinator-released leases. It adapts frozen measure.py only
to select baseline/candidate as the two measured arms while Zig remains the
calibration/oracle arm, and alternates warmup order. The approved protocol is
fresh 2+5 Zig calibration, exactly min(120s,3*Zig median) for both checked arms,
two warmup pairs and nine measured alternating pairs per case, all journals and
samples retained, with three bounded three-pair leases per case linked through
prior_receipt. Exact plans and binary/calibration identities were sent before
scheduling, after all qualification conditions passed. All samples completed;
none were censored, failed, or discarded. RDS3+flat baseline/candidate medians
are 100.814896/101.959615 ms, ratio 1.011355, paired 95% CI [1.003598,1.025534].
Cyclops medians are 47.443466/48.527092 ms, ratio 1.022840, CI
[1.011203,1.035057]. timing-summary.json retains all nine exact pairs, ranges,
fresh Zig calibrations, and receipt hashes. These are C2 diagnostics, not final
integrated parity: Zig was calibration/oracle, not nine paired Zig timings.

native-comparison.md separates observed uninstrumented code changes from the
inference about extra guard/control/temporary costs. Fewer counted calls do not
justify this measured slowdown. Stop scanner prototypes for this batch.
