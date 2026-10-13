# P5 admitted diagnostic and CPU evidence

The coordinator selected the exact two-module patch for separate source-002, with final full-corpus qualification pending. These are two-case diagnostics; the previous allocation savings remain demonstrated, but these wall-time probes show only modest effects against broad per-pair variation. No EDA parity, RSS improvement or robust general speedup is established.

| Case | C1 median s | Candidate median s | Zig median s | Candidate/C1 medians | Candidate/Zig medians | Median paired candidate/C1 | Pair range |
|---|---:|---:|---:|---:|---:|---:|---|
| stm32n6 | 0.058153799 | 0.057200542 | 0.034195240 | 0.983608 | 1.672763 | 0.992579 | 0.974762–1.065315 |
| rds3+flat | 0.102629502 | 0.101871723 | 0.062581443 | 0.992616 | 1.627826 | 0.990275 | 0.909630–1.077806 |

Both cases completed all 9 rounds per arm, zero censors. Exact qualified C1 stdout/stderr/file hashes matched every successful oracle/calibration/warmup/wall invocation. All raw journals and receipts are retained. diagnostic-results.json includes both full per-pair ratio arrays, medians and cutoff calibration evidence. The exact pinned measurer ran with 2 warmups, 9 alternating rounds, 5 fresh Zig calibration samples plus 2 calibration warmups, and a 3× Zig median cutoff (120s ceiling). RSS was not requested.

Each diagnostic ran through its own CPU 8 timing lease. The wrapper limits execution to 55 seconds and kills only its own tracked guest process groups; outer timeout is 58 seconds. The distinct CPU capture retains its 40-second perf deadline/55-second outer limit. All three wrappers exited successfully without expiry. authorization-and-commands.json pins commands and drivers. No nested admission.

## CPU attribution

Captured 600 cycles samples, 0 lost. Exact guest PID filtering includes 580 samples and excludes 20 Python driver samples. Guest leaf IPs: 513 in the pinned C1 app DSO, 67 in other DSOs. All 12 guest runs matched the qualified output oracle; guest PIDs and output hashes are retained.

Guest leaf counts: block_alloc 66, values_copy_box 58, core_owned_child 53, drop_owned 45, owned_octets_copy 18 (240 combined); parse_node 44, next_token 33; verify::check 35, grid_scan 20; compose::join_sites 30. These are sampled leaf counts, not exact CPU time shares or traffic counters. Parsing, verification and join_sites have direct CPU evidence for future focused investigation. Helper samples cannot be assigned to those callers.

DWARF user stacks were recorded, but application call chains did not reconstruct: zero guest chains contain app frames; 67 contain only other DSO frames. Python call chains reconstruct. No inclusive application or allocation-caller claim is supported. perf script --no-call-graph was rejected by this installed version; its diagnostic log is retained, and successful leaf decoding uses --hide-call-graph. Both report/script decodes succeeded offline with DEBUGINFOD_URLS empty and a private build-ID directory, outside timing admission.

Raw data is preserved in lossless gzip with its original raw digest and a checked decompression roundtrip; the uncompressed original remains in private scratch. raw-profile-archive.json pins both locations/digests. All decoded leaf symbols, stack text, all-PID report and filtering scripts are retained. The exact two-module patch is selected for source-002; C1 remains immutable and full-corpus qualification is pending.
