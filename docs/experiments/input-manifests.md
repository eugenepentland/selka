# Typed input manifest generation

`input-module` validates a declared JSON input manifest and writes a deterministic
module to stdout. The example manifest and generated module are checked in together:

```sh
zig build
zig-out/bin/mylang input-module examples/input-values/inputs.json
zig-out/bin/mylang eval-project examples/input-values/main.my
```

The project returns 64 through config.values.batch_size and config.values.enabled.
This establishes explicit input validation and generation. Evaluation does not yet
load JSON manifests automatically: it reads the generated .my file as an ordinary
import. Changing the JSON alone therefore does not update execution or cache identity;
regeneration is required. Automatic manifest loading and stale-generation protection
remain pending integration work.

## Format

A version-1 document has exactly version, module, and values fields. Each values entry
has exactly name, type, and value. The module is a dotted logical name. Each input name
is a non-keyword ASCII identifier and is exported as a parameter-free typed function.
Supported types are bool and signed/unsigned 8-, 16-, 32-, and 64-bit integers.

Values are strings: canonical decimal for integers, and "true" or "false" for bool.
This preserves u64/i64 precision independently of a JSON consumer's numeric storage.
Signs, leading zeros, negative zero, whitespace, nondecimal spellings, and text that
could inject source tokens are rejected except the minus sign on a valid negative
integer. Width bounds are checked before any source is generated. Duplicate input
names (after JSON decoding), duplicate JSON keys, unknown fields/types, reserved
keywords, malformed paths, and unsupported versions reject the manifest.

Limits are 1 MiB of manifest bytes, 1,024 inputs, 256 bytes for the module name, and
128 bytes per input name. These bound the manifest/generator stage, not whole compiler
memory. Errors print the manifest path and an error category, exit 2, and produce no
partial generated stdout. Host allocation failure remains a host error. The command
writes no files and requires no runtime capabilities.

## Generated representation and provenance

All exports precede function declarations, preserving input declaration order. Return
literals retain their declared integer widths. The generated source uses the ordinary
module grammar, visibility/type rules, and canonical formatter. Neither the source
nor its consumers need an untyped lookup dictionary or a runtime JSON parser.

The first source comment records SHA-256 of the complete manifest bytes, including
JSON formatting. After regeneration, even a manifest-only formatting edit changes
the generated source digest. Current evaluation reports/caches record that generated
source as a dependency. They do not yet record or reread the original JSON file;
the embedded hash is provenance of generation, not proof that generation is fresh.
The embedding Manifest parser owns decoded strings and exposes caller-owned output.

## Acceptance

Unit tests cover canonical formatting, full allocation-failure cleanup, invalid names,
modules, types, values/ranges, versions, and duplicates. The actual CLI driver generates
and evaluates imported values at every supported integer width's extrema and both
boolean values. It independently checks the embedded manifest hash and deterministic
output, and rejects duplicate/unknown JSON fields, numeric JSON values, path traversal,
duplicate names, excess input count, and excess manifest bytes. Debug and ReleaseFast
run the driver in zig build test. Schema derivation from language records, general
serialization/bindings, automatic declared-input loading, and finer incremental
compilation remain pending.
