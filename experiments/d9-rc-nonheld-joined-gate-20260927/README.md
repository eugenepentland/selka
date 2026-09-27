# Joined nonheld-capture gate

Frozen source `6983288b12c40579483c935449aa6b8488075a89` passes the complete
four-command gate and both forced counted-RC language sweeps. Exact commands,
raw logs, source/compiler identity and artifact hashes are retained here.
The scripts require unchanged HEAD and tracked source at both ends; the gate
uses the shared flock and build-slot wrapper, private cache and disk temporary
storage. LLVM uses the actual release backend with O3 and full LTO.

There are 2,318 executed main tests (23,641 shard exclusions), 442 QBE tests,
29 native-build steps, two formatting steps and 88 Guardian checks. Each RC
backend sweep passes 938 assertions across 161 programs with no failed, skipped,
cached, dropped or unloaded results.

Passing these checks does not resolve the separately reproduced record-field
snapshot bug, including heap and arena records. That newly identified case was
outside these prior suites and remains explicit correctness work. Full-corpus
performance and the ordinary RC default transition also remain open.
