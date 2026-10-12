# Environment identity

Every cached verdict in this repository depends on some environment variables
and must ignore the rest. A guest test receipt, a build-graph test verdict and a
verification coordinator action all ask the same question: which variables can
change an outcome, and which ones does a child process need? One file answers it
for all of them, `src/environment_identity.zon` (ENV-IDENTITY-1). Nothing else
lists environment variables for an identity.

- The compiler imports it at compile time through `src/environment_identity.zig`
  (no allocation, no I/O). The guest test receipts use it today: a receipt keys
  exactly the keyed class, never the host class (NEW-CORE-S4-TEST-5).
- `scripts/verification_environment.py` reads the same file with a strict
  parser and offers the same classification, projection and digest to Python
  drivers and the verification coordinator.
- The golden fixture under `test/fixtures/environment-identity/` (206 variables,
  five tools, the expected class of every variable and the expected guest and
  host digests) is
  checked by both `src/environment_identity_test.zig` and
  `scripts/verification_environment_test.py`, so the two implementations cannot
  drift apart (ENV-IDENTITY-2).

## The four classes

| Class | Children receive it | Enters identities | What belongs here |
| --- | --- | --- | --- |
| **keyed** | yes | `NAME=VALUE`, guest and host | anything that can change what the compiler, a runtime or a guest test does |
| **host** | yes | `NAME=VALUE`, host only | what changes host tooling (Python drivers, host tools) but never a guest build or test: `PYTHON*`, `LANG`, `LANGUAGE`, `LC_*`, `TZ` |
| **placement** | yes | never | where content-addressed storage, scratch or diagnostics live; how many jobs run; which process runs a test |
| **dropped** | no | never | everything else: shell, terminal, session, agent and credential variables |

