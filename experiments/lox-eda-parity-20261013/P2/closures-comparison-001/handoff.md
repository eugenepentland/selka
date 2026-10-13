# Scalar reader affected-case closures diagnostic

The exact immutable full-campaign closures.vm.2000000.lox input and stdout oracle are pinned in compare.py and samples.json. Input SHA256 cf29bbd883baa67b28d3e0240c695608801f46067fe93a478a277286a88e33f8; expected stdout SHA256 5c1bc928b1aa3275718aed95eabf1c87b836a3122be2ab4b376856b2e44029db. Binaries/compiler are the same immutable C1 and isolated scalar arm used for the fib diagnostic. Short-only is excluded.

Authorized invocation from P2 worktree after dev-env.sh and shared slot export, CHUNK=1,2,3:

```bash
scripts/build-slot.sh timing timeout 58 taskset -c 8 python3 experiments/lox-eda-parity-20261013/P2/closures-comparison-001/compare.py CHUNK
```

Tickets1344/1345/1346, wrapper PIDs290041/292515/294549, admission waits30/5/5s. All three completed0 within bounded wrappers. Each chunk calibrated fresh Zig with2warmups+5measurements, using3x median capped120s per guest. Each chunk used2warmup pairs and3 alternating measured pairs, nine measured pairs total. Guest timeout cleanup kills and waits the entire guest process group. Every sample checkpointed, all retained.

All18 measured and12 warmup guests completed exact expected stdout/empty stderr/status0. No censors. Scalar wins9/9 pairs. Median paired scalar/C1=0.91002440496 (9.00% lower). Median scalar/fresh Zig=1.79659761917; matching C1/fresh Zig=1.97450288576. Zig calibration medians0.76872809604/0.76432356401/0.77132294909s. This is an affected-case diagnostic, not an all-case parity claim or historical arm comparison. summary.json records all nine paired ratios. The scalar source-002 overlay has been independently verified byte-identical to the qualified scalar snapshot.
