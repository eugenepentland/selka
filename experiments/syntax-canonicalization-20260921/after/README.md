# Post-implementation canonical syntax evidence

This directory is an additive follow-up to the immutable baseline in the parent
directory. It captures the same probes with `zig-out/focus/mylang`, plus focused
cases for stored dictionary views, `list(range(...))`, keyed sorting, and the
library text/number wrappers under `noalloc`. It also checks that a single text
piece f-string is valid under `noalloc`.

The driver defaults to the focused compiler. Run it from the repository root
only after rebuilding that compiler:

```sh
python3 experiments/syntax-canonicalization-20260921/after/probe_after.py
```

Set `MYLANG_CANONICAL_AFTER_COMPILER` to capture another finished compiler. The
checked-in evidence used the final `zig-out/bin/mylang` produced by the green
full build:

```sh
MYLANG_CANONICAL_AFTER_COMPILER=zig-out/bin/mylang \
  python3 experiments/syntax-canonicalization-20260921/after/probe_after.py
```

The driver imports the original `probe.py`, redirects every generated artifact
into this directory, and records the focused compiler's path and SHA-256 before
and after capture. `evidence.json` also compares static emitted-IR call-site
counts with the parent baseline. Those counts describe emitted QBE only; they
are not dynamic allocation counts or timing measurements.

The behavior probe prints the unified numeric-parser results and integer totals
walked through stored `items()` and `values()` views. Views themselves are not
sent to the generic printer because their compositional iteration behavior is
the property under test.
