# S3-C hold: opaque Environment callback context treated as an allowlist

S3-C is held under the S3 implementation plan §2. No behavior decision or compatibility port has been made. This is an evidence checkpoint, not the S3-C exit report.

## Deterministic result

`context-probe.my` prints `len(env.names())`. `context-provider.c` implements the public native-provider ABI 7, supplies an Environment getter which always reports absent, and supplies an arbitrary static callback context containing `CUSTOM`. The context is unrelated to names or grant metadata. Both compilers successfully built the identical sources. The provider performs no host reads, and the getter is not called by this program.

Each executable ran with exactly these process variables and no `MYLANG_OPTIONS`:

```text
PATH=/usr/bin:/bin
ONLY_VISIBLE=ok
MYL_CORE_LEAKCHECK=1
```

| Compiler | Exit status | stdout | stderr |
| --- | --- | --- | --- |
| Qualified D2 old compiler | 0 | `1\n` | empty |
| Current Core | 0 | `3\n` | empty |

The separate command/result logs are `context-old-run-01.log` and `context-core-run-01.log`; they include the full argv, cwd, environment, binary SHA256, status, stdout and stderr. Separate empty build-output logs are retained as `context-old-build-01.log` and `context-core-build-01.log`. No log was reused.

Source checkpoint: `8e52a2129546b5cc46fa3b407c99186b5d8eb1b5`.

Qualified D2 old compiler SHA256: `feb7914ba50d0649180a5257b11f1a821930b40afd18b4f48f0d503127a80073`.
Its QBE SHA256: `bc4c25a0fd02f0e30cc5d9ec20dd5c4850af704c02400d5ddf6095de63f51299`.
Installed Core compiler SHA256 after the uncontended rebuild: `16dd7a43e13c1f72de9a3a225edae052f88fe88f7132b3dbedf15c6738ab1482`.
The generated executable hashes are in the run logs.

## Primary ABI and source evidence

- [Public provider ABI](/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-capabilities/src/native_providers.h:8) identifies ABI 7. Lines 10–12 require contexts to outlive the run and forbid callback reentry. Lines 50–51 define `void *environment_context` beside the Environment callback which receives that context. There is no name enumeration callback or C-string allowlist requirement for this pointer.
- [Old names implementation](/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-capabilities/src/qbe_providers.c:197) documents the ordinary allowlist/process-environment names algorithm, then casts `p->environment_context` to a C string. Lines 216–223 split that context on commas and publish it as names. Consequently `CUSTOM` becomes the one visible name even though it is only adapter state and is absent from the controlled process environment. Non-string adapter state can also be read as a C string; this probe deliberately uses valid readable storage to avoid undefined behavior in the evidence.
- [ENVIRONMENT-NAMES-1](/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-capabilities/SPEC.md:339) describes fresh sorted visible environment names honoring the runtime allowlist and `env.only(...)` narrowing. `docs/audits/phase2-env-notes.md:58–61` specifies narrowed scope intersected with the allowlist, the allowlist itself, or process-environment names when no allowlist is set. `docs/io.md:298–309` describes provider access and process-environment grants.
- [Current Core names implementation](/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-capabilities/src/core/runtime/core_io.c:1176) presently reads explicit grant state for names rather than reinterpreting the callback context. This explains the Core result; it does not settle which Environment names a custom native provider should expose.
- [Plan §2 stop rule](/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-capabilities/docs/audits/new-core-s3-implementation-plan-2026-10-06.md:162) requires a package that finds an old-answer implementation accident to stop and report rather than decide.

The old implementation depends on undocumented interpretation of a native callback context. That is the confirmed implementation accident. A semantic decision is required for custom-provider name enumeration, grant filtering, and the matching old/Core behavior before this package can qualify.

## Reproduction

The exact reproduction commands below use fresh `02` log names; they have not been rerun after the hold. Invoke them from `/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-capabilities` only once the stop is resolved. Existing `01` build and run output is retained.

```bash
scripts/build-slot.sh build .mylang-cache/s3/d2-oracle/mylang build experiments/new-core-s3-20261006/wave-b/s3-c/context-probe.my -o .mylang-cache/s3/context-old --qbe .mylang-cache/s3/d2-oracle/qbe --cache-dir=.mylang-cache/s3/context-old-cache --provider experiments/new-core-s3-20261006/wave-b/s3-c/context-provider.c > experiments/new-core-s3-20261006/wave-b/s3-c/context-old-build-02.log 2>&1
scripts/build-slot.sh build zig-out/bin/mylang-core build experiments/new-core-s3-20261006/wave-b/s3-c/context-probe.my -o .mylang-cache/s3/context-core --cache-dir .mylang-cache/s3/context-core-cache --link experiments/new-core-s3-20261006/wave-b/s3-c/context-provider.c > experiments/new-core-s3-20261006/wave-b/s3-c/context-core-build-02.log 2>&1
```

The exact observed executable argv, cwd, three-variable environment and output are recorded in the `01` run logs. A shell reproduction of those executions is:

```bash
env -i PATH=/usr/bin:/bin ONLY_VISIBLE=ok MYL_CORE_LEAKCHECK=1 .mylang-cache/s3/context-old
env -i PATH=/usr/bin:/bin ONLY_VISIBLE=ok MYL_CORE_LEAKCHECK=1 .mylang-cache/s3/context-core
```

Capture each command's exit status, stdout and stderr to a fresh log. Both observed statuses are zero and both stderr values are empty; old stdout is `1\n`, Core stdout is `3\n`.

## Other evidence and remaining gates

The exclusive Core rebuild at this source took 3.02 seconds. Its gate-admission wait was 170 seconds, separately recorded; all three build slots were held and other-build wait was zero. See `core-exclusive-01.log` and `core-exclusive-01.time`. The frozen-IR diff against `dc1a5831` remains empty.

Earlier focused debug/release conformance passed 24 comparisons with zero mismatches and no unsupported cases, and an earlier default-eight-shard run passed 225 tests. These are development checkpoints. The latest combined source, runner integration, full conformance, strict fixture rerun, coverage and final S3-C exit gates remain owed. No package exit is claimed.
