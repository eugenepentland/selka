# Module callable shadow receipts

The base source is `685e26311935cea0697726614a3897baff4f286f`.
The accompanying commit contains the production fix and regression tests.
`source.patch` records the exact candidate source delta; `identity.json` records
the compiler and input hashes. Compressed logs and JSON preserve exact commands,
raw output and negative controls. `validate.py.gz` is the final four-run guest
driver; its initial version and output are retained separately.

`accepted-gc-before.json.gz` reproduces the original module resolver failure
with the accepted GC compiler and confirms unchanged resolver source on `main`.
The final focused and guest checks pass; integration owns the fresh full gate.
