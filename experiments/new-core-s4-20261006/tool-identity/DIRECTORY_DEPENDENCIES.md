# Directory dependency snapshot correction

The coordinator's retained `external-dependency-reduced-run01` demonstrates a
directory aggregate accepting cached child success after an imported source
outside the selected subtree changed while a sibling compiled. That red receipt
predates this correction. The fresh installed-artifact reproducer in
`experiments/new-core-s4-project-tests-20261006/external-dependency-corrected-run02`
now observes the expected aggregate refusal with SourceChanged after the cached
child completed. Installed Core SHA256 is
`ae95edc2e2d473fe052810345335e3558ad553b325bd0394af48c39ceafcaf98`.
Focused run12 also passes all 42 project/tool tests; full qualification is pending.

The delegated files are `src/core/test_runner_directory.zig` and
`src/core/test_runner_cases.zig`. They snapshot exact loaded dependency bytes
before child execution: normal module closures, distinct selected provider
overlay closures, embedded assets, project configuration and policy, inferred
case files including their absence, and required API files including absence.
Paths are deduplicated across entries; conflicting initial bytes refuse with
SourceChanged. Overlay module bytes are covered by the loaded cases file, while
base closures retain the actual disk source inventory.

The final check preserves the original sorted `.my` path set and detects its
additions/removals, validates each source/asset/control content digest, and
re-resolves each entry's root, module name and winning configuration path. This
catches a newly introduced nearer project configuration without recursively
snapshotting unrelated files or native outputs. Shared receipt.readDigest owns
bounded disk content hashing and error behavior.

`directory-focused-03.log` passes six focused tests, covering external imports,
provider-introduced imports and embedded assets, changed/absent case and API
files, source edits/removals, added `.my` files, irrelevant output files, initial
snapshot conflicts, allocation refusal and selected/distinct provider maps.
`directory-fmt-03.log` and `directory-guardian-03.log` are green; the latter runs
all 88 Guardian checks. Earlier failed Guardian receipts remain retained.

Frozen ready-for-build hashes are directory
`ab9ce59d1baec75591bb595cb02ccf18f54fde09598a6d113843de68d2d39f71`
and cases `09f9767115dc66cf2a3e62b1c33136dd3f67e4a27bfb62e3df5cfa58faf5d524`.
The coordinator owns receipt/main wiring, final package checks and commit.
