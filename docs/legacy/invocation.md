# Invoking an exported function

> **Removed 2026-10 (new core S5-D5).** `mylang invoke` and its
> `native-invocation-v1` envelope were retired with host functions; the command is
> refused with status 2. This page is kept as a record.

`mylang invoke` calls one exported function of a checked program through the same
native runtime the guest tests use, without editing the program first. The three
questions it answers are: *what does this export accept and return* (`--describe`),
*what happens when I call it with these arguments* (`--input`), and *why can I not
call it at all* (a refusal that names the first unsupported type path or the
missing capability instead of advertising an unusable callable).

The route reuses the native test runner's machinery rather than a parallel copy of
it: the same immutable source snapshot with a stub `def main() -> int: return 0`
appended when the entry is a library, the same frontend facts request, the same
selective `--library` build with its content-addressed object cache, the same
copied-value codec, and the same child request/response protocol. Nothing is
cached about a *call*: every requested invocation executes in a fresh child. Only
compiled artifacts are reused, and the observed reuse is recorded below.

## mylang invoke

```console
$ mylang invoke <entry.my> --function 'module::name' (--describe | --input=FILE) [options]
```

`--function` takes the qualified `module::name` of an **exported concrete**
function. The entry may be a library with no `main`: a private copy gains the same
stub entry the guest-test runner adds, so a tool is callable without editing it or
writing a dummy program. `--describe` and `--input` are mutually exclusive; exactly
one is required, and `--format=json` is the only format.

Describe one export without running it:

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::scale' --describe
{"version":"native-invocation-v1","status":"described","target":{"function":"tool::scale",
"entry":"tests/invoke/tool.my"},"description":{"eligible":true,"contract":{"arguments":[
{"name":"value","type":"i64","wire":"integer","injected":false},
{"name":"factor","type":"i64","wire":"integer","injected":false}],
"result":{"type":"i64","wire":"integer"},"effects":[],"mutates":[],
"return_origin":"unknown"},"authority":{"capabilities":[],"effects":[]}, ...},
"context":{"limits":{"max_steps":1000000,"max_frames":1024,"max_calls":4096,
"timeout_ms":60000,"max_memory":536870912},"identities":{...}}}
```

The response above is one line on stdout, wrapped here for readability. It also
carries `description.wire_schema`, the generated JSON Schema described below.

Call it with a typed JSON request (`tests/invoke/requests/scale.json` is
`{"value": "21", "factor": "2"}`):

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=tests/invoke/requests/scale.json
{"version":"native-invocation-v1","status":"completed","target":{"function":"tool::scale",
"entry":"tests/invoke/tool.my"},"invocation":{"kind":"value","value":"42","steps":4,
"output":"","diagnostics":""},"context":{...}}
$ echo $?
0
```

A returned language `Result.Err` is a **completed** call, not a failure:

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::ratio' --input=tests/invoke/requests/ratio-error.json
{"version":"native-invocation-v1","status":"completed", ... ,
"invocation":{"kind":"returned-error","value":{"case":"err","value":"-1"},"steps":7, ...}}
$ echo $?
0
```

A runtime trap exits 1 and keeps its source-mapped trace:

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::integer_divide' --input=tests/invoke/requests/ratio-error.json
{"version":"native-invocation-v1","status":"trap", ... ,
"invocation":{"kind":"trap","steps":3,"output":"",
"diagnostics":"R_DIVISION_BY_ZERO (floor_div: left 7, right 0)\n  in tool::integer_divide at tool.my:43:22\n",
"trap":{"code":"R_DIVISION_BY_ZERO","operation":"floor_div","frames":[
{"function":"tool::integer_divide","path":"tool.my","line":43,"column":22}]}}, ...}
$ echo $?
1
```

A call that outruns its wall-clock bound is its own status, distinct from a trap:

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::count_up' --input=slow.json \
    --timeout=1 --max-steps=4294967295
{"version":"native-invocation-v1","status":"timeout", ... ,
"invocation":{"kind":"timeout","steps":0,"diagnostics":"Timeout"}}
$ echo $?
1
```

A function that prints through its injected `Stream` parameter returns its output
in the response instead of on the protocol channel:

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::announce' --input=tests/invoke/requests/announce.json
{"version":"native-invocation-v1","status":"completed", ... ,
"invocation":{"kind":"value","value":"5","steps":12,"output":"value 5\n", ...}}
```

## Response envelope

