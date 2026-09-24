# Generated standalone Python data bindings

Status: removed. `scripts/bindings.py` is gone, and its example consumer
`examples/schema/use_bindings.py` was deleted on 2026-09-24 because nothing
could generate the module it imports. This page is the design record.

The generator derives Python data types and a typed JSON codec from a freshly
checked public language schema:

```sh
zig build
mkdir -p zig-out/bindings
python3 scripts/bindings.py examples/schema/main.my \
  --output zig-out/bindings/message_bindings.py
PYTHONPATH=zig-out/bindings python3 examples/schema/use_bindings.py
```

`--compiler` selects an explicit compiler executable; the default is this checkout's
`zig-out/bin/mylang`. There is no pre-generated schema input option: every invocation
runs `schema-project`, including checking all private/uncalled source bodies.

The output is one standalone Python module. It imports only Python standard-library
modules and embeds its schema and codec implementation; running it requires neither
Zig, the compiler, this repository, nor a separately installed runtime package for
data operations. [Generated calls](python-calls.md) additionally require an explicitly
selected compiler and source project. It uses
Python 3.10+ features, including dataclass slots. Acceptance was executed with the
installed Python 3.14.4 interpreter.

## Python value model

| Checked language shape | Generated Python representation |
| --- | --- |
| Integer / boolean | `int` / `bool`, with exact type and integer-range validation at codec boundaries |
| Record | Distinct annotated, frozen, slotted dataclass |
| Closed enum | Distinct `Enum` with case-name string values |
| Tagged union / result | Distinct base class and one frozen, slotted dataclass per case; payload cases have an annotated `value` field |
| Fixed array | Tuple with checked length and recursively checked elements |
| Enum-indexed table | Mapping from the generated enum to element values; decoding returns a read-only mapping |

The public registries make source identities explicit:

```python
from message_bindings import CASES, TYPES, dumps, loads

Header = TYPES['message::Header']
Status = TYPES['message::Status']
Reading = CASES['message::Message']['reading']
message = Reading(Header(f_sequence=7, f_status=Status.v_ready))
text = dumps(message)
assert loads(text, expected_type='message::Message') == message
```

`TYPES` maps qualified nominal names to classes. `CASES[type][case]` maps variant
names to constructors. `FIELDS[type][field]` maps language record fields to Python
attributes. These registries are read-only. `TYPE_NAMES` includes all available
implicit-codec types, including scalars and structural arrays/tables.

Every generated class has a deterministic Python identifier beginning `T_`.
Every record field begins `f_`; enum members begin `v_`. ASCII letters/digits remain
literal, while other UTF-8 bytes become `_xHH`, including underscores. Because the
escape character is itself escaped, source names cannot collide after conversion.
For example, field `record` becomes `f_class`, and `f_x` becomes `f_f_x5fx`. Module
qualification remains part of class identities. Clients may directly import the
emitted class names for static annotations, or use registry aliases as above.

Forward annotations preserve records, variants, array elements, and table key/value
types even when definitions appear later in the generated file. Constructors are
ordinary Python constructors: annotations/frozen fields do not validate all supplied
values. `dumps` validates the complete value before emitting a document, including
rejecting Python `bool` in integer positions and a structurally similar instance of
a different nominal class. Decoded arrays/tables use immutable containers; caller-
constructed objects can still contain mutable mappings, which are validated when
serialized. Python does not statically enforce the language's result-handling rules.

## Wire compatibility and bounds

`loads(str_or_utf8_bytes, expected_type=None, limits=Limits())` consumes
[typed-json-v1](typed-json.md) and returns native generated values. An optional expected
type rejects a mismatched nominal root. `dumps(value, type_name=None, limits=Limits())`
returns canonical JSON without modifying the value. Nominal roots infer their type
from their exact generated class; scalar and structural roots require `type_name`.

The codec uses decimal strings for wire integers, case names for enums, complete
record/table objects, and explicit case/value variant objects. It rejects duplicate
decoded keys, unknown keys/cases, missing fields, wrong types/ranges/shapes, unsupported
versions, and invalid Unicode. Both directions preserve declaration ordering and
produce the same canonical bytes as the compiler for supported values.

