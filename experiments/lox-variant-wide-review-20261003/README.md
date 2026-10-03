# Independent review of fresh variant word stores

The reviewed compiler change widens two stores only in an already cleared,
fresh ordinary variant. The tag occupies bytes 0–3 and the sole active bool
occupies byte 8. Admission requires the Linux AMD64 little-endian native ABI,
16–32 bytes, alignment eight, ordinary byte copying without unique drop, at
most eight cases and physical fields, and one matching active bool field at
offset eight. A zero-extended word replaces each narrow store; bytes 4–7 and
9–15 remain zero. `loadub` preserves the complete raw payload byte.

The hook keeps full clearing, tag initialization, the partial-value journal,
source/address/region evaluation, payload reading, error provenance and final
publication in their established order. Private per-PC aggregate storage is
separate from the bool operand word and is cleared on every construction.
Inactive managed cases retain their descriptors and guards. No ownership
helper, callback, arithmetic check, source PC or cleanup operation changes.

This is an RC constructor change, including RC counting. Counting is authorized
only with unchanged event order and exact fresh runtime comparisons. GC,
borrowed bodies and legacy sharing use their existing aggregate path. Niche,
narrow, domain, misaligned, tag/payload overlap, multifield and unique-drop layouts
retain ordinary widths. Other variant operations and general field writes are
outside this hook.

The accompanying receipt distinguishes author-run checks from this read-only
review. The exhaustive 1,536-case raw-byte check is an emitted-store host model,
not native execution of malformed boolean values. Failed installation and
launcher attempts are retained separately and contribute no successful rows.
Static store-width counts are diagnostic evidence; they do not establish a
speed improvement or compiler selection.

The retained author qualification is separately checked: four actual Lox guest
builds; eight small native constructor pairs with identical complete counting
stderr; 336 fresh accounted AST checks and 28 constructor checks; 1,168 bounded
native Lox pairs, 96 AST-focused pairs and eight checked RC native-stress
refusals. The native matrix keeps all 80 omitted smoke/stress cells explicit.
It covers 23 error programs, 16 regressions and 13 smoke programs on both
evaluators and backends. Directory public tests omit provider execution.

The 22 focused checks and 28 constructor-acceptance checks overlap and are
listed separately. The final requested Guardian run returned zero and printed
88 checks; the author describes this as confirmation of its prior green gate.
The broader unit run reports 2,490 passes with process status zero, while also
reporting RSS above its declared limit. That receipt establishes test outcomes,
not a resource-clean full gate. All raw warnings and misleading failed-command
footers are retained.

Run `taskset -c 16 python3 -B experiments/lox-variant-wide-review-20261003/verify.py`
from this checkout to recheck the retained identities and completed coverage.
It never builds a compiler, runs a guest or performs a performance measurement.
