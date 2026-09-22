# Application normalization measurement

The application-only comparison uses the retained compiler at
`.tmp/schematic-implementation-20260921/before-mylang` for both arms. Each arm
was built in a fresh cache with the legacy LLVM adapter at O3, ordinary checks,
collecting GC, step accounting, frame accounting and retained symbols. The two
receipts identify the same runtime archive hash.

Twenty-one randomized, interleaved rounds after three warmups were pinned to CPU
6. The interval covers process launch, reading the three 25,845-byte documents,
rendering to the private output file and shutdown; compilation is excluded.
Median elapsed time fell from 84.77 ms to 44.80 ms. The after/before ratio is
0.528, with a paired-bootstrap 95% interval of 0.527–0.530, corresponding to a
47.2% reduction in this batch.

Every timed invocation checked exit status, stdout, stderr, issue bytes and the
complete 49,617-byte SVG. Both arms emitted SHA-256
`68157ea785ee3766c039714d1d081ea1c7a55def6cf9124660495f8b797ed388`.
Independent geometry passed for the fixture and for a changed-net input; the
changed result differed from the fixture and remained byte-identical between
arms.

Focused differential cases also swapped two ordinary net names, swapped adjacent
passive declarations, reversed a passive's pin declaration order, renamed the
folded rail base to exercise the raw/display identity namespace, and reused an
ordinary raw net spelling as an NC label. Each accepted case remained completely
byte-identical between arms and passed geometry. An empty connected net was
rejected by both arms with the same located `SCHEMATIC_13` issue and no SVG.

The implementation resolves raw and folded display-net spans once per pin,
assigns compact identities, records passive part pin indexes, caches ground,
rail and decoupling facts, and uses identities in graph construction, placement
and routing. Route obstruction tests reject nonintersecting geometry before
checking net identity. Source spans remain attached for diagnostics and SVG
metadata, and first-seen scans preserve existing branch and tie ordering.

The before snapshot was reconstructed with `git show HEAD` after editing had
started. Every copied guest file was subsequently verified byte-for-byte against
`HEAD`, and the initial status showed no guest paths as modified, but there is no
independent pre-edit copy of the dirty working tree. The result measures these
three existing fixtures on one machine and is not a general schematic-size
scaling result or a comparison with Zig.

Raw samples and provenance are in `implementation-measurements.json`; correctness
results are in `implementation-qualification.json`. Reproduce them with
`python3 -B experiments/schematic-parity-audit-20260921/implementation_measure.py`
after building the two private binaries recorded there.