One `native-invocation-v1` object is the whole of stdout; compiler diagnostics are
also written to stderr, and captured guest output stays inside the object.

| Field | Meaning |
| --- | --- |
| `version` | Always `native-invocation-v1`. |
| `status` | `described`, `completed`, `trap`, `timeout`, `source-error`, `invalid-request`, `unsupported` or `setup-failure`. |
| `target.function`, `target.entry` | The requested qualified name and entry path. |
| `description` | Present for `--describe`: `eligible`, `wire_supported`, `contract`, `authority`, `wire_schema`, `unsupported`. |
| `invocation` | Present for `--input`: `kind` (`value`, `returned-error`, `trap`, `timeout`, `host-failure`), `value`, `steps`, `output`, `diagnostics`, `trap`. |
| `failure` | Present when nothing ran: `kind`, `path`, `reason`, `diagnostics`. |
| `context.limits` | The effective `max_steps`, `max_frames`, `max_calls`, `timeout_ms` and `max_memory` the child ran under. |
| `context.identities` | `source` (captured inventory identity), `compiler` (build identity), `schema` (SHA-256 of the checked `language-schema-v1` document) and `abi`. |

### Exit statuses

| Exit | Statuses | Meaning |
| --- | --- | --- |
| 0 | `described`, `completed` | The answer was produced; a returned `Result.Err` is completed. |
| 1 | `trap`, `timeout`, `source-error` | The guest trapped or ran out of its wall-clock bound, or the project did not check. |
| 2 | `invalid-request`, `unsupported`, `setup-failure` | The request, the selected signature or the host environment made the call impossible. |

## The supported wire subset

`--describe` decides eligibility from the checked schema alone, before any guest
code runs, and reports two things separately: `wire_supported` (the copied-value
codec can carry the type) and `eligible` (the native adapter can execute it). The
two now agree on every argument shape the codec reconstructs.

| Checked type | As a result | As an argument |
| --- | --- | --- |
| `i8`/`i16`/`i32`/`i64`, `u8`/`u16`/`u32`/`u64` | decimal string, exact range | decimal string, exact range |
| `bool` | JSON Boolean | JSON Boolean |
| `Stream` parameter | — | injected by the runtime, no request value |
| record of supported fields | object of its fields | object of its fields |
| `[N]T` fixed array | exactly `N` items | exactly `N` items |
| table keyed by an enumeration | object with one entry per key | object with one entry per key |
| enumeration | case name string | case name string |
| tagged union / `Result` | `{"case": "...", "value": ...}` | `{"case": "...", "value": ...}` |
| domain with a codec | its codec's wire shape | its codec's wire shape |
| anything else (`str`, `bytes`, `list[T]`, buffers, resources, callbacks, units, other capabilities) | refused with the first unsupported path | refused with the first unsupported path |

Integers are exact and cross as decimal strings: `"9223372036854775807"` is
accepted for `i64` and `"9223372036854775808"` is refused, `"256"` is refused for
`u8`, and a JSON number (`21`) is refused where a decimal string is required.
A user alias of an integer is a distinct nominal spelling and is not reconstructed.

An **aggregate argument** (record, array, table, domain, variant) is executable.
An unmanaged aggregate crosses the guest ABI as the address of its storage
(`export function l $myl_f_...(l %ctx, l %a0)` stores `%a0` and reads fields
through it), and the generated copied-value adapter now reads that same crossing
from the compiler's `wire_types` manifest: it declares the C parameter
`const void *` and passes the argument buffer pointer itself, for the ordinary
copied-value dispatch and for a codec callback argument alike. A scalar argument
keeps its `co_word(...)`/`wire_word(...)` spelling, a move-only aggregate keeps
its by-value copy, and every supported aggregate *result* is unaffected.

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::sample_label' --input=tests/invoke/requests/sample.json
{"version":"native-invocation-v1","status":"completed","target":{"function":"tool::sample_label", ... },
"invocation":{"kind":"value","value":"7","steps":3,"output":"","diagnostics":""},"context":{ ... }}
$ echo $?
0
```

`tests/invoke/requests/sample.json` is
`{"sample": {"label": "7", "span": {"low": "1", "high": "2"}, "weights": ["1", "2", "3"]}}`,
so a nested record, a nested record field and a fixed array all cross the copied
boundary in one call.

A **capability argument** other than the injected `Stream` is kind `authority`:
`mylang invoke` supplies the standard streams and nothing else, so a signature
needing `Filesystem`, `Network`, `Clock`, `Entropy` or `Environment` is
refused, as is any declaration whose effect ceiling includes `filesystem`,
`network`, `clock`, `random`, `environment` or `host`. Managed allocation,
printing to the injected stream (`output`) and mutation of copied arguments are
allowed and reported.

Any other unsupported type reports the first path that fails, for example
`argument 'note' -> field 'title'`.

## Request validation and refusals

A request file is exactly one JSON object of named arguments: no envelope, no
positional list. It is checked against the selected signature before the library
is built, so a bad request never compiles anything.

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=tests/invoke/requests/extra.json
{"version":"native-invocation-v1","status":"invalid-request", ... ,
"failure":{"kind":"invalid-request","reason":"argument 'extra' is not a parameter of the selected function"}}
$ mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=tests/invoke/requests/missing.json
... "reason":"argument 'factor' is missing"
$ mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=tests/invoke/requests/duplicate.json
... "reason":"argument 'value' is given more than once"
$ mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=tests/invoke/requests/out-of-range.json
... "failure":{"kind":"invalid-request","path":"argument 'value'",
"reason":"argument 'value' is not a valid i64: the JSON value does not match the declared shape ..."}
```

