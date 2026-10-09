# Checked schema source receipts

Schema generation can now report the exact loaded source identities behind the public
schema:

```sh
zig-out/bin/selka schema-project examples/schema/main.selka --schema-report
```

Without the flag, `schema-project` retains its existing language-schema-v1 output.
With the flag, it emits a `schema-report-v1` envelope after every body has checked.
Source errors produce diagnostics and empty stdout with status 1. Duplicate flags
and use on another command reject as usage errors. No VM/native execution is involved.

## Receipt contents

The envelope contains `schema`, `schema_sha256`, `source`, and `source_sha256`.
Both hashes cover compact JSON in declared field order, without a trailing newline.
The public schema is the same object returned by ordinary schema generation.

The `schema-source-v1` source object records the logical entry, implementation
identity, and every loaded source module once in dependency-first order. Each source
record contains its logical module, relative path, SHA-256 of all loaded bytes, byte
count, and resolved imports with their aliases. Shared dependencies are not repeated.
Comments and private/uncalled declarations are covered by the source hash even when
they do not affect the public schema. Unimported files are outside this receipt.

Implementation identity includes the hash of the running compiler image opened by
the compiler itself, exact Zig version, architecture, OS, ABI, and host optimization
mode. It is not inferred from a filename or version string alone.

Receipts use the project-owned loaded source buffers and their digests. They do not
reopen source paths after checking, so later file edits cannot substitute different
bytes in the report. They identify the bytes actually checked; they do not archive
source contents or claim an atomic filesystem-wide snapshot. Relative paths allow
relocation of an otherwise identical project without changing the receipt.

## Binding generation integration

The Python generator now requests schema receipts and verifies envelope/schema/source
versions and hashes, compiler/source metadata, entry agreement, unique source names,
and dependency ordering before generating or reusing an artifact. Its generation
request includes both the selected launcher executable hash and the compiler image
hash reported by the actual schema process. These can differ for compiler wrappers.

Every `python-bindings-run-v1` report includes fresh `schema_source` and
`schema_source_sha256` fields alongside its schema/artifact/request identities. A warm
artifact hit still checks source and reports the new receipt; it never supplies source
provenance from an older cached run.

Full source identity is deliberately separate from artifact reuse identity. For
example, adding a private comment changes `schema_source_sha256`, while the unchanged
public schema can reuse the same generation request/artifact and preserve the output's
modification time. Changing a public field changes the public schema and invalidates
artifact reuse. Import aliases and order remain visible in the source receipt even
when they do not affect generated data types.

The compiler capture limit now covers the entire schema receipt, including source
metadata. Existing generation deadlines, bounded capture, output limits, atomic writes,
and unchanged-output preservation continue to apply. Both reported compiler-image
identity and selected launcher identity participate in the generation cache key.

## Shared implementation and acceptance

`source_receipt.zig` now supplies source records, implementation metadata, and compact
JSON hashing for both schema and evaluation receipts. Evaluation request/report formats
retain their existing field order and contracts. This keeps the two source-identity
paths consistent without duplicating traversal or formatting logic.

The `schema_report.render` embedding API checks its compilation and returns owned
bytes. Its temporary storage is scoped to a request arena. The source identity helper's
arrays/strings belong to a caller-supplied request arena and borrow project names/paths;
callers must keep both alive while serializing.

`tests/schema_reports.py` independently recomputes source/compiler/schema hashes and
checks byte counts, shared dependencies, relocation, unrelated files, private/public/
alias changes, invalid private bodies, duplicate flags, receipt integrity/dependency
ordering, and fresh source receipts on binding cache hits. A project unit scenario
removes the original provider's files after loading to prove that checking/reporting
uses the owned snapshot, and checks every allocation failure with leak detection.
Existing evaluation receipt/cache and binding codec/cache drivers remain in the full
Debug/ReleaseFast acceptance suite.

This supplies complete loaded-source identity for schema/binding generation. It does
not reuse compiler frontend work or provide declaration-level invalidation decisions.
Finer incremental compilation, source-level codec/input integration, domain codecs,
foreign function wrappers, and the remaining language roadmap work remain pending.
