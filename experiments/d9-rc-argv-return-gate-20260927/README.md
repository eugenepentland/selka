# Joined correctness gate receipts

`identity.json` names the frozen source/compiler, final gate summaries and both
uncached sweep counts. The scripts are the exact drivers used under
`flock ../.d9-closeout-gate.lock` (full gate) and build-slot admission (both
drivers). Compressed files preserve original output and the complete guest JSON.

All four gates pass at `89e79524`, as do 871 actual RC assertions across 149
programs on each backend. No guest file is dropped. This does not replace the
failed `685e2631` archive or establish performance acceptance.