`Limits` mirrors the compiler defaults: 1 MiB inclusive bytes, 65,536 typed value
nodes, 262,144 scanner tokens/fragments, and 64 typed value levels. Positive depth
limits up to 128 are allowed. Before Python's JSON DOM parser runs, a scanner checks
nesting, UTF-16 escapes, and the pinned complete-input Zig scanner's token/fragment
accounting. Encoding collects JSON output chunks only while they fit its byte limit.
The limits bound size/work, not total interpreter memory or elapsed execution time.

Failures raise `CodecError`, a `ValueError` subclass with `code` and `path`. Typed
value failures carry JSON-pointer paths where available; raw syntax/duplicate-key
errors do not necessarily have a nested path. Unknown types and explicitly unsupported
types remain distinguishable.

`UNSUPPORTED_TYPES` lists domains, capabilities, owners/resources/handles, and all
ordinary types containing unsupported dependencies. This propagates through every
variant arm and array element, even when an arm is unselected or an array is empty.
Generation can still produce bindings for independent ordinary types in that project;
unsupported types do not receive constructible binding classes or implicit codecs.

These are data bindings. The generator does not create callable FFI wrappers for
exported functions or supply private domain factories. [Executed domain codecs](domain-json.md) and [schema-pinned public JSON calls](checked-calls.md)
are now implemented in the compiler. Generated callable wrappers, Python domain wire
representations, native ABI integration, and source-level codec operations remain
separate work.

## Generation identity, failure behavior, and limits

The generated module embeds `BINDINGS_VERSION`, `SCHEMA_SHA256`, and
`GENERATOR_SHA256`. The schema hash covers the compact checked schema, including its
public function metadata. The generator hash covers generator-file bytes, a separator,
and the runtime template bytes read during generation. The `python-bindings-run-v1` stdout report includes those hashes, the final output
hash/size, supported type count, unsupported type names, and generation/cache/installation
status. [Incremental artifact reuse](binding-cache.md) now records the full generation
request and supports an optional persistent cache.

Generation is deterministic for those inputs and independent of checkout paths.
Import aliases/order, comments, and private changes leave the generated artifact
unchanged when the public schema is unchanged. A public schema change regenerates
new classes/metadata. The optional cache adds compiler/Python/output-limit identities and fresh schema
checking. It reuses generated artifacts; it is not frontend incremental compilation.
[Checked source receipts](schema-receipts.md) now record all loaded module identities
and the actual compiler image alongside the public schema, including on cache hits.

Defaults are a 90-second compiler subprocess deadline, 16 MiB combined captured
schema/diagnostics, and 16 MiB final generated output. Flags `--timeout`,
`--max-schema-bytes`, and `--max-output-bytes` configure positive limits. Captures go
to temporary files and their size is polled; file growth can overshoot between polls.
Timed-out or oversized compiler children are terminated and reaped. These controls
do not establish a strict total memory/disk quota for the entire generation pipeline.

The generated source is compiled for syntax before output installation. Installation
uses a temporary file in the destination directory, flush/fsync, and atomic replace. Exact byte matches now skip installation to preserve modification
times, with or without a cache. The parent directory must already exist. Compiler, schema, generation, and write
failures preserve an existing destination and clean up the temporary output. The
entry, compiler, and generator files cannot be selected as output. Source rejection
exits 1; host/configuration/generation failure exits 2. Success exits 0.

## Acceptance and remaining work

`tests/python_bindings.py` executes 29 compiler/Python wire comparisons per host
compiler build mode, including every integer-width boundary, booleans, records,
enums, arrays, tables, unions/results, and the default value-count boundary. It also
checks independently constructed Python values, nominal confusion, keyword/special
field names, immutable decoded containers, duplicate/invalid data, Unicode, custom
budgets, expected root types, isolated standalone imports, stable generation after
private edits, regeneration after public changes, existing-file preservation, atomic
write failure cleanup, and termination/reaping after time/capture limits.

The driver is part of `zig build test` in Debug and ReleaseFast. Python callable wrappers and explicit domain wire support are delivered by the
subsequent [Python calls milestone](python-calls.md). Other language bindings, native
ABI integration, broader incremental compilation, and the remaining roadmap are open.
