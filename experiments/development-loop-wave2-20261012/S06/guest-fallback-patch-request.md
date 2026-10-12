# Joint native driver cleanup repair

Read-only source B0 `c1857310e0bf623545380c8de24515f1b9970021`.
S10's actual frozen C1 Debug compiler reports two failed guest tests, both with
`ToolFailed`/`native-link-*/<digest>.o: FileNotFound`, and cache reason
`uncacheable-toolchain`. Exact raw JSON is retained in
`guest-fallback-reproducer/s10-debug-failure.json`; original source/argv/provenance
is S10/raw/guest-qualification-failed/manifest.json.

Current `/etc/ld.so.cache` SHA-256 is
`d519185506fec90f5efbdc206f606f4c259891e83c4e98e48b9fa4694b64fbe6`, modified
2026-10-12 01:37:15 UTC. Reviewed `config_core_tool_platform.zig` expects
`fe063c1bee92cacf27776b62c04e35a2c71e7ed111ec3eaa542ba339410fcde3`.
The other five loader/libc/libm/libgcc/libpthread hashes and pinned Zig still
match their reviewed values. This mismatch is sufficient to reject reuse;
no tool-approval pin refresh or weaker qualification is requested.

In `src/core/driver.zig` `unitObjects`, unconditional pending-object cleanup runs
when that helper returns. Cacheable publication renames those partial objects,
so removing the old partial path is harmless. Uncacheable publication uses
`unit_cache.found(item.object)` without a rename; cleanup then removes the exact
object subsequently passed to `linkNative`'s linker command. Outer `linkNative`
already removes its entire private staging directory on success or error.

Minimal proposed caller-preserving repair:

```zig
// Published cache partials moved away; private objects must survive the link.
defer if (places.cacheable) for (pending.items) |item| removeFile(native.io, item.object);
```

Coordinator/driver owner must apply and qualify this shared production change.
Require a real nonempty LLVM unit through an unproved delegated pinned-Zig tool,
actual link/execution, no successful native or test reuse, and staging cleanup
on success and compile/link failure. Existing unproved-driver tests use an empty
unit inventory/fake linker which does not consume objects, so they do not cover
this object lifetime. Keep full guard checks, isolation and source/tool identity.
Root-owned SPEC/test wiring/full compiler and final gate remain necessary.
