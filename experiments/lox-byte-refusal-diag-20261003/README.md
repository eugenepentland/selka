# Checked byte-length guard static diagnostics

These standalone QBE objects improve the isolated V1 guard's static successful path by at most two instructions. The best path still has 24 instructions against the selected compiler's 21. No compiler variant was built, no guest was run, and no timing or PMU measurement was performed. Selected compiler/source and frozen V1 are unchanged.

The complete `read_byte` IL extracted from the frozen V1 compiler on bytecode source V3 was copied, replacing only the first admission predicate and its branch polarity. The original unsigned index-below-length branch, captured receiver, payload/result handling, canonical normalizer, checked IP increment and traps remain byte-for-byte identical in IL. The separate control is the selected d14 compiler's original extraction for the same V3 source. All objects use the frozen adjacent QBE99ad and `cc -c`, through `scripts/build-slot.sh build`; exact argv, status/stdout/stderr, IL, assembly, objects, disassembly and SHA256 are in `receipts.json.gz`. `qualification.json` gives the compiler and all37 Lox source identities checked again after diagnosis.

| First predicate / refusal | Whole function instructions | Successful path |
| --- | ---: | ---: |
| V1 unsigned length <= I64_MAX, word result | 70 | 26 |
| Signed raw length >= 0, long or word result | 69 | 25 |
| Signed raw length < 0, inverted branch, long or word result | 65 | 25 |
| Raw length `shr 63` or `sar 63`, inverted branch | 64 | 24 |
| Unsigned length < raw 2^63 constant | 70 | 26 |
| Signed raw index >= 0 | 69 | 25 |
| Signed raw index < 0, inverted branch | 65 | 25 |
| Selected d14 canonical byte read | 55 | 21 |

The successful path is a static walk for IP=0, length=3 and a fitting IP increment. It includes `endbr64`, prologue and return. `analysis.json` records every instruction address and explicit branch choice; it is neither an emulator nor execution evidence. Total function size counts cold blocks too. Inverted branches shorten cold layout and change register copies; their smaller whole-function totals do not represent the executed saving. Both signed comparison polarities still emit `setcc`, zero extension and a boolean compare. The shift forms emit copy, shift, word-zero compare and branch, so they save two instructions versus V1 while leaving three extra instructions versus d14.

At the raw 64-bit word level, unsigned length <= 2^63-1 is equivalent to signed length >= 0, signed length < 0 refusal, logical right shift by63 equal zero, and arithmetic right shift by63 equal zero. These are backend operations on the loaded word, without a language cast or conversion trap. A logical shift yields0/1 and an arithmetic shift yields0/-1; their low32 bits preserve the branch truth value. A direct high-bit mask passed to word-valued `jnz` was deliberately excluded because truncating that result would lose the high bit. Existing SPEC's unsigned admission domain is preserved by the length predicates; its wording would need to describe any selected backend form accurately and independent review remains required.

The index-sign alternatives deliberately extend admission for nonnegative indices with length>=2^63. They refuse all negative indices before the unchanged unsigned bound. Nine of the30 synthetic boundary-model cells differ from the length-bounded certificate. This broader domain requires a separate certificate/SPEC review; it is not claimed eligible by this diagnostic. Guard refusal alone never implies a trap: the original canonical negative path retains its checked length-to-i64 conversion, while the canonical nonnegative path can read a huge-length receiver without that conversion. No synthetic huge allocation was executed.

To inspect the frozen archive:

```bash
python3 - <<'PY'
import base64,gzip,hashlib,json
from pathlib import Path
archive=Path('experiments/lox-byte-refusal-diag-20261003/receipts.json.gz')
receipt=json.loads(gzip.decompress(archive.read_bytes()))
out=Path('.tmp-byte-guard-inspect');out.mkdir(exist_ok=False)
for name,record in receipt['files'].items():
    data=base64.b64decode(record['base64']);assert hashlib.sha256(data).hexdigest()==record['sha256']
    target=out/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
print(receipt['variant_summary'])
PY
```

For a fresh standalone replay, restore only each group's `inputs.json` and `.ssa` files into a new private directory; keep its prior `.compiled.json`, `.s`, `.o`, `.asm` and analysis files absent. Run `python3 experiments/lox-byte-refusal-diag-20261003/run.py --work NEW_PRIVATE_DIRECTORY` for each group (top level, `index-sign`, `control`), then `analyze.py --work NEW_PRIVATE_DIRECTORY`. The runner refuses overwriting completed receipts and checks the QBE hash before and after. These commands generate assembly/objects only. Keep the recorded V1 experiment and selected compiler immutable; this experiment provides no runtime qualification or speed claim for changed guards.
