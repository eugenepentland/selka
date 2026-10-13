# Private LLVM-only fib timing receipt

No source/compiler policy change. This compares two matching relinks: unchanged scalar baseline and the LLVM alwaysinline trial qualified in ../reader-inline-001, not the original scalar executable. Binaries/compiler/input/oracle/script hashes and every output/timeout check are in samples.json.

Exact authorized command after dev-env.sh and shared slot export, CHUNK=1,2,3:

```bash
scripts/build-slot.sh timing timeout 58 taskset -c 8 python3 experiments/lox-eda-parity-20261013/P2/inline-fib-001/compare.py CHUNK
```

Tickets[1356, 1357, 1358]; wrapperPIDs[335066, 369436, 379842]; ordinary admission waits[80, 50, 160]s. All chunks complete0 under bounded wrappers. Each chunk fresh Zig2warmups+5measurements,3xmedian guest cutoff;2warmup pairs+3globally alternating measured pairs,9pairs total. Guest group cleanup kills/waits entire group on timeout. All18measured+12warmup guests exact expected stdout/emptystderr/status0; no censors.

Median paired inline/unchanged relink=0.886119196896;9/9faster. Median inline/freshZig=1.823289704824; matching baseline/freshZig=2.069405309398. This is a diagnostic on one full input, not an all-case claim. All individual pairs/control calibrations retained in summary.json. For closures, pair3ratio.78751 is unusually large and retained; eight other ratios.91861–.94201. Cross-chunk absolute controls vary; paired ratios provide more direct comparison.

Important structural caveat: both reader wrappers disappear, but LLVM exposes/re-outlines constant_operand as202-byte native helper with12callsites (baseline0), while function_instruction remains inlined. This complete variant is measured; the benefit cannot be attributed exclusively to either reader. .text+0.63%, vm.run+19.91%; single fresh native compile pair1.56s baseline/1.58s inline, diagnostic only. Production policy and bounded-subset performance remain separately unqualified.
