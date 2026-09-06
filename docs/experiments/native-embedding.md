# Native embedding entry API

Generated C supports a versioned C host entry, `mylang_native_run_v1`, under
`MYLANG_EMBED`. The native builder can publish a shared library:

```sh
python3 scripts/native.py examples/sum.my --library -o /tmp/libsum.so
```

Add `--project` for a module entry. The builder uses the pinned Zig 0.17 development
toolchain, retains atomic publication and unchanged-output preservation, and
reports `artifact_kind: shared-library` with `--report`. Executable builds still
use their existing CLI. Libraries receive providers at invocation time; combining
`--library` and the executable-only `--provider` option is rejected.

A host includes the public headers in this order:

```c
#include "native_providers.h"
#include "native_embed.h"

int main(void) {
    MylangRunResult result;
    MylangRunOptions options = { .max_steps = 100000 };
    int status = mylang_native_run_v1(&options, &result);
    if (status != 0) return status;
    return result.value == 4950 ? 0 : 1;
}
```

Compile the host with the repository's `src` include directory and link against
the generated library. Deploy that library where the host's dynamic loader can
find it. The example's expected value must match the selected guest program.

Status 0 returns the guest entry's i64 value. Status 1 returns a guest trap code,
source location and up to 16 frames, with an omitted-frame count. Status 2 returns
a host failure code such as `OutOfMemory`, `InvalidCapability`,
`CapabilityUnavailable` or `Busy`. The result pointer is mandatory; a null pointer
returns status 2 without a result. Diagnostic strings borrow library storage and
remain valid until the library unloads. Options, provider storage and the result
must not alias. Each caller must own its result storage.

Null options select default budgets and no external providers. Zero budget fields
select 10,000,000 instructions and 1024 frames. An explicit provider table grants
clock/random/environment/filesystem/network operations under provider ABI v4;
callbacks and their contexts must remain valid for the invocation and callbacks
must return normally. Callbacks must follow the existing resource ownership rules.

Every completed invocation releases guest storage, including trap and allocation
failure paths. The next invocation resets guest state and budgets. One generated
program is supported per linked library. Concurrent or callback-reentrant calls
to that program return `Busy`; they do not execute guest code or disturb the
active invocation. The host chooses its own printing and error policy.

The entry API invokes the source `main` with capability entry parameters and returns
its scalar result. [Exported scalar calls](native-calls.md) now have a separate versioned API.
[Ordinary aggregate arguments/results](native-wire.md) also have a bounded wire
API. Domain codecs, generated native callable bindings, and parallel per-call
runtime contexts remain unfinished. This is a foundation for those roadmap requirements.

## Acceptance

`tests/native_embedding.py`, wired into `zig build test`, compiles 12 fixtures in
both -O0 and -O2 with undefined-behavior sanitization. It checks repeated execution,
bounded trap frames, budget exhaustion, explicit provider validation, reentry and
concurrent Busy rejection, allocation-failure sweeps and subsequent recovery.
Fixtures cover generics, returned references, arenas, pools, buffers and resource
ownership, including a division trap with an acquired resource still live. Separate C hosts use only the public headers to link and run shared
libraries in Debug and ReleaseFast; rebuilding identical inputs preserves output
identity. All of these focused checks passed. Full regression results are recorded
in the roadmap's milestone entry when validation completes.
