# Calling one export

> **Removed 2026-10 (new core S5-D5).** `mylang invoke` was retired with host
> functions; it is refused with status 2. Call the function from a `main` or a
> test. This page is kept as a record.

`mylang invoke` calls **one ordinary exported function** through the native
runtime `mylang test` already uses: the same checked schema, the same
copied-value codec, the same isolated bounded child process and the same
compilation artifacts. It reimplements none of that. What it adds is the part a
caller needs — a selector that names an export instead of a test, the
eligibility question a checked signature does not answer, and one
`native-invocation-v1` object that keeps a returned value distinct from a trap,
a timeout and a bad request. It is the command for a coding agent that wants to
exercise a library function rather than read it.

The execution surfaces answer different questions:

| Command | The question it answers |
| --- | --- |
| `mylang test` | Do this project's guest tests pass? Every discovered `test_` function runs as its own native process, against an expectation declared up front. |
| `mylang context` | What are the published facts about this one declaration? It answers from the navigation, interface, reachability and diff tables the inspection commands already publish, and executes nothing. |
| `mylang invoke` | What does this one export actually do with these arguments? It checks, compiles and calls that export once, and reports the typed result. |

The examples below call two exports of a library module, `stats.my`, that
declares no `main`:

```mylang
# doc: skip library fragment: the bash example below is what calls this export
module stats

public enum Status:
    ready,
    failed

public record Sample:
    sequence: u64
    status: Status

public def scale_up(sequence: u64, scale: u64) -> u64 effects():
    return sequence * scale

public def sequence_of(sample: Sample) -> u64 effects():
    return sample.sequence
```

## `mylang invoke`

Exactly one of `--describe` and `--input=FILE` is required, and `--function` is
always required:

```bash
mylang invoke stats.my --function 'stats::scale_up' --describe --format=json
mylang invoke stats.my --function 'stats::scale_up' --input=request.json --format=json
```

`--function` names one exported concrete function in the `module::name` spelling
`mylang index-project` and `mylang context` already use. A name that is not an
export of the project, or a generic template with no checked instantiation, is
rejected before any guest code runs. The entry may be a library module with no
`main`: the runner supplies a synthetic entry point exactly as `mylang test`
does, so no dummy `main` has to be added to make an export callable.

| Option | Meaning |
| --- | --- |
| `--function 'module::name'` | The one exported concrete function to call. Required. |
| `--describe` | Report the selected export's contract and invocation eligibility without executing any guest code. |
| `--input=FILE` | Call the export once with the named arguments in the JSON object `FILE` holds. |
| `--format=json` | The response format. `json` is the only format today. |

Execution is bounded by the same knobs, and the same defaults, as one native
test call:

| Option | Meaning |
| --- | --- |
| `--max-steps=N`, `--max-frames=N`, `--max-calls=N` | Instruction, call-depth and call-count ceilings for the call. The defaults are 1000000 steps, 1024 frames and 4096 calls. |
| `--timeout-ms=N` | Wall-clock bound on the child process. The default is 60000 ms. |
| `--max-memory=BYTES` | The child's managed-heap ceiling, with `K`/`M`/`G` suffixes. The flag outranks `MYLANG_MEMORY_LIMIT`; the default is the test default of 512 MiB. |
| `--gc-stress` | Run the call under the runtime's stress collector, so a returned managed value is exercised against a collector that runs far more often than usual. |
| `--cache-dir=DIR` | Where compilation artifacts and checked facts are cached. The default is `.mylang-cache/invoke`. |
| `--no-cache` | Perform no durable cache reads or writes at all. |
| `--qbe=PATH`, `--zig=PATH` | The native tools to use instead of locating them beside the compiler or on `PATH`. |
| `--mode=Debug\|ReleaseFast` | The optimization mode of the native build. |

The command resolves these bounds before it answers and reports the effective
values in every response, so the defaults above are exactly what a response
shows when the flag that sets them is absent.

The cache holds compilation artifacts and checked facts, never call results. An
invocation is not answered from a cached test success, and a requested call is
never retried automatically: every requested invocation executes. That execution
inherits the native test runner's isolation — a fresh child process under the
call's bounds — and the isolation bounds the call rather than making arbitrary
foreign code safe. `mylang invoke` grants no external authority at all, so an
export that needs any is refused before it runs.

A worked example lives at [examples/invoke-report](../../examples/invoke-report/README.md):
a library that declares no `main`, one export returning a text report and one
returning a list, and the `--describe` and `--input` calls that reach them.

## `--describe` and eligibility

`--describe` answers the question a checked signature does not: could this
export be called from JSON at all? It reports, without executing any guest code:

- the checked argument and result contract, rendered from the checked schema;
- each parameter's checked type, its mode and how it reaches the callee, and the
  result's checked type;
- the declared effects;
- the capabilities the export requires;
- the effective execution limits the call would run under; and
- the invocation eligibility — and, when the export is not eligible, exactly
  why.

