# Environment identity

Every cached verdict in this repository depends on some environment variables
and must ignore the rest. A guest test receipt, a build-graph test verdict and a
verification coordinator action all ask the same question: which variables can
change an outcome, and which ones does a child process need? One file answers it
for all of them, `src/environment_identity.zon` (ENV-IDENTITY-1). Nothing else lists environment variables for an identity.

- The compiler imports it at compile time through `src/environment_identity.zig`
  (no allocation, no I/O). The guest test receipts use it today: a receipt keys
  exactly the keyed class (NEW-CORE-S4-TEST-5).
- `scripts/verification_environment.py` reads the same file with a strict
  parser and offers the same classification, projection and digest to Python
  drivers and the verification coordinator.
- The golden fixture under `test/fixtures/environment-identity/` (205 variables,
  five tools, the expected class of every variable and the expected digest) is
  checked by both `src/environment_identity_test.zig` and
  `scripts/verification_environment_test.py`, so the two implementations cannot
  drift apart (ENV-IDENTITY-2).

## The three classes

| Class | Children receive it | Enters identities | What belongs here |
| --- | --- | --- | --- |
| **keyed** | yes | `NAME=VALUE` | anything that can change what the compiler, a runtime or a test does |
| **placement** | yes | never | where content-addressed storage, scratch or diagnostics live; how many jobs run; which process runs a test |
| **dropped** | no | never | everything else: shell, terminal, session, agent and credential variables |

A placement variable must be unable to change an outcome. A cache directory
qualifies because every store under it is content-addressed; a job count
qualifies because results are independent of parallelism; a telemetry directory
qualifies because nothing reads it back to decide a verdict. On 12 October 2026 a
per-request telemetry directory in a keyed variable invalidated every guest
receipt (`experiments/telemetry-cache-invalidation-20261012/REPORT.md`); both
telemetry variables are now placement, and a test pins it.

`PATH` is placement: the tools it resolves are identified by their content,
through the tool list of the digest below, not by the search path string.

## Precedence

An entry is an exact name (`MYLANG_JOBS`) or a prefix ending in `*`
(`MYLANG_*`). To classify a name:

1. an exact entry wins, whatever its class;
2. otherwise the longest matching prefix wins (`MYLANG_ADMISSION_*` beats
   `MYLANG_*`);
3. otherwise the variable is dropped.

So `MYLANG_JOBS` is placement although `MYLANG_*` is keyed, `MYLANG_JOBSX` is
keyed, and `ZIG_VERBOSE_LINK` is dropped although `ZIG` is keyed. Each spelling
may appear only once in the file; the Zig build fails on an empty entry, a `*`
that does not end an entry, or a duplicate, and the Python reader raises
`ContractError` for the same mistakes.

```console
$ python3 -c 'import sys; sys.path.insert(0, "scripts"); import verification_environment as e; print(e.classify("MYLANG_JOBS"), e.classify("MYLANG_MEMORY_LIMIT"), e.classify("CODEX_THREAD_ID"))'
placement keyed dropped
```

## The environment digest

`environment_identity.digest` (Zig) and `verification_environment.digest`
(Python) compute the same lowercase hex SHA-256 (ENV-IDENTITY-2). Every field
is a u64 little-endian length followed by the bytes, the form the receipt module
already uses:

1. `field("environment-identity-v1")`;
2. for every **keyed** variable present, in bytewise order of name:
   `field(NAME)`, `field(VALUE)`;
3. for every tool in the caller's list, in bytewise order of name:
   `field("tool:" ++ NAME)`, `field(lowercase hex SHA-256 of the tool)`.

Placement and dropped variables and the order of the inputs never change the
digest. An empty value is still present and therefore keyed. The Zig function
sorts the caller's two slices in place and allocates nothing, so a host tool can
collect an environment map and a tool list into its own buffers and digest them.

## Run what you key

The same definition must both key an environment and project the environment a
step actually runs in: if a variable is not keyed, the process must not see it
(unless it is placement), or a dropped variable could change a verdict that a
cache then replays. `verification_environment.project(env)` keeps the keyed and
placement variables and removes the dropped ones. The compiler already follows
the rule for receipts: a guest test reads no environment, and a non-empty
`LD_*` variable still refuses every receipt. The build graph (`build.zig`) and
the verification coordinator adopt the projection in later lanes of the
[output-keyed verification plan](../audits/output-keyed-shared-receipts-plan-2026-10-12.md);
until then their own environment digests are unchanged.

## Audit of `MYL_`, `MYLANG_` and `SELKA_` variables

Every `MYL_`, `MYLANG_` and `SELKA_` variable read or set in `src/`, `build.zig`,
`scripts/` or the developer environment script was classified deliberately on
12 October 2026. Names not listed fall under the keyed prefixes, which is the
conservative default for a new variable. (`MYL_*` names such as `MYL_HEADER` that
appear only as C macros are not environment variables.)

