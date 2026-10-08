# Integer parsing: isolate the floating frame

This separate worktree starts at integrated join source `957f97c6`, with equality
unchanged. No benchmark, contract, allocation/accounting setting or reference
policy is edited. Existing integer/float grammar implementations remain shared
between the VM and native exports.

Actual source957 RF LLVM text code reserves `0x3b8` stack bytes and saves five
callee registers in `myl_native_bytes_number_parse` before checking the floating
mode. `native_format.zig`'s wrapper contains the floating grammar and its large
canonical buffer alongside the integer path. Separate noinline helpers now own
floating scalar/octet parsing, retaining the same success bits/status and the
rule that failure leaves output untouched. This is a general integer/float
dispatch change; no separate parser or fixture specialization is introduced.

Focused native-export checks include signed minimum with underscores/whitespace,
positive overflow, scalar integer parsing, nonzero floating flags, decimal and
infinity results, malformed float and empty input with an output sentinel.
Existing shared grammar vectors cover scalar/octet parity, including malformed
numbers, overflow, underscores, whitespace and floating rounding horizons.

The source design was prepared during another agent's timing lane, with builds
held. After release, four focused native-format tests and three shared-grammar
tests pass in Debug mode through the reserved build-slot wrapper, with private
caches and disk TMPDIR. Logs are retained. Reproduce:

```sh
scripts/build-slot.sh build zig test src/native_format.zig -ODebug
scripts/build-slot.sh build zig test src/number_text_test.zig -ODebug
```

No compiler build, emitted-code improvement or timing is claimed by the
implementation commit. Source-bound compiler/guest builds and int_parse plus
related float/CSV/JSON/text controls follow under unchanged six-arm policies.

The source-bound Debug host and all 24 RF guests now build; 140 fresh text
oracle outcomes, six refusal probes and two artifact records pass. Actual LLVM
byte-parser code shrinks from about 3104 to 410 bytes. It reserves no floating
scratch frame and saves two callee registers instead of five.

The six-arm exploratory screen checks int_parse, int_format, CSV, JSON, search
and join at both sizes, five rounds/one warmup/CPU2: 360 samples and 720 fresh
qualification checks. A matched Debug5a-to-Debug52 comparison retains 288 exact
outcomes. LLVM parsing after/before is 0.952164 small and 0.979835 large, but
large search repeats the prior blocker at 1.168492. Formatting is 1.024535 /
1.041571; CSV 0.994773 / 1.017796; JSON 1.005283 / 1.001158; search small
1.004810; join 1.023039 / 0.975884. Absolute six-arm costs are broadly higher
than earlier sessions, including unchanged external ports; only the matched
comparison isolates candidate effects within this session.

The candidate remains unintegrated: modest parsing gains do not justify the
repeated search regression. No extra timing or confirmation was run.
evidence.json retains exact commands, native checks, receipt/assets/manifest,
raw/archive hashes, both reports and matched-host parser disassembly. The next
step is a causal search-helper/layout investigation; no cause is claimed yet.

Read-only search diagnosis binds the exact before/after hashes from the pair.
The scanner (772 bytes), index helper (1659 bytes) and actual shared kernel
(11984 bytes) have identical relocation-normalized instructions, including all
relative instruction/branch offsets and NOPs. The kernel entry and timed search
loop move from a 64-byte boundary to offset32; the scanner does too. The index
helper moves from offset32 to a boundary. Several placements changed, so this
is a correlation rather than a proven cause. search-layout.py records the exact
normalization, literal relocation mappings and backward targets; its read-only
objdump/nm inputs and outputs are archived in search-layout-evidence.json.
A separate scanner alignment diagnostic follows under unchanged algorithms.
