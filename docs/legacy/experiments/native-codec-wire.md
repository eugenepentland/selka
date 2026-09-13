# Native domain codec wire API
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

`mylang_native_call_codecs_v1` in `src/native_embed.h` accepts exported functions
whose complete input/output shapes have ordinary values or declared domain codecs.
The older `mylang_native_call_values_v1` continues to reject domain signatures.
Resources, capability parameters and references remain outside both value APIs.

A domain is a preorder node with its exact schema name, zero bits and one child:
its declared ordinary wire representation. Input conversion calls the checked
decoder before the public function. Returned domains call their encoder and retain
the resulting wire tree. Domains can appear inside records, arrays and variants.
A host cannot directly supply the domain's backing integer.

The runtime prepares output in bounded scratch storage before copying any nodes
to the caller. Each returned domain invokes its encoder once, including when the
caller's output buffer is too small. `OutputTooSmall` reports the required node
count and leaves output unchanged. Other execution failures also leave it unchanged.
Input and output each retain the 100000-node and 128-level wire limits.

`MylangCodecOptions` combines ordinary step/frame/provider options with a call
quota. Zero selects 4096 calls. Implicit decoders, the public root and implicit
encoders each count once; their internal helper calls share instruction/frame
limits. Exhaustion returns `CodecCallLimit`. A failure during domain conversion
retains that domain's name in `MylangCodecResult.domain`.

An implicit decoder rejection returns status 2, code `DomainCodecRejected`,
`rejected=1`, and the ordinary typed rejection tree in output. Its type is the
schema codec's `error_type`. If the rejection tree exceeds output capacity,
`OutputTooSmall` retains the rejection flag, domain and required count. Calling a
decoder explicitly as the public function can successfully return a language
`err` value; that is not an implicit conversion failure.

## Acceptance

`tests/native_codec_wire.py` runs four address/undefined-behavior sanitizer hosts
(-O0/-O2, packed scalar and boxed record rejections), plus four independent hosts
linked against generated shared libraries using the public headers. It checks a
decoder that doubles input and an encoder that adds one, nested record/array/union
conversion, malformed domain nodes, old-API opacity, exact call quotas, shared
step/frame limits, decoder/encoder traps and encoder source frames, unchanged
insufficient output, typed rejections and explicit decoder results. Allocation
failure sweeps cover successful and rejected calls, assert no live allocations,
and verify subsequent recovery. The driver is wired into `zig build test`.

Generated `NativeClient` now consumes this API for domain-bearing signatures,
including typed rejection trees and shared call limits; see
[native-bindings.md](native-bindings.md). Ordinary signatures retain the older
value API and can use libraries without the codec symbol.
