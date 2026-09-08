# snapshot-diff

Version: 1. Family: filesystem-path. Kind: feature. Tier: medium.

Request: {"before":[ENTRY,...],"after":[ENTRY,...]} where
ENTRY is exactly {"path":PATH,"digest":ID}. Each side has unique paths;
duplicate paths are invalid even if digests agree. Return {"added":[PATH],
"removed":[PATH],"changed":[PATH]}, each sorted ASCII, for paths present only
after, only before, or on both sides with unequal digest. Input order is ignored.
PATH is / or an absolute slash-separated sequence of components matching
[a-z0-9_.-]{1,32}, except . and .. are forbidden components. No empty component,
trailing slash except /, or repeated slash. Total length is at most 256 bytes.
Paths are virtual names; digests are opaque IDs, not hashes to compute.

Apply the shared PROCESS.md transport, type, schema and validation rules.
