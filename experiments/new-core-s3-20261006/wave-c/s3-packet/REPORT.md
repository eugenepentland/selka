# S3-A byte-index performance repair

This isolated package starts at application foundation `ac81831bd9e6100bf8d31cc07ca97bcff9f82d6c` and freezes compiler source at `1c3e53fd40c0ca4c16d67d09048e6ec5afbd349c`. Packet and JSON pass both performance gates at both sizes. Full Core shards, strict conformance and both final fuzz families pass. No integration or main merge is claimed.

## Implementation and authority

The foundation packet profile attributes 55.56% of zero-loss samples to the external `myl_core_bytes_index_offset` helper. The builder now declares only its byte-index branch with compiler `runtime_c` authority. The LLVM emitter recognizes its exact `(bytes|byte_buffer, i64) -> u64` ABI, with no ownership/view flags, and emits the ordinary block-length load, negative comparison, unflagged modular addition and select. The original list bounds condition and located trap remain. The addition has no overflow flag, so overflow in an unselected positive-index arm cannot introduce poison. Unknown signatures retain their ordinary call. An `extern_c` with the same exact ABI remains foreign, and a source extern using this reserved name receives the existing `E_EXTERN_SYMBOL` rejection.

Inlining removed the runtime helper hotspot but packet/4096 still missed the old-core gate at 1.112. The final narrow forwarding pass exposes existing nonnegative indices to facts and vector planning. It changes only the exact compiler-owned adapter when the original signed index already has a nonnegative interval and every consumer is a byte `list_get` for that same receiver. Its signed copy is legal for this index operand. Negative or unknown intervals, foreign callees, other uses, and returned unsigned adapter values retain normalization. No new IR, fact, integer flag, ownership change or trace suppression is introduced.

Forwarding is disabled under `--verify-facts`. This follows the existing verification approach, rather than using verification to bypass the premise: the original counted-loop raw phi has its exact nonnegative lower bound checked by `assertFacts`/`assertRange` before normalization. The regression identifies each eligible phi and checks its `icmp slt ... 0` assertion in emitted verification LLVM. A second native regression injects the claimed interval `[0, 9223372036854775807]` on an otherwise valid input `-1` and requires `R_CORE_FACT`, including the exact range/value diagnostic. The trusted reduction vectorizes; the verification reduction retains normalization and assertions and returns 5387 with status 0 and empty stderr. `reduction-trusted.ir`, `reduction-verify.ll` and `reduction-verify-run.json` retain the evidence.

## Bounds fidelity and regressions

Edge comparisons exposed an existing Core port defect: immutable bytes below `-len` and at `INT64_MIN` reported the adjusted index, whereas the old core reports the original source index. `indices-01/` retains twelve complete report mismatches from the foundation implementation. The authorized adapter's raw operand now supplies only the failure report; access and the bounds condition still use the normalized offset. Mutable bytes already reported the raw index. The final `indices-03/` refresh compares complete status/stdout/stderr records in debug/release/verify against the qualified old debug/release oracle: **54 comparisons, zero mismatches**. Its cases cover bytes and mutable byte buffers at `-1`, `-len`, `-len-1`, zero, last, positive out-of-range, `INT64_MIN` and `INT64_MAX`, plus empty immutable bytes at -1 and zero.

All seven focused Core regressions pass (`logs/focused-07.txt`). They are embedded in `src/core/byte_index_test.zig`, so no fixture/input-manifest change is required. Earlier focused failures were test construction or compile errors; their original logs remain. Guardian initially requested explicitly typed generic parameters, a split signature condition and a file-scope print alias. The corrected gate and both normal source commits pass all 88 checks.

## Performance

`rows-02.json` retains seven shuffled interleaved rounds, startup subtraction, CPU-10 native argv/status/stdout/cycles and checksum equality for all four configurations. The shared timing lock is `/run/user/1000/mylang-s2-cpu10.lock`.

| Row | Size | New cycles/unit | New/old | New/Zig | Both gates |
|---|---:|---:|---:|---:|---|
| packet_decode | 4096 | 15.986 | 1.058 | 0.842 | Pass |
| packet_decode | 64 | 15.922 | 1.056 | 0.813 | Pass |
| json_transform | 4096 | 2825.950 | 0.207 | 1.002 | Pass |
| json_transform | 64 | 2971.229 | 0.212 | 1.038 | Pass |

Packet's foundation measurements were 48.339/48.973 cycles/frame. The final profile has 4,086 samples and zero lost samples: main 88.02%, error-trace runtime 11.95%, and no byte-index normalization helper. The first inline-only profile and annotation remain for comparison (`profile-02.txt`, `packet-annotate-02.txt`): main 90.40%, trace 9.60%, with LLVM's four-wide i64 reduction. The stripped old binary yielded no named main samples, so its unsuccessful named annotation is retained without a symbolic-profile claim.

