# Scoped directory listing

```sh
zig-out/bin/mylang-io --project examples/standard-directory --allow-dir=/absolute/data/directory
```

The guest checks the granted root's metadata and prints its immediate names through
an owned, bounded listing buffer. Entries are in provider order; names are raw bytes
and may themselves contain newlines. This example is a byte-oriented demonstration,
not a lossless line serialization format. No recursive traversal or write authority
is requested. The provider defaults to at most 256 entries and 64 KiB per snapshot.
