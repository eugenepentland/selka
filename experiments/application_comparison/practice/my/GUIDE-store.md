# .my practice guide, declaration-store session

Repair this small byte-input utility according to the supplied practice contract
and public checks. Fix the unresolved-name diagnostic first: static checking can
reject the whole project before any input branch runs.

There are no files, paths, directories or shell commands in this session. Source
is a set of declarations addressed by qualified name, `module::name`, and the
session verbs are the only way to reach it:

```text
open    {}                              the modules, every declaration and every readable document
context {"ids":["main::answer"],"budget":8192}   canonical source, the hash if_match needs, callers, callees, types
search  {"text":"multiply"}             up to 20 hits; or {"type":T} {"calls":ID} {"effect":E}, optional {"limit":N}
asset   {"name":"CONTRACT.md","offset":0,"limit":4096}   one page of a document
batch   {"ops":[...],"if_match":{"main::answer":"HASH"}}  one transactional edit
probe   {"request":<json>}              run the application on an input of your choosing
check   {}                              the complete public practice cases
output  {"record":N,"offset":0,"limit":4096}   page a prior response of this session
finish  {"reason":"completed"}          end this phase; "abandoned" is the other reason
```

Every response carries its own `record` number; `output` pages that record when a
response did not fit its budget. Read `GUIDE.md` and `CONTRACT.md` with `asset`.

**Repairs are made through `batch`.** A batch is all-or-nothing, and takes 1..32
operations. These four are every shape there is; copy one and edit it:

```json
{"op":"replace","id":"main::answer","source":"fn answer() -> i64 effects(host) { ... }"}
{"op":"add","module":"helper","source":"fn double(value: i64) -> i64 { return value * 2; }"}
{"op":"add","module":"helper","source":"fn triple(value: i64) -> i64 { return value * 3; }","after":"double","exported":true}
{"op":"remove","id":"helper::double"}
```

`replace` takes exactly `op`, `id`, `source`. `add` takes exactly `op`, `module`,
`source` and the optional `after` (place it behind that sibling instead of at the
end) and `exported`. `remove` takes exactly `op`, `id`. Any other field, or a
missing one, rejects the batch.

`replace` and `remove` require an `if_match` entry giving that declaration's
current hash, which `context` returns; an edit is therefore always preceded by a
read. `add` needs no `if_match` entry. A replacement or addition is exactly one
top-level declaration, and a replacement keeps the name and exported flag of the
declaration it replaces, so a rename is an `add` and a `remove`. The batch commits
when it parses, so type and ownership errors do not lose work: the response returns
the check delta as `new` and `resolved` diagnostics keyed by declaration, never by
file or line. Use `check` for the complete public practice cases; a committed batch
is not a passing check.

**Practise `add` and `remove` before you finish.** Add one small helper
declaration to `helper`, confirm with `open` that it is listed, remove it again,
and confirm with `open` that it is gone. Onboarding is not complete until each of
the two has committed once, alongside the `replace` operations the repairs need.

## The language, in the shapes a declaration takes

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
nor `x as T` is a cast. Qualified references derive imports, so writing
`helper::multiply(argument)` is enough to import `helper` and **no import
statement is ever written**; two aliases that derive the same import are refused.

`module name;` names a module. `export multiply;` is recorded as the
declaration's exported flag, not as text you write. `let name = value;` creates an
immutable binding. Names must resolve in their scope; the diagnostic names the
declaration that needs repair.

This exercise's parser returns the `result` type `ParsedDigit`; `new
ParsedDigit.ok(value)` and `new ParsedDigit.err(error)` construct its variants. An
exhaustive `match` handles both. `discard` explicitly ignores an unneeded error
payload, but the failure branch must still return the result required by the
utility contract.

The `io` module exposes only raw byte count, indexed reads, and byte writes.
`effects(host)` declares and propagates these external effects. Byte literals use
the `u8` suffix; `cast<i64>(value)` explicitly widens a byte for arithmetic.
`discard io::put(...)` acknowledges the host's status value. Returning zero from
`main` commits the buffered output; it is the process status, not the answer.

`probe` feeds one request to the application on the current branch and returns
its output, exit status and stderr. It is the store session's equivalent of
running the program on an input you choose; it is not the public check.
