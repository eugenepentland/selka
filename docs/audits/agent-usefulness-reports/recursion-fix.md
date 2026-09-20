# Runaway `native-test-graph` recursion — root cause and fix

Status: **fixed and verified** for the process recursion. One pre-existing
defect in the same new test was exposed by the fix and is **not** fixed; it is
recorded at the end with its reproduction.

## The failure

`mylang test` / `mylang invoke` runs grew a parent→child chain of copies of the
same binary (`native-test-graph → native-test-graph → …`), from 192 to 200
processes in ten seconds, until aggregate RSS passed 12 GiB and the machine OOM
killed processes.

## Root cause

Two facts compose into unbounded recursion. Neither is a bug on its own.

1. **A native session takes its compiler from `/proc/self/exe`.** In
   `src/native_test_session.zig`, `Session.initFrontend` resolved the compiler it
   spawns as *this process*:
   ```zig
   const compiler = try std.Io.Dir.cwd().realPathFileAlloc(context.io, "/proc/self/exe", context.allocator);
   ```
   That is correct for the CLI, where this process *is* `mylang`, and wrong for
   every other caller. The session then spawns it:
   `src/native_test_session.zig` `factsText` runs
   `{compiler} native-test-graph {source}`, and `build` runs
   `{compiler} build … --library …`.

2. **A Zig test binary is a test runner, not a compiler.** The runner parses
   `--guardian-filter=`, `--listen`, `--seed`, `--cache-dir` and ignores every
   other argument, so a test binary handed `native-test-graph <file>` runs its
   test suite instead of emitting facts. Reproduced on its own, safely:
   ```
   $ <cached test binary> native-test-graph tests/invoke/tool.my --cache-dir=…
   guardian/test: 11 test(s) selected
   All 11 tests passed.
   guardian/test: PASS — 11 passed
   ```

The trigger was new in this round: `src/invoke_test.zig`'s `builtLibrary` — used
by the `QBE-TEXT-4` test — is the only place that builds a native session
**inside the test process**. It passed `Options` with no compiler, so:

```
test binary → builtLibrary → Session.initFrontend → compiler = /proc/self/exe = the test binary
            → spawn "<test binary> native-test-graph tests/invoke/tool.my"
            → that child runs the suite → reaches QBE-TEXT-4 → builtLibrary → …
```

Every generation created a session temporary under `/tmp/.pending` and never
removed it, because the recursion was only stopped by killing the processes.

## The fix

`src/native_test_options.zig` — the compiler is now a named input rather than an
assumption. `Options.toolchain` groups the executables a session drives
(`qbe`, `zig`, `compiler`), with `compiler: ?[]const u8 = null` documented as
"null means this process, and a session must not assume it". Grouping also takes
`Options` from 14 fields to 12, back **under** the frozen type-size ratchet of 13
rather than over it.

`src/native_test_session.zig` — `resolveCompiler` honours a named compiler
verbatim and only falls back to `/proc/self/exe` when the caller named none.
`decideSelfCompiler` is the separate, testable decision at the ceiling.

`src/invoke_test.zig` — `builtLibrary` names `resolved.compiler`, the installed
`mylang`, with a comment saying why leaving it null is a recursion.

### The containment, in case a future caller still gets it wrong

`resolveCompiler` counts how many **ancestors of this process run the same
executable** and refuses with `error.CompilerRecursion` at
`ancestry_limit = 5`, before any child exists. Legitimate nesting is shallow and
known — `mylang test <dir>` spawns `mylang test <file>`, which spawns
`mylang native-test-graph` and `mylang build` — so the ceiling is well clear of
real use.

The parent chain is read from `/proc/<pid>/status`, not from an inherited
variable, for two reasons: the session fingerprints its **whole environment** to
key cached results (`native_test_environment.zig` `capture` hashes every pair), so
a counter threaded through the environment would invalidate every warm pass; and
a counter a child is handed can be reset by whatever hands it over. `status` is
read in preference to `stat` because its fields are line-oriented and its command
name is never parenthesised. An unreadable `/proc` entry ends the walk, which can
only **undercount** and therefore never refuses a legitimate session.

## Verification

| Check | Command | Result |
| --- | --- | --- |
| Reproduction is safe | `.tmp/repro-recursion.sh` (own session, 0.2 s watchdog, `RLIMIT_AS`, hard `timeout`) | watchdogs tripped before growth; no run left the sandbox |
| The test binary is a runner | `<cached test binary> native-test-graph tests/invoke/tool.my` | ran the suite and printed `PASS — 11 passed` |
| Ceiling refuses | `python3 scripts/focused_test.py units "another copy of this program"` | **PASS 12/0** — `decideSelfCompiler` returns `CompilerRecursion` at the limit and the executable one below it |
| No recursion under the suite | `python3 scripts/focused_test.py units invoke` under a process watchdog matching **any** cached test binary | **peak live copies: 1** |
| Native tests | `./zigw build test-native-tests` | **140 passed, 0 failed** |
| Gate | `./zigw build` | **88 Guardian checks passed** |
| Normal native test path | `mylang test tests/native/aggref_arguments.my --cases …` | **7 passed** |
| Normal invoke path | `mylang invoke tests/invoke/tool.my --function tool::bracket --input=…` | `completed`, `[aé😀é]` |

`test-native-tests` initially failed at `qbe_build_embed.zig`'s inline manifest,
which carried no `by_address` — the compatibility hardening from the same round
refusing a stale manifest, which is what it is for. The fixture now spells the
fact.

## Two defects the fix exposed, and their state

### Fixed: `myl_qbe_heap` was called without a declaration

`src/qbe_codecs_runtime.c` used `myl_qbe_heap` but its only include was
`native_text.h` → `native_collections.h` → `native_heap.h`, none of which declare
it, and `qbe_runtime.h` was never included. The call was therefore an implicit
`int` and the returned heap **address was truncated to 32 bits**. `qbe_bytes.c`
includes `qbe_runtime.h` through `qbe_bytes.h` for exactly this reason. The
include was added; this is a real latent bug in the text path independent of the
recursion.

### Not fixed: `OutputTooSmall` on a `str` result faults

`invoke_test.test.an undersized codec result buffer reports OutputTooSmall, not
WireLimit` still terminates with **SIGSEGV at address 0x4** inside
`mylang_native_call_codecs_v1`, on the first call with a 4-node output buffer for
a 5-node result — the `co_needed > co_capacity` path. It is **pre-existing work
from this round, not a consequence of the recursion fix**: the path had never
executed before, because reaching it required a session that spawned the real
compiler, which is exactly what the recursion prevented. Every other invoke test
passes once the stale `str`-era expectations are corrected, and text arguments
and results work through `mylang invoke` in both directions.

## Anything the lead should know

* `/tmp/.pending` had accumulated **1007** session staging directories from the
  bomb window (22:08–22:44, 18 MB); they were removed. A killed session leaves
  its staging directory behind, because `Session.init`'s `errdefer` cannot run in
  a process that is killed.
* The watchdog scripts used here (`.tmp/repro-recursion.sh`,
  `.tmp/safe-run.sh`, `.tmp/watch-invoke.sh`) match **any** cached test binary,
  not one fixed path — the first version watched a path that the build had
  already replaced and therefore counted zero.
