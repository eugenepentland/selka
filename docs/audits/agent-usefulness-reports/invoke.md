# I1 — invoke an ordinary export through the native runtime

Package: **I1** of [`agent-usefulness-implementation-plan-2026-09-20.md`](../agent-usefulness-implementation-plan-2026-09-20.md).
Worktree: `.worktrees/agent-usefulness`. Status: **implemented end to end on the
whole copied-value wire subset, aggregate arguments included (the pre-existing
adapter ABI defect this report originally deferred is fixed; see *The aggregate
argument, closed* below).**

Every number and every quoted output below was produced by the command shown
above it, in this worktree, with `MYLANG_QBE=$PWD/zig-out/focus/qbe` and
`MYLANG_ZIG=$PWD/zigw` (the sandbox wrappers for the vendored QBE build and for
Zig's unwritable global cache). The compiler under test was installed with
`./stage.sh` from the same sources.

## What changed

| File | Change |
| --- | --- |
| `src/invoke.zig` | The `native-invocation-v1` contract in one place: the `Status` vocabulary with hyphenated spellings, the response structs (`Response`, `Description`, `Contract`, `Authority`, `Invocation`, `Failure`, `Trap`, `Frame`, `Limits`, `Identities`), target selection over the checked `language-schema-v1` document, the eligibility walk that reports the first unsupported type path in two modes (`wire` and `execution`), named-argument validation, the raw-text duplicate-key scan, and trap-text parsing. |
| `src/invoke_wire_schema.zig` | Generated JSON Schema for the request object and the result value of the wire subset: decimal-string integers with their exact checked range, `additionalProperties: false`, exact array lengths, table keys, variant `oneOf`, and a domain resolved to its codec's wire shape under `x-mylang-domain`. Its `$comment` says it is not the language-contract graph, and it carries no effects, mutates or origin. |
| `src/invoke_execute.zig` | Checked-project preparation and one bounded child call: snapshot, `native-test-graph` facts (returning the compiler's located diagnostics on refusal), `Session.executor` selective library build, `Executor.attempt`. Also the precise classification of an unselectable target through the declared `interface-contracts-v2` manifest. |
| `src/invoke_command.zig` | Flag parsing, the diagnostic/stdout channel split, the response rendering and the exit status. Entry, `--function`, `--describe`, `--input`, `--format=json`, `--max-memory`, `--timeout`, the three execution quotas, `--cache-dir`, `--zig`, `--qbe`, `--mode`, `--report`. |
| `src/invoke_test.zig` | 15 spec-tagged tests: envelope and exit statuses, returned-error vs trap, structured trap frames, duplicate-key scanning (including nesting and strings), target selection, aggregate-argument eligibility (unit and end to end through the installed compiler), argument refusals, the generated schema, and the frontend-only session. |
| `src/native_test_session.zig` | Two extractions, both behaviour-preserving: `Session.initFrontend` (the existing `init` body minus tool resolution, which `init` now calls) and `factsText` (the existing `facts` body plus the compiler's located diagnostics on refusal, which `facts` now calls). |
| `src/native_test_execute.zig` | One extraction: `Attempt { outcome, timed_out }` and `Executor.attempt`, whose body is the old `execute` body plus the `err == error.Timeout` flag; `execute` is now a one-line wrapper, so the test runner's statuses, receipts and diagnostics are byte-identical. |
| `tests/invoke/tool.my` | The callable fixture: a library with **no `main` and no `test_` function** — `scale`, `byte_span` (`u8`), `ratio` (returned `Err`), `integer_divide` (trap), `count_up` (timeout), `announce` (`Stream` + captured output), `grow` (nested record/array result), plus `hidden` (private), `identity` (generic template), `probe_filesystem` (capability) and `sample_label` (nested aggregate argument, now executed). |
| `tests/invoke/broken.my` | A source-error fixture (`E_TYPE`). |
| `tests/invoke/requests/*.json` | Twelve request fixtures: valid, empty (zero-argument call), `Err`, out-of-range integer, JSON number for an integer, missing, extra, duplicate, nested result, timeout workload, stream call, and a nested record argument. |
| `SPEC.md` | Nine bullets (`INVOKE-1` … `INVOKE-8`, plus `INVOKE-9` for the widened aggregate-argument execution which supersedes the `aggregate-argument` clause of `INVOKE-2`). |
| `docs/tooling/invocation.md` | The `## mylang invoke` section: worked examples, the envelope and exit-status tables, the supported wire subset, refusals, the generated schema, bounds, and the measured per-call cost and reuse. |

`src/main.zig` and `src/features.json` were not touched; the existing dispatch and
feature entry are used as given.

## How it works

1. **Snapshot.** `Session.initFrontend`/`init` captures the entry's source
   inventory; `snapshot.withTestEntry` appends the same stub
   `def main() -> int: return 0` the guest-test runner appends, so a library with
   no `main` is callable without editing it; `snapshot.materialize` writes the
   private copy into the session's temporary directory.
2. **Check.** `Session.factsText` runs `native-test-graph` once. A refusal returns
   the child's own located diagnostics (also forwarded to stderr), not just a
   status code.
3. **Select.** `invoke.select` takes the exact `module::name` from the checked
   schema. A miss is classified with `list-interfaces --contracts` — the extra
   compiler child runs only on this failure path — into `unqualified-name`,
   `generic-template` (declaration carries generics), `private-target` (module
   published, declaration not exported) or `unknown-function`.
4. **Judge, before anything runs.** `invoke.eligibility` walks the checked type
   graph twice: once for the copied-value *wire* subset, once for what the native
   *adapter* can execute. It reports the first unsupported path (for example
   `argument 'note' -> field 'title'`), the capability types the signature needs,
   and the declared effects that are not grantable without host authority.
5. **Validate the request.** The raw bytes are scanned for a repeated top-level
   key, then parsed, then the names are checked against the declared parameters,
   then the copied-value codec (`native_test_wire.Codec`, unchanged) validates and
   flattens every value in declaration order, naming the offending argument on
   failure. This happens **before** the build, so a malformed request compiles
   nothing.
6. **Build.** `Session.executor` starts one persistent `native-test-compile`
   child, lowers exactly the selected closure, and drives
   `mylang build --project --library` with the shared `--cache-dir`; the resulting
   `Executor` binds the library, the checked schema types and the compiled C
   harness.
7. **Execute once.** `Executor.attempt` writes one request into a fresh child
   directory and runs the library in a new process under the resolved step,
   frame, call, byte and wall-clock bounds. Nothing about the call is cached, and
   a failure is never retried.
8. **Answer.** One `native-invocation-v1` object on stdout; compiler diagnostics
   also on stderr; captured guest output inside the object.

## Acceptance results

### 1. Invoke a non-test public function without modifying it

`tests/invoke/tool.my` declares no `main` and no `test_` function, and was not
edited to become callable.

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=tests/invoke/requests/scale.json
{"version":"native-invocation-v1","status":"completed","target":{"function":"tool::scale","entry":"tests/invoke/tool.my"},"invocation":{"kind":"value","value":"42","steps":4,"output":"","diagnostics":""},"context":{"limits":{"max_steps":1000000,"max_frames":1024,"max_calls":4096,"timeout_ms":60000,"max_memory":536870912},"identities":{"source":"8966bb0cc030...","compiler":"...","schema":"c65cdcf0fadf...","abi":"mylang-qbe-native-v5"}}}
$ echo $?
0
```

A zero-argument export is called with an empty object: `tool::answer` with
`{}` answers `completed 42` in 2 steps.

`--describe` on the same target needed no native toolchain at all
(`env -u MYLANG_QBE -u MYLANG_ZIG` → `described True`, exit 0), while `--input`
under the same environment reports `setup-failure` with `diagnostics:
"ToolNotFound"` and exits 2.

### 2. Integer boundaries and nested values

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::byte_span' --input=<{"first":"255","second":"0"}>
completed -255                      # u8 255 accepted
$ mylang invoke tests/invoke/tool.my --function 'tool::byte_span' --input=<{"first":"256","second":"0"}>
invalid-request argument 'first'    # out of u8 range
$ mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=tests/invoke/requests/out-of-range.json
invalid-request argument 'value' | argument 'value' is not a valid i64: the JSON value does not match the declared shape ...
$ mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=tests/invoke/requests/number.json
invalid-request argument 'value'    # JSON 21 refused where a decimal string is required
$ mylang invoke tests/invoke/tool.my --function 'tool::grow' --input=tests/invoke/requests/grow.json
completed {"label":"-9","span":{"low":"-9","high":"-18"},"weights":["-9","-8","-7"]}
```

The nested result is a record containing a record and a fixed array, decoded
element by element by the shared codec. Nested *arguments* are refused before
execution (see *Limits not closed*).

### 3. `Err`, traps and timeout are distinguished

| Command | Status | Exit | Payload |
| --- | --- | --- | --- |
| `tool::ratio` with `denominator: "0"` | `completed` | 0 | `{"kind":"returned-error","value":{"case":"err","value":"-1"},"steps":7}` |
| `tool::integer_divide` with `denominator: "0"` | `trap` | 1 | `R_DIVISION_BY_ZERO (floor_div: left 7, right 0)` with `frames[0] = {tool::integer_divide, tool.my, 43, 22}` |
| `tool::count_up` with `limit: "4000000000"`, `--timeout=1 --max-steps=4294967295` | `timeout` | 1 | `{"kind":"timeout","diagnostics":"Timeout"}` |
| `tool::scale` with `--max-memory=12x` | `invalid-request` | 2 | usage on stderr plus one object |
| `broken.my::bad` | `source-error` | 1 | `broken.my:9:18: error[E_TYPE]: expected int, found str` |
| `tool::sample_label` with `sample.json` | `completed` | 0 | `{"kind":"value","value":"7","steps":3}` |

The timeout is a wall-clock bound on the child process; the same call under a
larger bound instead traps `R_STEP_LIMIT`, which is a different status — that is
the distinction the contract asks for.

### 4. Private, unknown, generic and unsupported targets are rejected

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::hidden'    --describe   # private
invalid-request | private-target  | the module publishes no exported declaration named 'tool::hidden'; make it public or invoke an exported wrapper
$ mylang invoke tests/invoke/tool.my --function 'tool::identity'  --describe   # generic template
invalid-request | generic-template | 'tool::identity' is a generic template, so it has no concrete checked signature; add a concrete exported wrapper ...
$ mylang invoke tests/invoke/tool.my --function 'other::scale'    --describe   # no such module
invalid-request | unknown-function | no published module carries 'other::scale'; check the module name and the entry's import graph
$ mylang invoke tests/invoke/tool.my --function 'scale'           --describe   # unqualified
invalid-request | unqualified-name | the target must be the qualified name of an exported function, spelled 'module::name'
$ mylang invoke tests/invoke/tool.my --function 'tool::probe_filesystem' --describe
described | eligible false | authority | argument 'fs' | a capability argument needs a host grant; `mylang invoke` supplies only the standard streams
```

An unsupported nested type path is named exactly (`argument 'note' -> field
'title'` in the unit fixture), and `--describe` answers with `eligible: false`
and `wire_supported: false` rather than advertising the callable.

### 5. Source-mapped failures are retained

Trap diagnostics keep the located frame text and a structured form
(`trap.code`, `trap.operation`, `trap.frames[].{function,path,line,column}`);
source errors keep the compiler's own located line in `failure.diagnostics` and
on stderr.

### 6. Stdout stays parseable as one JSON object

Every status was checked by parsing stdout with `json.loads` and asserting one
line:

```
tool::scale          <- scale.json         : completed        lines=1 exit=0
tool::ratio          <- ratio-error.json   : completed        lines=1 exit=0
tool::integer_divide <- ratio-error.json   : trap             lines=1 exit=1
tool::announce       <- announce.json      : completed        lines=1 exit=0
tool::grow           <- grow.json          : completed        lines=1 exit=0
tool::scale          <- extra.json         : invalid-request  lines=1 exit=2
tool::sample_label   <- scale.json         : unsupported      lines=1 exit=2
```

`tool::announce` prints `value 5` in the guest; the bytes arrive in
`invocation.output` while stdout remains exactly one object.

### 7. Existing native-test behaviour is preserved

```console
$ ./zigw build test-native-tests
guardian/test: RESULT {"passed":93,"failed":0,"skipped":0}
$ mylang test tests/guest --filter '*'
42 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 11 programs
```

(The first `test-native-tests` run failed one unrelated, flaky
`qbe_build_io` concurrent-staging test; the immediate rerun above, and the full
gate, are green. `src/qbe_build_io.zig` is not in this package's diff.)

### 8. Repeated calls execute while unchanged artifacts are reused

```console
$ time mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=requests/scale.json --cache-dir=.tmp/reuse-a   # cold
0.649 s
$ time mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=requests/scale.json --cache-dir=.tmp/reuse-a   # warm
0.408 s
objects after cold: 3 digest=05daab324eabc16ff0b539b1d596a0d0
objects after warm: 3 digest=05daab324eabc16ff0b539b1d596a0d0   (digest unchanged)
```

* The content-addressed objects (name, size, mtime) are identical before and
  after the warm call: nothing was recompiled.
* An equivalent `mylang build --report` against that same cache directory:
  `compiled_functions: 0, reused_functions: 1, runtime_reused: true`.
* `mylang invoke … --report` on a warm call prints `work-report-v1` on stderr:
  `parsed_modules` `hit`/`reused 1`, `checked_bodies` `hit`/`reused 11`,
  `lowered_functions` performed `1`, `reused_results: 0`. The selective lower
  runs per invocation; the native object is reused; no call result is.
* Two warm `tool::announce` calls each report `steps: 12` and captured
  `value 5\n`, i.e. the guest ran both times.

`--describe` on a warm cache measures **0.069 s**.

## Supported and unsupported type matrix

| Checked type | Wire (arguments/results) | Executable argument | Executable result |
| --- | --- | --- | --- |
| `i8`/`i16`/`i32`/`i64`, `u8`/`u16`/`u32`/`u64` | decimal string | yes (verified `i64`, `u8`) | yes |
| `bool` | JSON Boolean | yes (codec-level; no fixture) | yes (codec-level) |
| record of supported fields | object of its fields | yes (verified nested, `sample_label`) | yes (verified nested) |
| `[N]T` fixed array | exactly `N` items | yes (verified inside the same call) | yes (verified) |
| table keyed by an enumeration | object, one entry per key | yes (codec-level; no fixture) | codec-level |
| enumeration | case-name string | yes (codec-level; no fixture) | codec-level |
| tagged union / `Result` | `{"case","value"}` | yes (codec-level; no fixture) | yes (verified `Err`/`Ok`) |
| domain with a codec | its codec's wire shape | yes (codec-level; no fixture) | yes (verified by hand through the same adapter; no invoke fixture) |
| integer alias (`type X = i64`) | — | refused (`unsupported-type`) | refused |
| `Stream` parameter | injected, no request value | yes (verified) | — |
| `str`, `bytes`, `list[T]`, buffers, resources, handles, callbacks, unit, other capabilities | — | refused with the first path | refused with the first path |

Effects: `managed_allocation`, `output` (printing to the injected stream) and
`mutation` (of copied arguments) are allowed; `filesystem`, `network`, `clock`,
`random`, `environment` and `host` are refused as `authority`.

## The aggregate argument, closed

* **Aggregate arguments are executed.** Fixed in this change, exactly along the
  line this report predicted: `src/qbe_wire.zig` carries the emitter's own
  crossing decision into the `wire_types` manifest as a per-type `by_address`
  fact, and `src/qbe_build_shapes.zig` declares `const void *` and passes
  `co_arguments[i]` for a recorded crossing instead of dereferencing the buffer
  by value. `invoke.argumentRefusal` no longer refuses a copyable aggregate, so
  `sample_label` executes; see `aggref-abi.md` for the defect, the fix and the
  agreement test.

`mylang emit-project-qbe` on a record parameter emits
`export function l $myl_f_…(l %ctx, l %a0)` and `storel %a0, %l0`; the generated
adapter now passes the argument buffer pointer for exactly the types the manifest
marks `by_address`, so the callee reads the same bytes the codec wrote. The
guest-level guard in `tests/native/aggref_arguments.my` and the three-way
manifest/QBE/C agreement test keep the two sides from drifting apart again.

## Limits not closed

* **No `--schema`-only command**: the generated JSON Schema is published inside
  the `--describe` object rather than as a standalone document selection.
* **`--format` is `json` only**; a human-readable text mode was not added.
* **Domain round-trips are not covered by an invoke fixture.** The domain codec
  path was verified by hand through the same adapter (a `Result` whose `Ok`
  payload is a domain decodes to `{"count":"5"}`, and a rejected decode returns
  `{"case":"err","value":"-1"}`), but the committed fixture set does not include
  a domain module.
* **The trap parser is text-shaped.** `invoke.trapDetail` parses the runtime's
  located rendering; an unparsable text leaves the structured fields empty and
  keeps the raw `diagnostics` authoritative. A future protocol version that
  carried the trap detail fields directly would remove that dependency.
* **Per-call cost is dominated by the frontend check plus one `zig cc` of the C
  harness** (0.408 s warm for a one-scalar call). The harness compile is not
  cached across processes by this package; only the QBE objects and the frontend
  query caches are.
* **Per-call cost includes the C harness compile.** An executing invocation
  compiles the embedded `native-test_runner.c` through `zig cc` in its own
  temporary directory; only Zig's own cache makes that cheap. A durable harness
  cache keyed by the embedded source and the tool identity would remove it, and
  is not part of this package.

## Spec tags

`INVOKE-1` target selection and its four refusal kinds; `INVOKE-2` the first
unsupported path and the authority refusals; `INVOKE-3` request validation;
`INVOKE-4` the envelope and exit statuses; `INVOKE-5` returned `Err` vs trap vs
timeout; `INVOKE-6` the generated JSON Schema; `INVOKE-7` the frontend-only
session; `INVOKE-8` the command line; `INVOKE-9` aggregate-argument eligibility
and the end-to-end nested-record call, which supersedes the `aggregate-argument`
clause of `INVOKE-2`. One primary `// spec:` test each, with the remaining tests
carrying `// spec-case:`.

## Commands run

```console
$ ./zigw build -Dtest-shards=1 test-units -Dtest-filter=invoke   # guardian/test: RESULT {"passed":27,"failed":0,"skipped":0}
$ ./zigw build test-native-tests                                  # guardian/test: RESULT {"passed":93,"failed":0,"skipped":0}
$ mylang test tests/guest --filter '*'                            # 42 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 11 programs
$ mylang doctest .                                                # 733 blocks, 154 run, 0 mis-tagged, 0 failed
$ mylang doc-coverage .                                           # doc-coverage: 0 failures
$ ./zigw build test --summary all                                 # Build Summary: 61/64 steps succeeded (2 failed); 1487/16543 tests passed (15055 skipped, 1 failed)
$ ./zigw build -Dtest-shards=1 test-units -Dtest-filter="concurrent staging"
                                                                  # guardian/test: RESULT {"passed":12,"failed":0,"skipped":0} on the rerun
$ ./zigw build                                                    # exit 0; guardian: run-all: 88 check(s) passed; installed zig-out/bin/mylang
$ ./zigw build fmt-check                                          # exit 0
$ guardian-check all .                                            # 88 checks passed (before the full gate finished another package's fix)
```

The one full-gate failure is
`qbe_build_io.test.concurrent staging in one destination never loses a child to
another build's reclaim`, which fails with `unexpected errno: 2` from a
concurrent `/tmp` staging race and passes when rerun in isolation; it does not
touch this package's files and predates it.

`mylang invoke` also releases its temporary copy of the project on both paths:
two invocations (one executing, one rejected at check time) in a single shell
leave `/tmp` with the same entry count it started with, and a rejected project is
answered from the located text after the temporary directory is removed.

Final end-to-end run with the **installed** compiler, no `MYLANG_QBE`/`MYLANG_ZIG`
overrides (the sibling `zig-out/bin/qbe` is found next to the compiler):

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=tests/invoke/requests/scale.json
{"version":"native-invocation-v1","status":"completed", ... "value":"42","steps":4 ...}
$ mylang invoke tests/invoke/tool.my --function 'tool::sample_label' --input=tests/invoke/requests/sample.json
{"version":"native-invocation-v1","status":"completed","target":{"function":"tool::sample_label","entry":"tests/invoke/tool.my"},
"invocation":{"kind":"value","value":"7","steps":3,"output":"","diagnostics":""},"context":{...}}
$ echo $?
0
```