The rule the command enforces is that a checked signature is not necessarily a
serializable or callable one. Two boundaries decide it, and they are not the
same width: the copied-value codec decides what can be a **copied value**, and
the native call ABI decides what can be a **call argument or a call result**.
The ABI is the narrower one — it carries integers, booleans and an injected
`Stream` — so a record is a perfectly good copied value that still cannot cross
a call. Rather than advertise a callable tool it would then refuse, the
description names the first unsupported type path and the reason. An export that
describes as ineligible still describes — `--describe` answers with the facts
and exits 0 — because the description is the answer; only `--input` refuses that
export, and does so with exit status 2.

```json
{
  "version": "native-invocation-v1",
  "status": "ok",
  "function": "stats::scale_up",
  "identities": {
    "compiler": "<compiler build identity>",
    "zig": "<Zig tool stamp>",
    "qbe": "<QBE tool stamp>",
    "source": "<checked source snapshot identity>",
    "schema": "<checked schema digest>"
  },
  "limits": {"max_steps": 1000000, "max_frames": 1024, "max_calls": 4096, "timeout_ms": 60000, "max_memory": 536870912},
  "describe": {
    "signature": "def stats::scale_up(sequence: u64, scale: u64) -> u64 effects()",
    "parameters": [
      {"name": "sequence", "type": "u64", "mode": "value", "wire": "copied"},
      {"name": "scale", "type": "u64", "mode": "value", "wire": "copied"}
    ],
    "result": "u64",
    "effects": [],
    "required_capabilities": [],
    "invocation": {
      "eligible": true,
      "reason": null,
      "wire": {"supported": true, "unsupported_path": null, "unsupported_detail": null}
    }
  }
}
```

A parameter's `wire` reads `copied` for a value the codec encodes, `injected`
for the `Stream` the adapter supplies (no JSON argument, no host grant) and
`authority` for a capability parameter, which JSON can never mint. A description
carries the qualified function name in its rendered `signature`: the schema
publishes the checked contract, not the source text.

An export the ABI cannot call answers with `"eligible": false`, the first
blocking position in `wire.unsupported_path` and `wire.unsupported_detail`, and
a `reason` that repeats it. Describing the record-taking
`stats::sequence_of` above reads:

```json
"invocation": {
  "eligible": false,
  "reason": "the type at parameters.sample cannot cross the invocation boundary: the native call ABI carries integers, booleans and an injected stream; that type is a copied value but not a call argument",
  "wire": {"supported": false, "unsupported_path": "parameters.sample", "unsupported_detail": "the native call ABI carries integers, booleans and an injected stream; that type is a copied value but not a call argument"}
}
```

When authority, rather than a type, is what stops the export, the description
carries the missing capability in `required_capabilities` and its name in
`reason`, with no unsupported path — the wire verdict is about types alone. An
export whose result the ABI cannot carry is refused at path `result` the same
way a parameter is.

## The wire subset

Two boundaries stand between a caller and a running export, and the page keeps
them apart on purpose.

The **copied-value codec** decides what can be a copied value at all. It is the
typed JSON representation [Typed JSON boundaries](../typed-json.md) defines for
the compiler's boundary — the same one `mylang test --cases` carries arguments
and expectations in — and not the guest-level `json` module:

| Type | Wire representation |
| --- | --- |
| Fixed-width integer | A canonical decimal **string**, so a 64-bit value survives a JSON client whose native numbers cannot represent it. |
| Boolean | A JSON boolean. |
| Record | An object with every declared field exactly once and no extra fields. |
| `Result`, tagged union, enumeration | A `Result` or union is an object with `case`, plus `value` for a payload-bearing case; an enumeration is its case-name string. |
| Domain with a declared wire codec | The representation of the codec's wire type. A domain that declares no wire codec is rejected. |
| Fixed-length array | An array of exactly the declared length. |

The **native call ABI** of the isolated child is narrower than that codec. It
carries integers and booleans by value, and an injected `Stream`; nothing else
is a call argument or a call result in this version. A record, a `Result`, a
tagged union, an enumeration, a domain and a fixed-length array are all copied
values the codec would carry and none of them can cross a call — which is why
`--describe` reports `stats::sequence_of` ineligible even though every type in
its signature is a copied value.

A `Stream` parameter is injected by the adapter and takes no JSON argument.
Everything else is rejected before any guest code runs, including a
`Filesystem`, `Network`, `Clock`, `Entropy` or `Environment` capability
parameter and any managed value such as `list[T]` or `dict[str, T]`.

The managed values that cross today are **`str` and `list[T]` of a scalar, and
only as results**. A returned text arrives as the JSON string its scalars spell,
and a returned list as a JSON array of its elements in the declared element
form, so

```bash
mylang invoke stats.my --function 'stats::greeting' --input=request.json
```

```
"outcome": {"status": "returned", "value": "h\u00e9llo \u4e16\u754c", "diagnostics": "", "output": "", "steps": 5}
```

A managed value the guest returns is read out after the call has finished and
nothing is allocated while it is read, so the handle never has to survive a
collection safepoint. A managed *argument* is a different matter: building a
guest value while materialising the remaining arguments would need a root held
across the next argument's allocation, which the codec runtime does not do yet,
so `--describe` reports a `str` or `list[T]` parameter ineligible with exactly
that reason and `--input` refuses it with exit 2.

