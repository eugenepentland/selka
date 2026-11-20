# Declared inputs for schemas and calls

`schema-project`, `check-value-project`, and `invoke-project` now accept the same
repeated `--inputs=manifest.json` option as `eval-project`. Each invocation reads
and validates up to 16 distinct manifest paths, generates their modules in memory,
and checks the project against those owned source buffers. Existing module/import,
manifest, duplicate-module, entry-conflict, and unused-input checks remain in force.
No generated module is written to disk; in-memory inputs take precedence over stale
files at the generated module paths.

The Python binding generator accepts repeated `--inputs` options (or `build`'s
`inputs` keyword). It forwards the selection during fresh checked schema derivation.
Generated-source comments contain each complete manifest's digest; schema source
receipts therefore change when manifest content changes, including formatting.
The reusable binding artifact remains keyed by public schema and generator/compiler
identity. An input value change can reuse the artifact while producing a fresh
source receipt. An input type/export change that alters the schema regenerates it.
Output and cache writes cannot replace one of the selected manifests.

Generated `Client` accepts `inputs=(path, ...)`. It resolves and copies the path
selection at construction, then forwards those paths on every call. Values are read
afresh by the compiler; they are not embedded in the generated Python module or
captured when the client is constructed. Path lists are bounded and duplicates are
rejected before spawning a process.

```python
client = generated.Client(compiler, entry, inputs=('config.json',))
result = client.call('main::calculate')
```

The public schema pin still applies before argument decoding or target execution.
Changing only a configured value can deliberately change a call's result; changing
its declared type can invalidate the generated schema. The compiler's source receipt
records the loaded snapshot used for generation, rather than a later reread. Calls
currently return their typed result envelope without an additional execution receipt.
This feature does not introduce hidden environment reads, native ABI inputs, source
serialization operators, or general incremental frontend compilation.

`tests/call_inputs.py` checks generation without on-disk modules, fresh call results,
changed receipts with artifact reuse, schema invalidation, copied path selections,
malformed/duplicate inputs, and preservation of manifest files. The CLI regression
root separately checks schema input loading and fresh malformed-manifest rejection.
Existing input-manifest tests retain scalar boundaries and module-conflict coverage.