Guest test receipts key only the **keyed** class. Host tooling (the build
graph's verdict manifest, Python drivers, the verification coordinator) keys
**keyed** plus **host**. The host class exists because the compiler is Zig and
the guest runtime formats numbers and text itself, so locale, time zone and
Python settings cannot change a guest outcome, yet they differ between
contexts: the coordinator sets `PYTHONNOUSERSITE`, `PYTHONDONTWRITEBYTECODE`
and `PYTHONPYCACHEPREFIX` for its workers and a developer's shell does not.
Keying them in guest receipts would stop the gate's receipts and hand-made ones
from matching.

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

`environment_identity.digest(scope, variables, tools)` (Zig) and
`verification_environment.digest(env, tools, scope="guest")` (Python) compute
the same lowercase hex SHA-256 (ENV-IDENTITY-2). The scope chooses the
variables: `guest` takes the keyed class (what a guest test receipt keys),
`host` takes the keyed and host classes (what host tooling keys). Every field
is a u64 little-endian length followed by the bytes, the form the receipt module
already uses:

1. `field("environment-identity-v1")`;
2. for every variable present that the scope takes, in bytewise order of name:
   `field(NAME)`, `field(VALUE)`;
3. for every tool in the caller's list, in bytewise order of name:
   `field("tool:" ++ NAME)`, `field(lowercase hex SHA-256 of the tool)`.

Placement and dropped variables and the order of the inputs never change
either digest; host variables change only the host digest. An empty value is
still present and therefore keyed. The Zig function
sorts the caller's two slices in place and allocates nothing, so a host tool can
collect an environment map and a tool list into its own buffers and digest them.

## Run what you key

The same definition must both key an environment and project the environment a
step actually runs in: if a variable is not keyed, the process must not see it
(unless it is placement, or host for a guest), or a dropped variable could
change a verdict that a cache then replays. `verification_environment.project(env)`
keeps the keyed, host and placement variables and removes the dropped ones. The compiler already follows
the rule for receipts: a guest test reads no environment, and a non-empty
`LD_*` variable still refuses every receipt. The build graph follows it through
`build-env` and the verification coordinator follows it too (both below), as the
[output-keyed verification plan](../audits/output-keyed-shared-receipts-plan-2026-10-12.md)
lays out.

## In the build graph

`zig build` keys a cached test verdict on its command, its artifacts, its
declared input files and one environment manifest, and it runs every test
command in the environment that manifest describes. One host tool does both:
`build-env`, built from `build_env.zig` for the build host (its pure half,
`src/build_env_rules.zig`, is tested from the unit root).

- **The manifest** (ENV-PROJECTION-2). On every build that runs a cached test
  step, `build-env digest OUT TOOL...` writes `environment.txt`. Its first line
  is the host-scope digest, `environment_identity.digest(.host, …)`, of the live
  environment and the named tools; the following lines explain it: every keyed
  and host `NAME=VALUE` in name order (a backslash and a line feed escaped as
  `\\` and `\n`), then `tool:NAME=SHA256` per tool. Placement and dropped
  variables never appear. Every cached step declares the file as an input, so a
  changed manifest re-runs the cached verdicts and an unchanged one keeps them.
- **The keyed tools.** A `TOOL` argument is `NAME=PATH` or a bare `NAME`
  resolved on the live `PATH` when the step runs, so the configure phase never
  bakes a tool location. The build names its configured Zig by path (`zig=…`)
  and `sh`, `env`, `python3` and `git` by name. A tool that cannot be found or
  read is recorded as `absent`. The tool is compiled ReleaseSafe: hashing the
  184 MB Zig binary takes about 0.17 s on every build, against about 1 s in Debug.
- **The projection** (ENV-PROJECTION-1). `withTools` in `build.zig` wraps every
  test root, shard and driver as
  `sh -c SCRIPT with-tools BUILD-ENV NAME=VALUE... CMD...`; the script exports
  the Zig cache variables and then runs
  `exec BUILD-ENV project -- env NAME=VALUE... CMD...`. `build-env project`
  keeps the keyed, host and placement variables (`passedThrough`), drops the
  rest and replaces itself with the command, which keeps the wrapper's pid,
  exit status and resource accounting. It exits with status 2 and one line on
  standard error when the command cannot be executed. Variables the build
  itself sets (`MYLANG_ZIG`, `MYLANG_COMPONENT_DIR`, `MYLANG_UNIT_SHARDS`,
  `MYLANG_TEST_COMPILER`, ...) follow the projection through `env`.
- **`MYLANG_TEST_COMPILER`** (TEST-PATHS-1). The unit, core, CLI and golden
  test binaries do not embed the compiler's path or any absolute path of the
  tree. The wrapper sets the placement variable `MYLANG_TEST_COMPILER` (and
  `MYLANG_TEST_COMPONENT_BUILDER` for the CLI root) to the artifact's absolute
  path; the step keys the artifact by content, not by path, so a changed
  compiler re-runs the step without rebuilding the test binary. Fixture paths
  (`test/core`, `tests/lang`, `benchmarks/runtime/ports/native_clock.c`) are
  relative to the build root, which every test step uses as its working
  directory. `src/core/test_paths.zig` holds both and is imported as
  `core_test_options` by the core root and `test_paths` by the others.

```console
$ CODEX_THREAD_ID=x MYLANG_MEMORY_LIMIT=1G zig build run -- run probe.my
None Some('1G') None Some('/…/.tmp/work')
```

A program that prints `env.get` of `CODEX_THREAD_ID`, `MYLANG_MEMORY_LIMIT`,
`TERM` and `TMPDIR` shows a dropped variable absent, a keyed one present and a
placement one present. The manifest is byte-identical with and without
`CODEX_THREAD_ID`, and `MYLANG_MEMORY_LIMIT=1G` changes its first line and adds
its line.

## In the coordinator

`scripts/verify_cache.py` is host tooling, so it keys the `host` scope.
`normalized_environment` projects the launcher environment with
`verification_environment.project` and then applies the coordinator's constants
(the `PYTHON*` pins, the fixed `GIT_*` isolation and identity, `PATH` limited to
existing directories); workers run in exactly that environment. The `environment`
field of every action key is `verification_environment.digest(env, tools,
scope="host")`, where `tools` maps each tool the coordinator resolves to the
content digest its tools snapshot already computed. `PWD` is dropped, not pinned,
and the checkout path is in no key. Each action in `last-run.json` lists the
names of the variables in its identity (`environment_variables`). See
[receipt identities](development-loop.md#receipt-identities-schema-3).

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
| `MYLANG_VERIFICATION_SHARED_CACHE` | placement | location of the verification coordinator's shared evidence store, whose receipts are content-keyed |
| `MYLANG_COMPONENT_DIR` | placement | per-worktree directory of component artifacts, which are identified separately |
| `MYLANG_JOBS`, `MYLANG_UNIT_JOBS`, `MYLANG_UNIT_SHARDS` | placement | job counts |
| `MYLANG_TEST_ISOLATE`, `MYLANG_TEST_CHILDREN` | placement | which process runs a test (oracles of the batch runner) |
| `MYLANG_TEST_COMPILER` | placement | reserved: the compiler a test binary runs, supplied at run time by the build graph |
| `MYLANG_SLOT_DIR`, `MYLANG_ADMISSION_*`, `MYLANG_BUILD_SLOTS`, `MYLANG_BUILD_MEM`, `MYLANG_GATE_SLOTS`, `MYLANG_GATE_MEM`, `MYLANG_TIMING_MEM`, `MYLANG_TIMING_CPUS`, `MYLANG_SLOT_SETTLE`, `MYLANG_SLOT_POLL` | placement | build-slot admission settings |
| `MYLANG_DEV_JOBS`, `MYLANG_DEV_MAXRSS` | placement | developer job sizing from the environment script |
| `MYLANG_TEST_TELEMETRY_DIR`, `SELKA_VERIFICATION_TELEMETRY_DIR` | placement | per-request diagnostic directories |
| `MYLANG_FRICTION_LOG` | placement | the friction log is append-only and a write failure never changes an exit status |
| `MYLANG_S1_WORKDIR` | placement | scratch directory of a profiling script |

Besides these, the keyed class holds `SOURCE_DATE_EPOCH`, `ZERO_AR_DATE`,
`LD_*` and the C compiler
and Zig toolchain variables (`CCC_OVERRIDE_OPTIONS`, `COMPILER_PATH`, `CPATH`,
`C_INCLUDE_PATH`, `CPLUS_INCLUDE_PATH`, `GCC_EXEC_PREFIX`, `LIBRARY_PATH`,
`OBJC_INCLUDE_PATH`, `ZIG`, `ZIG_LIB_DIR`, `ZIG_LIBC`). Placement also holds
`HOME`, `XDG_CACHE_HOME`, `XDG_RUNTIME_DIR`, `TMPDIR`, `PATH`,
`ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR`. The host class is `PYTHON*`,
`LANG`, `LANGUAGE`, `LC_*` and `TZ`.

Compared with the receipt code before the contract, receipts now also key
`SELKA_*`, `ZERO_AR_DATE` and empty `LD_*` variables, and no longer key the
placement variables above, including both telemetry directories. They still
ignore the locale, `TZ` and `PYTHON*`, which are host.

## Adding a variable

1. Decide the class with the questions above: can the value change what any
   compiler, runtime or guest test does (keyed), only what a host tool or
   Python driver does (host), or only where things are stored, how many run at
   once or which process runs them (placement)? When in doubt, keyed: a
   needless key costs a cache miss, a missing one a stale verdict.
2. Add one line to `src/environment_identity.zon` in that class, as an exact
   name unless a whole family shares the class.
3. Add the variable to the golden fixture: a `NAME=VALUE` line in
   `environment.txt` and a `NAME CLASS` line in `classification.txt`, then
   regenerate `digest-guest.txt` and `digest-host.txt` from the Python module
   and confirm the Zig test reproduces them:

```console
$ python3 -B -c 'import sys; sys.path.insert(0, "scripts"); import verification_environment as e; d = "test/fixtures/environment-identity/"; env = dict(l.split("=", 1) for l in open(d + "environment.txt").read().splitlines()); tools = dict(l.split(" ", 1) for l in open(d + "tools.txt").read().splitlines()); [open(d + "digest-" + s + ".txt", "w").write(e.digest(env, tools, s) + "\n") for s in e.SCOPES]'
$ python3 -B scripts/verification_environment_test.py -v
$ scripts/build-slot.sh build zig build test-units -Dtest-filter='environment identity'
```

4. Add a row to the audit table above for a `MYL_`, `MYLANG_` or `SELKA_`
   variable, with its reason.
