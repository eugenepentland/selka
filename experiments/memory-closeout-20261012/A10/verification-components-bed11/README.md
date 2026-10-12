# C1 external component compiler inputs in verification

Prepared for coordinator review against frozen compiler source
`bed11cf3bf3102ffec44487e431a1573fdf02ad5`. Production files are coordinator-owned
and unchanged in A10. Apply `verification-component-inputs.patch` separately to
`scripts/verify_cache.py` and `scripts/verify_cache_test.py`; record the harness
revision independently from the frozen Support7 compiler and component receipts.
This is C1 explicit owned-package support, not default promotion or retirement.

The old full-gate parser rejects both existing build options. The patch admits
only `-Dcomponent-owned-compiler-pin=PATH` and `-Dcomponent-seed-source=PATH`;
empty, duplicate, NUL-containing or missing values refuse. Existing target,
prefix, cache-root and runner restrictions remain. Either option remains
independently meaningful to the builder; the actual closeout command supplies
both qualified inputs. No fallback or historical pin edit is introduced.

Before preparation, the existing `Snapshot` machinery watches and streams the
hashes of the external files, preserving logical paths and symlink traversal.
Their complete identities enter the common identity used by inventory,
preparation and action receipts, and appear in `last-run.json.component_sources`.
Watches remain active through queue admission, execution and receipt publication.
This invalidates same-path content changes and catches write/restore ABA even
with restored timestamps. The component builder retains responsibility for pin
schema, archive-digest validation and recipe qualification; this patch does not
replace those checks or impose future C3 marker requirements.

Seven added tests cover full-gate restrictions, all-phase option forwarding,
external relative paths, reported hashes, warm reuse, same-size/mtime edits,
missing/nonregular files, same-byte symlink retargeting and queued/running ABA.
All 73 coordinator tests passed in 28.241 seconds. Initial isolated full run
omitted an unchanged coverage fixture: 72 passed and one setup error occurred;
extracting that exact pinned fixture fixed its focused retry and full rerun.
Both logs are preserved. Exact base/proposed hashes and apply checks are in
`validation.json`. Tests use fake native drivers; no guest/compiler rebuild or
C1 gate completion is claimed here.

Run the real coordinator directly, never inside another admission wrapper:

```bash
source /home/epentland/.config/mylang/dev-env.sh
export MYLANG_COMPONENT_CACHE=/home/epentland/ai/canopy/mylang-memory-20261012-A10/.tmp/memory-closeout/A10/owned-pin-support6-5167c588/component-cache
python3 -B scripts/verify_cache.py --zig "$ZIG" -- \
  -Dcomponent-owned-compiler-pin=/home/epentland/ai/canopy/mylang-memory-20261012-A10/experiments/memory-closeout-20261012/A10/packaging-support6-candidate/candidate-pin.json \
  -Dcomponent-seed-source=/home/epentland/ai/canopy/mylang-memory-20261012-A10/.tmp/memory-closeout/A10/owned-pin-support6-5167c588/source.tar \
  -j4 --maxrss 8589934592
```

The existing parser and Zig command expect `--maxrss VALUE`, not the joined
`--maxrss8589934592` spelling. The pin selects qualified Support6 source
`5167c588be79dd43d21d5013c36db15110bf239b`; its archive SHA256 is
`0557a645579881d54d3f4c493c8b07be38d42b0a21622ab712b84589ee212c27`.
Support7 host/compiler qualification remains separately bound to its own
source, binary and installed component identities.
