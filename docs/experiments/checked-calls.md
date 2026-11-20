# Schema-pinned public JSON calls

invoke-project calls an explicitly exported function or public domain method after
checking the complete loaded project and matching the caller's expected public
schema. This is the executable request boundary for generated callable bindings;
it is not a native ABI or generated wrapper implementation.

```sh
zig-out/bin/mylang invoke-project path/to/main.my --request=request.json
```

A request has exactly these fields:

```json
{
  "version": "typed-call-v1",
  "schema_sha256": "<lowercase SHA-256 of the compact checked public schema>",
  "function": "data::Positive.from_wire",
  "arguments": {"x": {"n": "7"}}
}
```

A complete request for the checked-in example can be generated and run with:

```sh
python3 - <<'PYTHON'
import hashlib, json, pathlib, subprocess
compiler = 'zig-out/bin/mylang'
entry = 'examples/domain-codecs/main.my'
schema = subprocess.check_output([compiler, 'schema-project', entry]).rstrip(b'\n')
request = {
    'version': 'typed-call-v1',
    'schema_sha256': hashlib.sha256(schema).hexdigest(),
    'function': 'data::Positive.from_wire',
    'arguments': {'x': {'n': '7'}},
}
pathlib.Path('zig-out/call.json').write_text(json.dumps(request))
subprocess.run([compiler, 'invoke-project', entry, '--request=zig-out/call.json'], check=True)
PYTHON
```

The schema digest hashes schema-project's exact compact JSON document, excluding
any trailing newline. It matches the existing generated Python SCHEMA_SHA256
identity for the checked public schema. Argument keys are source parameter names;
values use those parameters' typed JSON representations, including explicit domain
wire representations. Arguments are decoded in parameter declaration order,
independent of JSON key order. Missing, extra, repeated, or incorrectly typed fields
reject; the request does not accept additional top-level fields or versions.

For the [domain codec example](../../examples/domain-codecs/main.my), the request
above returns a typed-json-v1 envelope for data::Decoded, with its ok case carrying
{"n":"7"}. The caller must fill in the schema digest from that checked project.
A decoder rejection while materializing an argument is an invocation failure;
a typed err result returned by the requested function is successful output data.
Foreign callers remain responsible for interpreting result cases.

## Checks and execution

The loaded compilation owns the source buffers used for schema derivation and
execution. No path is reread between the identity check and the call. The schema
pin covers the complete exported interface, including nominal types, parameter
names/modes, result types, codec contracts, and effects. It does not pin source
implementation bytes. A body-only change with an unchanged public schema executes
the freshly checked implementation; an added or changed public contract rejects
an old request with InvocationSchemaMismatch. Finer dependency identities and
optional implementation pins remain separate work.

Only exported functions/public methods can be selected. Before decoding any
argument, preflight rejects effectful call graphs, reference parameters/returns,
and complete parameter/result graphs without JSON representations. Unselected
variants and zero-length arrays cannot hide unavailable domain codecs or runtime
owners/authorities. The VM still validates the selected invocation, receives no
injected capabilities, and copies arguments across the allocator boundary.

Invocation uses the [shared JSON operation budgets](domain-json.md). The same
--max-codec-steps, --max-codec-frames, --max-codec-calls, --max-codec-bytes, and
--max-codec-values options apply to invoke-project. The requested target counts as
one VM invocation attempt alongside argument decoders and result encoders; source
calls inside each VM invocation are bounded by guest steps and frames. Counters do
not restart between argument decoding, target execution, and result encoding.
Per-direction value limits cover all arguments together, then the result. The
shared work limit covers both. Input bytes/tokens cover the entire request.

Memory accounting includes request parsing and fresh schema rendering, as well as
decoded arguments, invocation copies/bookkeeping, results, and output serialization.
Temporary schema text is freed after its digest is checked. Compiler/source storage
remains outside runtime accounting, and guest instruction counts do not measure
schema rendering or other host work. The request envelope has two container levels
before an argument value; typed wire depth limits retain their meaning and support
the full embedding limit of 128 levels.

Argument failures have pointers such as /arguments/x/n. Schema mismatches point to
/schema_sha256; target selection/signature/execution failures point to /function;
result encoding failures point inside /value. A target trap uses InvocationTrap and
retains its source trace. Domain decoder/encoder traps retain DomainCodecTrap and
the domain occurrence's path. Failure values and diagnostic lifetimes follow the
same rules as codec_json, including rejection ownership and reuse protection.

The CLI writes one typed-json-v1 envelope on success, no result on failure, and
existing source/operation diagnostics to stderr. Source/request/runtime failures
exit 1; usage, I/O, or host allocation failures use the existing exit-2 convention.

## Embedding and acceptance

codec_json.invokeProject exposes the same operation in Zig. Compilation.publicFunction
shares export selection with invokePublic, avoiding an intermediate export list.
The existing main execution and standalone typed JSON APIs retain their behavior.

Acceptance covers independent schema hash computation, named/reordered arguments,
domain input/output, returned typed errors versus decoder rejection, zero-argument
and maximum-u64 calls, exact shared budgets, memory and allocation failures,
visibility/effect/reference rejection before argument execution, stale signatures,
fresh body changes, private invalid source, malformed requests, byte/depth boundaries,
and source/path diagnostics. Allocation failure injection includes compilation,
request creation/parsing, schema rendering, decoding, invocation, and encoding.

Generated callable wrappers, Python domain wire representations, source serialization
operations, native ABI integration, richer input integration, and other unfinished
roadmap work remain pending. This boundary supports the checked JSON-representable
function shapes; it does not make effectful or reference-bearing functions foreign
callable or establish source-level result obligations in a host language.
