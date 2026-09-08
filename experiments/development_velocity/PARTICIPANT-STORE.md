# Matched development workflow, declaration-store session

Read TASK.md and PROCESS.md with the `asset` verb. Implement the requested
behavior in the application declarations. The process transport, public documents
and input contract are protected. Standard-library preparation is complete before
timing. Use the supplied libraries; report a missing general-purpose prerequisite
instead of quietly implementing a parser, general map/sorter, codec or path
library.

All inspection, editing and execution must use the invocation-only participant
bridge given by the coordinator. In this arm the bridge has no command tool and
no shell: there are no files, paths, directories or line numbers. Source is a set
of declarations addressed by qualified name, `module::name`. The verbs are

```text
open    {}                                     modules, declarations, readable documents, budgets
context {"ids":["app::run"],"budget":8192}     source, hash, callers, callees, types, reaching tests
        1..16 ids; budget 1024..32768, default 8192
search  {"text":...} | {"type":...} | {"calls":...} | {"effect":...}, optional {"limit":N}
asset   {"name":"TASK.md","offset":0,"limit":4096}      limit 1..8192
batch   {"ops":[...],"if_match":{"app::run":"HASH"}}    1..32 operations
probe   {"request":<json>}
check   {}
output  {"record":N,"offset":0,"limit":8192}
finish  {"reason":"completed"}                 or {"reason":"abandoned"}
await-handoff {}                               only between practice and the timed task
```

Do not inspect the bridge source, hidden packs, prior solutions, timing reports,
other participants or coordinator material. Do not use network access, other
agents, alternate runtimes to implement `.my` behavior, or coordinator code as an
application dependency.

`.my` applications use `app::run(heap, doc, request) -> std_bytes::Built`. Return
one JSON result. The supplied transport catches the defined application
validation errors as `invalid-request`. Use explicit semantic error objects for
errors named differently in TASK.md. Validate an entire request before state
transitions or semantic error reporting.

## Batch operations

Edits are transactional batches. These four are every operation shape there is;
copy one and edit it:

```json
{"op":"replace","id":"app::run","source":"fn run(heap: allocator, doc: &[]i64, request: j::Node) -> b::Built { ... }"}
{"op":"add","module":"app","source":"fn helper(value: i64) -> i64 { return value; }"}
{"op":"add","module":"app","source":"fn later(value: i64) -> i64 { return value; }","after":"helper","exported":true}
{"op":"remove","id":"app::helper"}
```

`replace` takes exactly `op`, `id`, `source`. `add` takes exactly `op`, `module`,
`source` and the optional `after` (place it behind that sibling instead of at the
module's end) and `exported`. `remove` takes exactly `op`, `id`. Any unexpected or
missing field rejects the batch, and the rejection states the accepted fields.

`replace` and `remove` need an `if_match` entry holding the declaration's current
hash, which `context` returns, so an edit is always preceded by a read; `add`
needs no `if_match` entry. A replacement or addition is exactly one top-level
declaration, and `replace` keeps the declaration's name and exported flag, so a
rename is an `add` and a `remove`. A batch is rejected whole on any if-match
mismatch, protected declaration, unknown name or parse failure, and the branch is
then untouched. It commits on parse rather than on check, so type and ownership
errors never lose work; the response reports the check delta as `new` and
`resolved` diagnostics keyed by declaration. Declarations of the protected
transport modules are readable but not writable, exactly as the protected files
are in the files arm.

## Declaration shapes

A top-level declaration is exactly one of these kinds:

```text
alias  const  pool  buffer  resource  result  enum  union  domain  struct  fn  host_fn
```

```text
struct Point { x: i64, y: i64 }             a product type; fields are name: type, comma separated
enum Mode { fast, slow }                    a closed set of named variants
result Parsed { ok: i64, err: i64 }         success and failure payload types
fn add(a: i64, b: i64) -> i64 { return a + b; }        parameters and return type are declared
const LIMIT: i64 = 8;                       an immutable module-level value
type Count = i64;                           an `alias` declaration
host fn put(value: u8) -> i64 effects(host);           a `host_fn` declaration
```

There is **no** `record` keyword. Casts are written `cast<T>(x)`; neither `T(x)`
nor `x as T` is a cast. Imports are derived from the declarations you write, so
`helper::multiply(argument)` is enough to import `helper` and **no import
statement is ever written**; two aliases that derive the same import are refused.
`export name;` is recorded as the declaration's exported flag, not written text.

## Running, checking and finishing

`probe` runs the application on one request of your choosing against the current
branch and returns its stdout, stderr and status. The bridge `check` renders the
branch, captures it as the submission and runs the complete public pack with
identical expected outputs across arms. It is the required declared verification
workload. Write targeted local tests as declarations when useful; do not change
or skip the required public checks. A committed batch is not a passing check.

Use `finish` with reason `completed` after checking the final branch; the last
check must cover your last edit. Failed checks, attempts and timings are all
retained; a fast failure is not a speed win. Completion does not reveal hidden
results. If unable to finish, seal with reason `abandoned`. During practice,
`finish` returns `ready`; then call `await-handoff` with `{}`, in the same
context, until it answers `phase: "working"`, and follow its message. Onboarding
practice must have committed one `add` and one `remove`, besides its repairs,
before `finish` accepts `completed`. Practice and preparation stay outside
application delivery time; the application clock starts at the coordinator's
`begin`, and only the poll's return latency, at most 0.5 s, falls inside it.

Every request and response is retained whole outside the source. Responses are
bounded: `open`, `context`, `search` and `asset` to 8 KiB, `batch`, `probe` and
`check` to 16 KiB, and `context` accepts a `budget` up to 32768. A response that
did not fit reports `response_truncated` with the exact `output` request that
pages the retained original, and every trimmed response reports what it omitted.
Each response carries its own `record` number; `output` pages that record. Record
numbers start at zero and include rejected requests and retrievals. Practice uses
a separate onboarding session and its own record numbers. `output` reads only
your previous responses; it cannot reveal private tests or another participant.
No verb returns a filesystem path, and none reads the rendered snapshot the
coordinator checks.
