# Completed compiler wall closeout

`final-closeout.json` independently verifies the completed compiler-only
wall phase: four arms, all 13 scripts on VM and tree, and three original-size
rounds give exactly 312 unique samples. Guest, compiler, QBE, runtime, source,
command and log identities match; output hashes and complete empty ASCII
diagnostics match. Per-case summaries and paired arithmetic reproduce the
analysis and its tracked copy. No cells remain pending in this receipt.

| Compiler candidate relative to fixed control on source84 | VM reduction | Tree reduction |
| --- | ---: | ---: |
| LLVM wall time | -0.496014% | -0.659956% |
| QBE wall time | +0.377190% | -0.936326% |

Negative reductions mean slower execution. The median per-case paired-ratio
spreads are respectively 6.035456%, 11.043249%, 6.473296% and 7.006126%; these
are not maximum case spreads or spreads of engine geometric means. The small
changes provide no convincing wall-time win. Compiler candidate `33159179`
remains isolated; accepted source84 uses fixed compiler `d14a7040`. This
four-arm attribution excludes Rust and Go and makes no new parity claim.

The primary 1,300-row review and its later 468-row source-counter closeout are
preserved unchanged. Adding the 312 compiler-wall rows gives **2,080 unique
completed measurement rows**, without counting the 468 counters twice. The
earlier receipt's 44/312 observation remains explicitly historical. The
separate reconstruction review adds 156 behavior-only samples, not timing.

The independent verifier ran no guests, tests or performance commands and
changed no root sources or artifacts. Producer checks used full raw stdout,
but receipts retain its hash; per-sample raw perf CSV was not archived.
All diagnostics in these newly completed phases are empty ASCII, so the
retained 1,500-character tail contains their complete decoded diagnostic.
The primary review's statistical and provenance limits still apply.

Receipt SHA256:
`719b4b4f72fe9619c798254deaf277013e72134817ff416e390a8985b42080c4`.
Recheck using `closeout.py` with the same `--root` and a fresh `--out` path;
the verifier refuses to overwrite a historical receipt.

The completed checkpoint is root commit `44cd4307`. Its sealed evidence is
`/home/epentland/ai/canopy/evidence/lox-parity-20261003/callee-table`, whose
`MANIFEST.sha256` file hashes to
`94d85a11474d68c281d6b0e9010046ed5ebc8dd7ded019d43761b5d7c63b7272`.
This late review references that archive and leaves it untouched. The archive
already includes the primary and source-counter reviews; this closeout is a
separate follow-up, not a replacement or an archive amendment.