A key repeated in the raw request text is rejected as a duplicate: a parsed JSON
object has already lost the first spelling, so the check runs over the bytes.

An unselectable target names which kind of miss it is:

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::hidden' --describe
... "failure":{"kind":"private-target","reason":"the module publishes no exported declaration named 'tool::hidden'; make it public or invoke an exported wrapper"}
$ mylang invoke tests/invoke/tool.my --function 'tool::identity' --describe
... "failure":{"kind":"generic-template","reason":"'tool::identity' is a generic template, so it has no concrete checked signature; add a concrete exported wrapper ..."}
$ mylang invoke tests/invoke/tool.my --function 'other::scale' --describe
... "failure":{"kind":"unknown-function","reason":"no published module carries 'other::scale'; check the module name and the entry's import graph"}
$ mylang invoke tests/invoke/tool.my --function 'scale' --describe
... "failure":{"kind":"unqualified-name","reason":"the target must be the qualified name of an exported function, spelled 'module::name'"}
```

A generic function has no concrete checked signature, so the initial route is an
exported concrete wrapper:

```mylang
def identity[T](value: T) -> T effects():
    return value


public def normalize(value: i64) -> i64 effects():
    return identity(value)
```

A source error keeps its located compiler diagnostic, on stderr and in the object:

```console
$ mylang invoke tests/invoke/broken.my --function 'broken::bad' --describe
{"version":"native-invocation-v1","status":"source-error", ... ,
"failure":{"kind":"source-error","reason":"the project did not check",
"diagnostics":"broken.my:9:18: error[E_TYPE]: expected int, found str\n      return value + label\n                   ^\n"}}
$ echo $?
1
```

## Generated wire schema

`--describe` includes a JSON Schema for the request object and for the result
value. It describes only the invocation wire subset — integers as decimal strings
with their exact checked range, `additionalProperties: false`, exact array
lengths, a domain resolved to its codec's wire shape under `x-mylang-domain` — and
it carries no effects, mutation footprint or return origin, so it cannot be
mistaken for the `language-schema-v1` contract graph.

The request schema sits at `description.wire_schema.request`; laid out for
reading, it is:

```console
$ mylang invoke tests/invoke/tool.my --function 'tool::scale' --describe --format=json
{"version":"native-invocation-v1","status":"described", ... "wire_schema":{"request":
{
  "$id": "native-invocation-v1/request",
  "title": "mylang invoke request for tool::scale",
  "$comment": "native-invocation-v1 wire subset: named arguments only, integers as decimal strings. This is not the language-contract graph.",
  "x-mylang-dialect": "2020-12",
  "type": "object",
  "properties": {
    "value": {"type": "string", "pattern": "^-?(0|[1-9][0-9]*)$", "x-mylang-type": "i64",
              "x-mylang-minimum": "-9223372036854775808", "x-mylang-maximum": "9223372036854775807"},
    "factor": {"type": "string", "pattern": "^-?(0|[1-9][0-9]*)$", "x-mylang-type": "i64", ...}
  },
  "required": ["value", "factor"],
  "additionalProperties": false
},"result":{...}}, ...}
```

## Worked examples

Two small libraries under `examples/invoke/` show the route end to end with no
handwritten JSON plumbing. Each is an ordinary program — `mylang run` executes
its `main` — and each is also callable as a library, because `invoke` checks a
private copy under the same stub entry the guest-test runner uses.

An agent discovers a contract by asking for it rather than by reading the wire
form:

```console
$ mylang invoke examples/invoke/reading_validator.my \
    --function 'reading_validator::validate' --describe --format=json
{"version":"native-invocation-v1","status":"described", ... "description":{"eligible":true,"wire_supported":true,"contract":{"arguments":[{"name":"reading","type":"reading_validator::Reading","wire":"record","injected":false}],"result":{"type":"reading_validator::Verdict","wire":"result"}, ...}, ...}}
```

`reading_validator` is a structured-record validator. A `Reading` goes in as a
record of scalars and a `Verdict` comes back as a result whose `err` arm names
the rule that failed, so a caller can tell a cold sensor from an unsteady one
without parsing prose:

```console
$ mylang invoke examples/invoke/reading_validator.my \
    --function 'reading_validator::validate' \
    --input=examples/invoke/requests/reading-cold.json --format=json
{"version":"native-invocation-v1","status":"completed", ... "invocation":{"kind":"returned-error","value":{"case":"err","value":{"site":"3","rule":"too_cold","observed":"-40"}},"steps":27, ...}, ...}
```

`text_report` is a text/list transformation. `summarize` takes Unicode text
plus a `list[str]` and returns a record of counts; `join`, `widths` and
`bracket_all` move the same list across the boundary in the other direction:

```console
$ mylang invoke examples/invoke/text_report.my \
    --function 'text_report::summarize' \
    --input=examples/invoke/requests/text-report.json --format=json
{"version":"native-invocation-v1","status":"completed", ... "invocation":{"kind":"value","value":{"scalars":"5","pieces":"3","longest":"2","empty":"1"},"steps":120, ...}, ...}
```

`scalars` counts Unicode scalars and not bytes, so `héllo` is five. The request
fixtures sit beside the examples in `examples/invoke/requests/`.

Every one of these calls is run twice, once through the vendored QBE and once
through the LLVM backend, by `tests/native_boundary_matrix.py`
(`zig build test-native-boundary`). That driver requires the two backends to
produce the same answer *and* the answer the contract declares, because a matrix
that only compared them to each other would pass if both were wrong the same way.

## Quotas and toolchain

`--max-steps`, `--max-frames`, `--max-calls` and `--timeout=SECONDS` bound the
call; `--max-memory=BYTES` (or `MYLANG_MEMORY_LIMIT`) sets the child's byte ceiling
and defaults to 512 MiB. The effective values are echoed in `context.limits` and
are part of what the child enforces.

`--describe` needs no native toolchain: it captures the sources, checks the
project and reads its facts while `zig` and `qbe` are never resolved. `--input`
needs both — `--zig` and `--qbe` name them, then `MYLANG_ZIG`/`MYLANG_QBE`, then a
sibling of the compiler, then `PATH` — and reports `setup-failure` with the
missing tool otherwise. `--cache-dir=DIR` points the shared frontend and object
caches somewhere other than `.mylang-cache/tests`, and `--mode=Debug|ReleaseFast`
selects the build mode.

## Measured per-call cost and reuse

Measured on this worktree (amd64 Linux, warm page cache), one `tool::scale` call
with `--cache-dir` freshly created for the cold run:

```console
$ time mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=requests/scale.json --cache-dir=.tmp/reuse-a   # cold
0.649 s
$ time mylang invoke tests/invoke/tool.my --function 'tool::scale' --input=requests/scale.json --cache-dir=.tmp/reuse-a   # warm
0.408 s
$ mylang invoke tests/invoke/tool.my --function 'tool::scale' --describe                                                  # warm
0.069 s
```

Repeated calls execute while the unchanged native artifacts are reused, and the
reuse is observable:

* the three content-addressed objects the cold call created are byte-identical —
  same names, sizes and modification times — after the warm call
  (`find .tmp/reuse-a -name '*.o' -printf '%T@ %s %p\n' | sort | md5sum` is the
  same digest before and after);
* an equivalent `mylang build --report` against that same cache directory reports
  `compiled_functions: 0, reused_functions: 1, runtime_reused: true`;
* `mylang invoke --report` prints the frontend work report on stderr for a warm
  call: `parsed_modules` `hit`/`reused 1`, `checked_bodies` `hit`/`reused 11`,
  while the selective lower still runs once per invocation.
