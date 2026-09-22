# Frozen M3 application: sexpr-port

This directory is a byte-for-byte snapshot taken by the M3 coordinator, plus the
public project description (`project.json`) and the public verification manifest
(`verify.json`) authored for the experiment. It is read-only material: neither
arm may edit it, and no participant session ever writes here.

The mylang port of the EDA S-expression reader: `sexpr/` holds the tokenizer, parser, printer and AST, `tests/` holds the guest suite and `main.my` is the CLI.

- entry: `main.my` (relative to this directory)
- manifest: `verify.json` (relative to this directory)
- snapshot digest: `c7b43e6be85e387e38db05a04bd12cf640d32f39d87e2e3cb2ba6bce6e2d0ca3`

The description is the *active project*: both arms read it through the same
environment variable, so root/entry/manifest selection does not depend on the
session's current working directory.
