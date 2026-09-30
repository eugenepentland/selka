# Frozen LLVM constant-overflow proof

Source8a1bc3b3 admits exact signed64-bit +/-1 bound formulas through a local
reaching store. It makes no alias/escape assertion and leaves all original
loads, arithmetic operand availability, failure branches and trap details in
place. Unknown stores/calls/blits/address uses/control reset its facts.

`receipt.json` pins the source, compiler/QBE, source-file and all raw member
hashes. `lox-receipt.json` pins410 byte-identical input units and actual
machine change42→0 minimum-int MOVabs sites,27→76 jo/jno sites,32 ssub/48 sadd
intrinsic calls. The actual program prints30000. `guest-receipt.json` records
36 fresh tests across six distinct modes; the ignored MYLANG_RC_STATS attempt
is explicitly excluded and actual counting uses `--rc-runtime=stats`.

The1273-member raw archive contains every production input IL/translated
IR/signature set, actual LLVM binary/full assembly, strict-prototype patch and
VM body, test/install/Guardian logs, guest outputs and reproduction scripts.
All archive members were re-read and hashed after creation. Extract into an
owned scratch directory to inspect; native object caches are omitted.

Frozen checks:15 focused unit entries (34 admission shapes),13 golden entries,
3 new CLI entries (12 QBE/LLVM boundary pairs),3 existing CLI entries
(28 arithmetic-width boundaries),140 QBE-build tests,27 input/format steps,
12 install steps,36 fresh guests and88 whole-tree commit checks. The five
changed historical golden expectations keep their old IR beside the reviewed
new expectation.

Independent frozen review:54/54 admission identities (19 positive/35 refused),
43 valid functions with215,602 assertions each on baseline and candidate.
Eleven malformed/marked raw probes are admission-only. Root separately owns
that review's raw archive. Guardian feedback commit77dfbf3d records both this
checkpoint and the separate invocation attribution.

No lane hardware/timing sample was collected. Root owns composed all86
acceptance; functional success and removed machine constants do not waive the
per-row no-regression rule.
