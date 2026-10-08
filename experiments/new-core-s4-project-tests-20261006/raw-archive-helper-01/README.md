# Archive helper checks, run 01

Eight local tests passed, with zero failures or errors. `summary.json` and
`tests.log` grade the archive helper only. No compiler, conformance or fuzz gate
ran. `commands/command-00325.log` retains the exact selftest invocation; the
source bytes and hashes are in `source-freeze/`.

The original fixture directory remains untouched in the M worktree at
`.mylang-cache/s4-m/raw-archive-selftest-01`. Each curated test directory has a
`fixture-raw-archive` containing its raw file bytes, readable member index and
successful byte verification status. The mutation tests deliberately changed
their own originals before curation; their earlier rejection receipts and
`complete: false` creation statuses remain separate. All fixture symlinks and
FIFO paths were rejected; `curation.json` records their descriptors instead of
adding live unsafe filesystem entries to this evidence directory.

`curation.json` records the unchanged hashes of the five frozen qualification
sources. Summary files, CLI argv/status records, raw stdout/stderr, malformed
archive fixtures, indices, command journals and the sample generated program
remain readable outside the raw fixture archives.

Run the adjacent `archive_raw_processes_test.py` with a fresh `--evidence`
directory to reproduce the checks. Use `archive_raw_processes.py verify` with
each archive and its index to check the curated bytes independently. Both tools
explicitly refrain from claiming compiler qualification.
