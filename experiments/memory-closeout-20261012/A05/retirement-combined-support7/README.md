# Selector-free native retirement preview — not applied

A02's combined Support7 runtime candidate (`f7b7206b72`) and A05's complete
durable fixture pass with neither `MYL_ZERO_RC` selectors nor a compiler define.
The native harness refuses a candidate containing that selector. Source revision
`bed11cf3bf3102ffec44487e431a1573fdf02ad5`, every concatenated runtime input hash,
compiler/tool identity, command and all native output are in `native-result.json`.

Runtime SHA256 is `ca2ded335995f2d6f76c9900b172d74c20800cbe2885af4f3d39bf72a1eb7ca1`;
binary SHA256 is `0a63da3dbf33a00403e40a2805175d82160c99a4784dc5e57d1726e2b1a17e08`.
All short-write, bounds, fsync/publication, directory, SIGKILL, concurrent-writer
and lease-cleanup scenarios pass. Native exit is 0, stderr is empty under leak
checking, and retain/release/share symbols are absent. The dictionary layout
callbacks, provider-resource cleanup and OS locks remain.

This is new native scratch evidence, not relabelled earlier evidence. Production
compiler/runtime selectors remain until root applies the coordinated C3 changes;
the result does not qualify generated guest ownership, installed package contents
or final caches/gates. The full A05 public-library matrix is separate.
