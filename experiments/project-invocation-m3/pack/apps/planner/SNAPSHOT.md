# Frozen M3 application: planner

This directory is a byte-for-byte snapshot taken by the M3 coordinator, plus the
public project description (`project.json`) and the public verification manifest
(`verify.json`) authored for the experiment. It is read-only material: neither
arm may edit it, and no participant session ever writes here.

The workflow dependency planner: `main.my` plus json/schema/planner/output modules, driven as a byte-I/O program that reads one JSON request on stdin and writes one response on stdout.

- entry: `main.my` (relative to this directory)
- manifest: `verify.json` (relative to this directory)
- snapshot digest: `b1795b992bdc724067f8061e256fb38602abce52e2c18e7e548703cf4de042e3`

The description is the *active project*: both arms read it through the same
environment variable, so root/entry/manifest selection does not depend on the
session's current working directory.