`micro-01.json` checks the affected bytes/number rows, all checksums equal and both gates passing at both sizes:

| Row | New/old 4096 / 64 | New/Zig 4096 / 64 |
|---|---:|---:|
| bytes_scan | 0.625 / 1.010 | 0.037 / 0.145 |
| int_parse | 0.636 / 0.640 | 1.017 / 1.090 |
| int_format | 0.321 / 0.300 | 0.318 / 0.317 |

`audit-02/` compares complete LLVM definitions for all 35 existing row programs against the exact foundation compiler: **all 35 identical**. Original S3-wide Host-prologue differences against `92590700` remain supported by S3-C's prior rowwise audit; this comparison isolates this byte repair. Raw definition files and statuses remain in both audit runs.

## Qualification and toolchain

- Strict full old/new conformance: **1518 matching, 0 mismatching, 0 unsupported**, independently in debug and release with leak/fact checking (`logs/conformance-01.txt`).
- Full Core32: **261 unique tests passed**, 36/36 steps, 141.20 seconds total and slowest shard 79.77 seconds, below the 300/90-second limits (`logs/core-tests-01.txt`, `.time`). The aggregate reports 261/8352 with 8091 intentional shard skips.
- Extended S3 text50: **50 accepted / 750 comparisons**, zero mismatches, refusals, leaks, fact failures, timeouts or crashes; seed 733, actual run 180.82 seconds (`fuzz-text-02/summary.json`). The fresh run overrides the inherited wrapper with S3-T1’s extended generator. The earlier inherited S2 text50 also passed but is not used for final S3 text qualification.
- Number50: **50 accepted / 750 comparisons**, zero mismatches, refusals, leaks, fact failures, timeouts or crashes; seed 731, actual run 500.67 seconds (`fuzz-number-01/summary.json`).
- Final meaningful exclusive rebuild: **3.65 seconds**, below 10 seconds, with fresh private Zig local cache and all three build slots held (`logs/core-03.time`). Earlier exclusive builds took 2.54 seconds and a cached 0.07 seconds.
- Frozen IR diff against `dc1a5831`: empty (`logs/frozen-ir-01.txt`).

The copied qualified oracle has compiler SHA256 `d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79` and QBE `b6139650a99b39131cd791fa1fdc84c09472dc303930bbadd3f8a5348487af4c`. Foundation Core is `0ae6485273394d7a2d365b8e029dcf781f1d6f4cd6581141db2517e00eb86a64`; final freshly rebuilt Core is `31168db0bf090f053fad74f4fcbc3155fec92ecce4d15290c38eaebbc8b9b068`.

Core test gates retain the gate FD through an intermediate shell. Ordinary guest/report/audit/fuzz builds and CPU10 measurements use build slots under the inherited S2 pace table; root clarified these require no additional gate slot. Each command has its own output log. Exclusive Core installation acquires all build slots while holding the gate to exclude simultaneous gate work; actual rebuild timing excludes slot admission.

Ownership, tracing, persisted formats, `tests/lang`, float formatter/cache source and language rules are unchanged. T2's measured float unit cold compile remains 0.96559 seconds (3.11696 seconds total first program), with 0.11394 seconds subsequent keyed-object reuse. Complete helper content, executing Zig `0.17.0-dev.1683+5ceec001b` and target/options remain cache inputs; this package makes no new cold-cost claim.

## Reproduction

From this worktree, the complete Core gate is:

```sh
scripts/build-slot.sh gate -- bash -c '"$@"; result=$?; exit "$result"' -- scripts/build-slot.sh build -- zig build test-core -Dcore-shards=32 --summary all
```

The final text qualification uses `experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py --kind text --harness experiments/new-core-s3-20261006/wave-b/s3-t1/fuzz_text.py --cases 50 --seed 733`; the number run uses the same wrapper with `--kind number --cases 50 --seed 731`. Both receive the private qualified `--mylang`/installed `--core`, fresh `--evidence`/`--cache-root` paths, and run through `scripts/build-slot.sh build`.

The report-comparison helper is `qualify_indices.py`; the complete-definition comparison helper is `audit_rows.py`. Application/micro timing uses the foundation `wave-c/s3-a/measure_all40.py` registry with `--rows packet_decode,json_transform` or `--rows bytes_scan,int_parse,int_format`, the shared CPU10 timing lock, and fresh private builds. The full commands and native results are retained in their JSON records; command output goes to a distinct numbered log for each run.
