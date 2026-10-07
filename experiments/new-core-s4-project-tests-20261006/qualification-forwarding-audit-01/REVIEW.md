# Qualification argument forwarding

The current M conformance adapter reproducibly consumes the historical sweep's
`--core` argument as an abbreviation of its own `--core-source`. With the source
revision supplied first, the executable path overwrites that revision. The
historical parser then receives no `--core` argument and selects its default
`zig-out/bin/mylang-core`. Supplying the full source option last avoids the
revision overwrite but still loses the explicitly selected executable.

This receipt executes only the actual parser-construction statements extracted
from the source AST and the shared `receipt_arguments` definition. It executes
neither wrapper `main`, historical sweep `main`, a compiler, nor a native guest.
All five input source hashes remain unchanged. The first audit setup lacked the
`BASELINE` globals; its NameError and exact script are retained separately. The
corrected audit uses the same default baseline paths as the real adapter.

The minimal behavioral correction is:

```python
parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
```

For a meaningful permanent selftest, extract the existing conformance parser
construction into `arguments(argv=None)` returning
`parser.parse_known_args(argv)`, then have `main` call that helper. The test must
exercise that real helper, rather than instantiate a second parser with copied
options. Assert that an explicit 40-character `--core-source` is unchanged and
the exact historical argv still contains the requested `--core` and executable
path. Cover both orders of receipt/historical flags and both separate/equals
forms. The pure control already passes all four combinations. Parsing the
forwarded argv with the historical parser additionally verifies that the
selected executable is the requested one, rather than a default.

`project_matrix.py` and `fuzz_matrix.py` both define their own exact `--core`
option and use `parse_args` in a single stage. Exact options win over prefixes,
so neither reproduces this swallowing bug; the receipt checks the same core
binary/source tuple before and after disabling abbreviation. Setting
`allow_abbrev=False` there is consistent optional strictness, not a required
repair for this concrete defect. The frozen historical sweep needs no edit.

`summary.json` has schema `s4-parser-forwarding-audit-v1`, the RED tuple, controlled
GREEN tuple, four exact forwarding cases, direct-wrapper review and five source
hashes. `manifest.json` hashes this small evidence package. No M edit or Git
mutation, Guardian invocation, timing qualification, compiler/native execution
or source merge is part of this read-only audit.
