# Refreshed retirement preview — not applied

This preview reads validation base `3c5d19c74b5e323306d76bcc0fed18f90290d1af`
plus the qualified five-file nested-extension feature. It preserves
`myl_core_owned_same_block` once when selecting the existing owned runtime.
`git apply --check` passes against those exact runtime inputs. Production files
are unchanged by generation; `manifest.json` pins before/after source hashes.

The older preview and native results remain untouched in the parent directory.
This refresh has a textual apply check only; its native runtime combination is
not separately qualified. The parent README's A05/A07/A09/A10 dependencies,
capacity-test migration and C2 approval requirement still apply. Neither this
patch nor a prepared checklist constitutes legacy RC retirement.
