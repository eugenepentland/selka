# Source domain codec operations

Source expressions can invoke a domain's declared codec without depending on its
method names:

```mylang
match codec_decode<Positive>(new Wire { n: 7 }) {
    Decoded.ok(value) => { return codec_encode<Positive>(value).n; },
    Decoded.err(error) => { return error; }
}
```

`codec_decode<Domain>(wire)` returns the exact result type of the declared decoder.
`codec_encode<Domain>(value)` returns the declared ordinary wire type. Both take
one explicit nominal domain type and one value argument. Imported aliases work,
for example `codec_decode<units::Distance>(wire)`. The names `codec_encode` and
`codec_decode` are reserved keywords. The formatter preserves their syntax.

Resolution selects methods named by the `codec` declaration and produces ordinary
checked calls. Public method visibility, exact parameter/result types, ordinary
wire/error graphs and transitive effect-free codec validation still apply. The VM
and generated native code execute the selected methods with normal call/frame/step
accounting and source traces. A rejected decode is an ordinary typed result, so
existing result-handling obligations apply. Encoding cannot accept a raw backing
integer, and decoding cannot construct a domain without a declared codec.

## Acceptance and remaining work

Zig tests cover execution, nonstandard method names with nontrivial transformations,
explicit rejection handling, missing contracts, wrong types/arity, formatter
round trips, imported alias resolution and allocation-failure cleanup. The shared
VM/native parity driver includes an imported codec-operation fixture.

These operations convert between a domain and its declared typed wire value.
They do not parse or emit JSON bytes. Source byte serialization still needs a
bounded buffer/slice API with explicit allocation authority and typed malformed
input errors. Generic codec constraints remain unimplemented; abstract generic
bodies using these operations receive `E_GENERIC_BODY_UNSUPPORTED` rather than
assuming that an arbitrary copyable type has a codec.
