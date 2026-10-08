# Raw process evidence archives

`archive_raw_processes.py` packages a completed, immutable `processes` directory
without decoding its contents. Use it after the capture process has exited. The
output directory must be fresh, its parent must already exist, and it must be
outside the raw directory.

```sh
python3 archive_raw_processes.py create \
  --raw /absolute/evidence/processes \
  --output /absolute/curated-evidence/raw-archive

python3 archive_raw_processes.py verify \
  --archive /absolute/curated-evidence/raw-archive/raw-processes.tar.gz \
  --index /absolute/curated-evidence/raw-archive/index.json
```

The fresh output contains a gzip tar archive, a readable `index.json` listing
every relative filename, size and SHA256, and `status.json`. Creation succeeds
only after checking the complete inventory, every archived byte against the raw
files, and unchanged input metadata and hashes. The tool rejects symlinks,
special files, traversal paths, duplicate members, missing members, reused
output directories and observed input changes. Verification never extracts
members. Add `--raw /absolute/evidence/processes` to verify against the original
snapshot again; that check includes original inode and metadata identity.

Keep the qualification summary, command journal, compiler/tool manifests and
generated program sources readable beside the archive. Select only `processes`,
not its containing qualification directory. The tool never deletes or writes
the original raw files. A failed creation retains its partial archive and a
`complete: false` status for review. Check both exit status and final status;
archive presence alone is insufficient. Archive verification makes no compiler
qualification claim.

Small checks can be rerun without compiler builds or fuzz execution:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 archive_raw_processes_test.py \
  --evidence /absolute/fresh-helper-test-receipts
```

These checks retain invalid UTF-8 and NUL bytes, a nested member exceeding the
streaming chunk size, an empty directory, malformed and rehashed tampered tar
files, raw subprocess outputs and explicit rejection receipts. Mutation checks
use a fixture-owned worker while creation is active, including unchanged bytes
with the old modification time restored. The unmodified originals remain in
the helper test directory; its `summary.json` only grades the helper checks.
