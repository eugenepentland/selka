# mount-routing

Version: 1. Family: filesystem-path. Kind: feature. Tier: medium.

Request: {"mounts":[{"prefix":PATH,"target":PATH}],
"paths":[PATH,...]}; at most 32 mounts, with unique prefixes. PATH has exactly
the same normalized ASCII grammar as snapshot-diff: / or slash-separated
[a-z0-9_.-]{1,32} components, excluding . and .., no repeated/trailing slashes,
at most 256 bytes. A prefix matches its exact path or descendants separated by
/, with / matching all paths. Choose the longest matching prefix. Replace it
with target and join the remaining suffix with exactly one slash. Exact matches
produce target; no match produces null. Return {"paths":[PATH-or-null]} in
input order. Result length may exceed 256 (up to 512); do not revalidate it as
an input. No host filesystem or symlink resolution.

Apply the shared PROCESS.md transport, type, schema and validation rules.
