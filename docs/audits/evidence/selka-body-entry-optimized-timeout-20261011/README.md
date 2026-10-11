# Optimized B7 entry generations and incomplete matrix gate

The root gate at `3e44a64df34bc06ee79b0a2f5781286a83140809` exits 1:
136/139 steps succeed, with one failed action. The installed normal/edit body
matrix exceeds its outer 600-second subprocess deadline. It produces no complete
matrix report, and the body gate does not reach its release phase. This archive
does not claim a passing full gate or completed pure tests in both modes.

The independent entry qualification completes both debug and release lanes.
Each passes 349 operations, 35 captured body exchanges, 15 resource forgeries,
and two generations of all seven actual component entrypoints. Each of the seven
binaries is byte-identical between generations within its lane. Actual library
admission passes 213 operations and four join forgeries. Both entry reports and
the library report have zero failed or skipped operations.

The selected native Guardian verdicts total 2,806 passed, zero failed and zero
skipped. The aggregate Zig summary reports 2,808 passed and 25,843 shard-filter
skips. Formatting checks 1,006 sources with 208 exclusions and zero failures.
The packaging schema assertion passes; the separate normal/edit matrix timeout
is the only failed action. The expected pure-test inventory contains 286 tests
across 46 roots; an inventory is not a completed gate verdict.

`summary.json` binds reports to the exact installed manifest inventory, source
commit and host/body artifact hashes. The Debug host is
`ee9bc995df50cac1d29e6c3c8cfd16807862f0ce95e601e7dec57eeb4e62f0b5`,
and the body artifact is
`337e7d27b241c8699d8d754adae801a7c230be1aacb2edb54cc042e923a60a5a`.
The archive retains 195 component source files and 194 exchange paths using 51
compressed payloads. Every retained frame was reconstructed and checked against
its original size and SHA256. Run `sha256sum -c SHA256SUMS` to verify the retained
files, or `python3 reconstruct_frame.py ORIGINAL_PATH OUTPUT` to restore a frame.

The next harness change extends the whole-matrix deadline to 1,800 seconds while
preserving individual guest/transport limits and all required checks. It requires
a fresh gate result. That change does not alter this archived attempt's failure.
The native catalog, later semantic passes, Core/LLVM backend and driver remain;
neither complete compiler bootstrap nor performance acceptance is established.
