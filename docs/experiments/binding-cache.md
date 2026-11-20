# Incremental binding artifact reuse

Python binding generation can reuse a previously validated artifact after checking
the current source project:

```sh
mkdir -p zig-out/bindings
python3 scripts/bindings.py examples/schema/main.my \
  --output zig-out/bindings/message_bindings.py \
  --cache-dir .mylang-cache/bindings
```

Every invocation runs `schema-project` before cache lookup. Invalid private or
uncalled source bodies still reject even when an old artifact exists. Cache hits
skip Python source generation; they do not skip the compiler frontend. Cached source
is checked for Python syntax without executing it.

## Request and artifact identities

The `python-bindings-request-v1` object records:

- The complete returned public schema's compact JSON SHA-256.
- Generator/runtime content identity, captured once for the invocation and shared
  by request construction and source generation.
- SHA-256 of the actual compiler image reported in the checked schema receipt.
- SHA-256 of the selected compiler executable. Its bytes are read before and after
  schema checking; a detected change rejects generation for a retry.
- Python implementation, full version, bytecode cache tag, and optimization setting.
- The generated-output byte limit.

The cache key is SHA-256 over compact JSON in request field order. Output paths,
source checkout paths, and cache directories are not key fields. Compiler timeout
and capture limits apply freshly before lookup; they do not affect an already
returned schema or the generated artifact and are not part of the key. Changing
an output limit conservatively creates a different request.

An artifact is stored as `<request-sha256>.json` under the explicitly supplied cache
directory. Its versioned envelope contains the full request, generated source,
generation report, and a checksum over that payload. Lookup compares the complete
request, verifies checksums, source length/hash, report identities and metadata,
checks output limits, and compiles the cached source for syntax before reuse.
Reads are bounded by twelve times the output byte limit plus 64 KiB to accommodate
JSON escaping and duplicated report metadata. This is an envelope-read bound, not a
process-wide allocation quota.

A missing entry is a miss. Malformed, mismatched, corrupt, or syntactically invalid
entries are regenerated and replaced atomically after successful generation. Other
filesystem failures remain host errors. The cache is trusted local build storage;
checksums detect accidental corruption rather than authenticate a hostile replacement.

Only successfully generated/syntax-checked artifacts are stored. Cache installation
precedes destination installation, so a valid cached artifact can remain if writing
the destination subsequently fails. Failed source checking/generation never supplies
an artifact. The destination cannot replace its own cache entry.

## Downstream rebuild behavior

Before installing either a generated or cached artifact, the driver compares the
existing destination's complete bytes with the desired output. An exact match skips
installation, preserving inode and modification time. This also applies with the
cache disabled. A missing or stale destination is installed atomically, including
from a cache hit; timestamps alone are never accepted as evidence of freshness.

The `python-bindings-run-v1` stdout report includes the request and its hash, fresh
[schema source receipts](schema-receipts.md), artifact identities, `frontend: checked`, cache status/reason, actual generation execution/skip,
and `installation: unchanged|replaced`. Private implementation changes may retain the
same schema and produce a cache hit. A different compiler or limit may cause a miss
while producing identical bytes, in which case destination installation still skips.

Cache misses write a same-directory temporary cache file, flush/fsync it, and atomically
replace the entry. Destination installation retains the same atomic behavior. A cache
write failure stops before destination replacement. Existing generated output is
preserved on failure and temporary files are removed. Concurrent identical writers
may independently generate the same request; no shared generation lock is claimed.

## Acceptance and scope

`tests/binding_cache.py` spies on actual compiler checking and generation calls to
verify cold execution and warm skips. It checks inode/mtime preservation, deleted/stale
output restoration from a hit, malformed/checksum/report/request/syntax corruption
repair, output-limit changes, runtime edits, compiler wrapper changes, detected compiler
replacement during checking, public schema changes, rejection of invalid private
bodies, disabled-cache no-op installation, and cache-write failure cleanup.

The driver runs in Debug and ReleaseFast with the existing generated-binding wire
parity and compiler suites. These observations establish actual generation skips and
avoided file rewrites, not a measured end-to-end performance improvement. Full loaded-source receipts are now implemented as described above. Frontend/
declaration-granular reuse, cache eviction, and broader incremental compilation remain
separate work.