| Variable | Class | Reason |
| --- | --- | --- |
| `MYL_CORE_LEAKCHECK` | keyed | turns on the runtime leak check |
| `MYL_CORE_TEXTWALK` | keyed | makes the runtime report text walks |
| `MYL_CORE_PARENT_TOOL_TICKET` | placement | lets a child borrow its parent's tool identity; which process captures it changes no result |
| `MYL_BATCH_PROBE_*` | keyed | test-only probes that change a batch runner's behaviour |
| `MYLANG_OPTIONS` | keyed | runtime options of a built program |
| `MYLANG_MEMORY_LIMIT`, `MYLANG_HOST_MEMORY_LIMIT`, `MYLANG_SEMANTIC_BUDGET` | keyed | byte ceilings that decide whether a run or a compile fails |
| `MYLANG_HOST_LIMIT_CHECKPOINT`, `MYLANG_HOST_LIMIT_RESTORE` | keyed | carry the compiler's ceilings to its children |
| `MYLANG_ZIG` | keyed | the pinned toolchain path, keyed by receipts today |
| `MYLANG_CORE_LAYOUT`, `MYLANG_CORE_SANITIZE` | keyed | change emitted code |
| `MYLANG_CACHE_PLAN_MODE`, `MYLANG_TEST_INDEX_MODE`, `MYLANG_TEST_KEYS` | keyed | choose compiler code paths and their oracles |
| `MYLANG_STAGE_CACHE_COMPRESSION` | keyed | an invalid value fails the compile |
| `MYLANG_THREADS` | keyed | sizes the guest runtime's task threads, which a test can observe |
| `MYLANG_COUNTERS` | keyed | the program under test writes its counters there |
| `MYLANG_PORTABLE_PROBE`, `MYLANG_TEST_SECRET`, `MYLANG_P1_FIXTURE_OUTPUT`, `MYLANG_ZERO_RC_TASK_OUTPUT` | keyed | test-only inputs and outputs of Zig tests |
| `MYLANG_GDB_COMMANDS`, `MYLANG_GDB_REPORT` | keyed | local to `scripts/qualify_debugger.py`; never in a gate environment |
| `MYLANG_RUNTIME`, `MYLANG_RC_SITES` | keyed | retired switches the compiler refuses |
| `SELKA_*` (other than below) | keyed | reserved for the verification tools |
| `MYLANG_CORE_RUNTIME_CACHE`, `MYLANG_COMPILER_SHARED_CACHE`, `MYLANG_TEST_SHARED_CACHE`, `MYLANG_FRONTEND_CACHE` | placement | locations of content-addressed stores |
| `MYLANG_COMPONENT_DIR` | placement | per-worktree directory of component artifacts, which are identified separately |
| `MYLANG_JOBS`, `MYLANG_UNIT_JOBS`, `MYLANG_UNIT_SHARDS` | placement | job counts |
| `MYLANG_TEST_ISOLATE`, `MYLANG_TEST_CHILDREN` | placement | which process runs a test (oracles of the batch runner) |
| `MYLANG_TEST_COMPILER` | placement | reserved: the compiler a test binary runs, supplied at run time by the build graph |
| `MYLANG_SLOT_DIR`, `MYLANG_ADMISSION_*`, `MYLANG_BUILD_SLOTS`, `MYLANG_BUILD_MEM`, `MYLANG_GATE_SLOTS`, `MYLANG_GATE_MEM`, `MYLANG_TIMING_MEM`, `MYLANG_TIMING_CPUS`, `MYLANG_SLOT_SETTLE`, `MYLANG_SLOT_POLL` | placement | build-slot admission settings |
| `MYLANG_DEV_JOBS`, `MYLANG_DEV_MAXRSS` | placement | developer job sizing from the environment script |
| `MYLANG_TEST_TELEMETRY_DIR`, `SELKA_VERIFICATION_TELEMETRY_DIR` | placement | per-request diagnostic directories |
| `MYLANG_FRICTION_LOG` | placement | the friction log is append-only and a write failure never changes an exit status |
| `MYLANG_S1_WORKDIR` | placement | scratch directory of a profiling script |

Besides these, the keyed class holds the locale (`LANG`, `LANGUAGE`, `LC_*`),
`TZ`, `SOURCE_DATE_EPOCH`, `ZERO_AR_DATE`, `PYTHON*`, `LD_*` and the C compiler
and Zig toolchain variables (`CCC_OVERRIDE_OPTIONS`, `COMPILER_PATH`, `CPATH`,
`C_INCLUDE_PATH`, `CPLUS_INCLUDE_PATH`, `GCC_EXEC_PREFIX`, `LIBRARY_PATH`,
`OBJC_INCLUDE_PATH`, `ZIG`, `ZIG_LIB_DIR`, `ZIG_LIBC`). Placement also holds
`HOME`, `XDG_CACHE_HOME`, `XDG_RUNTIME_DIR`, `TMPDIR`, `PATH`,
`ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR`.

Compared with the receipt code before the contract, receipts now also key
`SELKA_*`, the locale, `TZ`, `ZERO_AR_DATE`, `PYTHON*` and empty `LD_*`
variables, and no longer key the placement variables above, including both
telemetry directories.

## Adding a variable

1. Decide the class with the questions above: can the value change what any
   compiler, runtime, driver or test does (keyed), or only where things are
   stored, how many run at once or which process runs them (placement)? When in
   doubt, keyed: a needless key costs a cache miss, a missing one a stale verdict.
2. Add one line to `src/environment_identity.zon` in that class, as an exact
   name unless a whole family shares the class.
3. Add the variable to the golden fixture: a `NAME=VALUE` line in
   `environment.txt` and a `NAME CLASS` line in `classification.txt`, then
   regenerate `digest.txt` from the Python module and confirm the Zig test
   reproduces it:

```console
$ python3 -B -c 'import sys; sys.path.insert(0, "scripts"); import verification_environment as e; d = "test/fixtures/environment-identity/"; env = dict(l.split("=", 1) for l in open(d + "environment.txt").read().splitlines()); tools = dict(l.split(" ", 1) for l in open(d + "tools.txt").read().splitlines()); open(d + "digest.txt", "w").write(e.digest(env, tools) + "\n")'
$ python3 -B scripts/verification_environment_test.py -v
$ scripts/build-slot.sh build zig build test-units -Dtest-filter='environment identity'
```

4. Add a row to the audit table above for a `MYL_`, `MYLANG_` or `SELKA_`
   variable, with its reason.
