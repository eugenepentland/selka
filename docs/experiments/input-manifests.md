# Typed input manifest generation

`input-module` validates a declared JSON input manifest and writes a deterministic
module to stdout. The example manifest and generated module are checked in together:

```sh
zig build
zig-out/bin/mylang input-module examples/input-values/inputs.json
zig-out/bin/mylang eval-project examples/input-values/main.my
```

The project returns 64 through config.values.batch_size and config.values.enabled.
Use `eval-project --inputs=examples/input-values/inputs.json` to load the manifest
and generate its module in memory for that invocation. The evaluation cache driver
accepts the same `--inputs` option. [Schemas and calls](call-inputs.md) also accept
these manifests, including binding generation and generated Python clients. Generated files on disk are no longer required
for this workflow; the compiler does not write or update them.

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
the generated source digest. Evaluation reports/caches record that generated source as a dependency. With
--inputs, every request/evaluation reads the manifest afresh and regenerates the
source. The exact JSON content hash in its provenance comment therefore participates
in the source/request identity. The JSON filesystem path is not separately included
in the receipt; identical manifest content supplying the same logical module can
share an identity across locations. Explicit disk generation still requires its
caller to regenerate after edits.
The embedding Manifest parser owns decoded strings and exposes caller-owned output.

## Acceptance

Unit tests cover canonical formatting, full allocation-failure cleanup, invalid names,
modules, types, values/ranges, versions, and duplicates. The actual CLI driver generates
and evaluates imported values at every supported integer width's extrema and both
boolean values. It independently checks the embedded manifest hash and deterministic
output, and rejects duplicate/unknown JSON fields, numeric JSON values, path traversal,
duplicate names, excess input count, and excess manifest bytes. Debug and ReleaseFast
run the driver in zig build test. Schema derivation from language records, general
serialization/bindings, broader input types, and finer incremental
compilation remain pending.

## Automatic evaluation inputs and freshness

Up to 16 --inputs=manifest.json bindings are supported per eval-project invocation, including
request-only and successful-report modes. Paths to manifests are interpreted from the
working directory. The manifest supplies an imported logical module through the
existing bounded module provider. That explicit binding takes precedence over a disk
file at the same logical module path, including a stale or invalid generated file.
No physical directory or generated file is required. The generated source retains
normal module/type/effect checking and source-budget accounting.

The entry module cannot be replaced by a manifest. Every manifest whose module is absent
from the reachable import graph is rejected as unused. Duplicate-path/empty bindings and
bindings supplied to other compiler commands reject as usage errors. Generation and
manifest validation complete before loading the project; the retained in-memory
snapshot remains owned through checking/evaluation. Source diagnostics for generated
code use its logical .my path.

The cache driver forwards --inputs to both request lookup and executed evaluation.
Editing a manifest automatically changes its generated source identity and causes a
miss; an unchanged manifest can hit. A change between those two snapshots is covered
by the existing request/report identity comparison. Cache hits still read, validate,
and generate the current declared inputs before lookup, preventing reuse based on a
stale disk-generated copy.

Acceptance now also exercises in-memory loading over invalid disk content, absent
files/directories, manifest value edits, generated-source receipt hashes, duplicate
bindings, entry replacement/unused-manifest rejection, and real cached input changes
followed by a warm hit. Existing disk contents remain unchanged in these tests.

## Multiple manifest boundaries

Repeat --inputs for distinct imported modules. Duplicate logical module bindings
reject even when their manifests have different filenames or identical values; there
is no first-wins or last-wins ambiguity. Literal duplicate manifest paths reject as
usage errors, while alternate paths to the same logical module are detected after
parsing. The compiler reports both conflicting manifest paths. Each declared module
must be used by the reachable graph, and entry replacement remains forbidden.

The invocation permits at most 16 manifests and 8 MiB of combined manifest bytes,
while retaining the 1 MiB per-file limit and 1,024 values per manifest. Generated
sources also count toward the existing project module/source budgets. The cache
driver forwards every repeated binding to both request and execution. Valid binding
flag order does not affect request identity: source/import order comes from the
project graph, and each generated module retains its own manifest content hash.

Acceptance executes 16 generated input modules, rejects a 17th binding, rejects two
files naming the same module, compares full request documents under reversed binding
flags, accepts eight exact-1-MiB manifests, and rejects a ninth. Cache tests change
each of two manifests independently and verify refreshed values; reversing unchanged
bindings still hits the same cache entry.

The boundary tests also verify an exact-4-MiB ordinary source module and rejection
of one extra byte. Manifest and module file readers account for the pinned Zig
reader's exclusive limit so the documented byte budgets are inclusive.
