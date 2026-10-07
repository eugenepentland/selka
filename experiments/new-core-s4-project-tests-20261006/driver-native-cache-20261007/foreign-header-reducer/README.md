# Current Core external-header regression

Immutable M focused compiler SHA256
`591886dc7d20409c878ee0a5b15c9faa0394b5b836eeaaa8c75e43a31350f120`
from source `0ebc9c8f0`; copied and verified before native actions. This is a
diagnostic artifact, not the final combined Wave A qualification.

The isolated app calls `linked_value`, supplied by `--link value.c`. That C
source includes `value.h`. Both actual Core builds returned 0 using the identical
command, output path, Core cache, private Zig global cache and flags. Original
`VALUE 7` produced guest exit 7. After changing the header to `VALUE 8`, preserving
its 16-byte size and restoring its original nanosecond modification time, Core
again returned 0 and the guest still exited 7. Its change time and content hash
changed. Expected edited guest exit: 8.

Both executable bytes have SHA256
`ca691032815c17741087feea1de74150bd291eeaf77c64fe1d1fbbf7b8579cfb`.
Both generated LLVM texts have SHA256
`4a663a0a90362a8e1d3f581740beacca8ab60135dd0baa89039bafe47eabe320`.
The second trace invokes `zig cc` and `ld.lld` successfully and links the same
cached `value.o`. `native-actions.json` retains the exact native argv;
`retained-object-manifest.json` identifies the retained C/program/runtime objects.
Raw build/native stdout and stderr are empty. Phase JSON files record statuses,
input generations and hashes; raw exec traces and actual LLVM texts remain.

Actual executables, object copies, compiler copy and Zig caches remain under the
task-owned `.mylang-cache/s4-frontend/c-prep-core-foreign-header-01`, outside the
reviewable evidence set. `reproduce.py` ran wholly inside one ordinary build slot.
No production source, system file or M Git state changed. No fix is part of this
receipt. The root agent was notified of this current Core RED before a proposed
repair.

Fresh-cache controls on the protected original compiler both passed: local-only
and local+global each produced build 0 / guest 8. The authorized M correction
then passed against the restored original stale local+global caches: build 0 /
guest 8, identical LLVM, stale value.o left unchanged, invocation-owned link
caches removed. Corrected compiler SHA256:
`d6e4220ad8a833f3d56510eb5958637e25f9c367071949db281d64584d3bface`.
The actual compiler and historical protected compiler are distinct explicit
fields in corrected-stale-cache.json. The executed diagnostic script bytes are
retained separately; the reusable script now writes those labels directly.
The native correction changes only final-action cache selection; closed runtime
and numeric object keys and all existing tool Guard validations remain.