`str` is the one list read as a string; `list[u32]`, which has the same shape,
is an array. `bytes` is not carried at all — the plan gives it its own encoding
rather than letting it inherit this one.

The first version accepts only exports whose effects and signature need no
external authority. Managed allocation, printing to an injected `Stream` and
mutation of copied inputs do not count as external authority.

## The request

`--input=FILE` reads one JSON object of **named** arguments. Each member key is
a parameter name and each value is the bare typed-JSON value of that parameter's
type — not the three-field `typed-json-v1` envelope, because the selected
signature already fixes every type. A request for `stats::scale_up` above looks
like this:

```json
{
  "sequence": "7",
  "scale": "3"
}
```

The integers are decimal strings rather than JSON numbers, so a `u64` argument
of `18446744073709551615` is written as that decimal string and keeps its full
64-bit value across a client whose numbers cannot carry it. The object is
checked against the selected signature before any guest code runs. A missing
argument, an extra argument, a duplicate name, an unreadable or malformed file,
or a value that does not match the declared type at that position is a request
failure: no child process is started, no guest code runs, and the answer reports
the request refusal instead of an outcome.

## The response

Exactly one `native-invocation-v1` JSON object is published on stdout, and
nothing else is. Compiler diagnostics and any captured guest output stay off
that channel — the compiler's diagnostics are forwarded on stderr, and guest
output is carried inside the object as well. The envelope names the compiler,
source and schema identities of the snapshot that answered, the effective
limits the call ran under, the selector, and either the description or the
outcome:

```json
{
  "version": "native-invocation-v1",
  "status": "ok",
  "function": "stats::scale_up",
  "identities": {
    "compiler": "<compiler build identity>",
    "zig": "<Zig tool stamp>",
    "qbe": "<QBE tool stamp>",
    "source": "<checked source snapshot identity>",
    "schema": "<checked schema digest>"
  },
  "limits": {"max_steps": 1000000, "max_frames": 1024, "max_calls": 4096, "timeout_ms": 60000, "max_memory": 536870912},
  "outcome": {
    "status": "returned",
    "value": "21",
    "diagnostics": "",
    "output": "",
    "steps": 4
  },
  "reason": null
}
```

The envelope's top-level `status` names the verdict: `ok` for an answer,
`rejected` when the selector or the target's eligibility refused the call,
`invalid-request` for a request failure, `source-rejected` when the target, or a
source it depends on, did not check, and the child-failure verdicts `trap`,
`timeout` and `infrastructure-failure`. A call that ran carries the outcome's
own word for what it did: `returned` for a completed call, and the same `trap`
or `timeout` verdict when the child failed. The `value` is the typed JSON value
of the result — `"21"` is the decimal string of one integer. A refusal replaces
`describe` or `outcome` with `reason`. A refusal that was reached after the
project was checked still names the compiler, tool, source and schema identities
it judged; a refusal decided before that — a request file that cannot be read —
reports empty identity fields, because no snapshot was read to pin.

### Failure spellings

| What happened | Envelope | Exit |
| --- | --- | --- |
| The call ran to a value | `status` `ok`, `outcome.status` `returned` | 0 |
| A budget trap — an exhausted `--max-steps`, for example | `status` `trap`, `outcome.status` `trap`, and `outcome.diagnostics` carrying the located trap code (`R_STEP_LIMIT` for the step budget) | 1 |
| An expired `--timeout-ms` | `status` `timeout`, `outcome.status` `timeout`, `outcome.diagnostics` `Timeout` | 1 |
| The project did not check | `status` `source-rejected` and a `reason`, with no `outcome` | 1 |
| An unknown or ineligible target | `status` `rejected` and a `reason` naming the export or the obstacle | 2 |
| A bad or unreadable request | `status` `invalid-request` and a `reason` | 2 |
| The child died without a usable answer | `status` `infrastructure-failure` | 2 |

## A returned `Err` is a completed call

A language `Result.Err` is a value a call can return, not a failure of the
invocation: a completed call is a completed call whatever its value, so the
envelope's `status` is `ok`, `outcome.status` is `returned`, and the command
exits 0. An `Err` is never reported as a trap, a diagnostic or a refused
request; a runtime trap, an exhausted budget and a request or setup problem are
the failures.

The call ABI of this version carries integers and booleans, so an export whose
*result* is a `Result` is refused by `--describe` at path `result` before it is
called. The rule stays in the contract because it decides the status of every
value a call can return: a completed call is status 0 whatever it carries.

## Exit statuses

| Exit | Meaning |
| --- | --- |
| 0 | A completed call — including a call that returned a language `Result.Err` — or a successful `--describe`. |
| 1 | The target, or a source it depends on, failed to check; or the call trapped or exceeded its time, step, frame or call budget. |
| 2 | A usage error; a `--function` that names no export of this project, or a generic template with no checked instantiation; an export that needs external authority or an unsupported type; a malformed or unreadable request file; or a host/setup failure. |

`--describe` exits 0 for an export it describes as ineligible, because the
description is the answer; the same export invoked with `--input` exits 2.
