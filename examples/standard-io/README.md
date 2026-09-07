# Bounded file reader

Place notes.txt in a directory you choose to grant, then run:

```sh
zig-out/bin/mylang-io --project examples/standard-io --allow-dir=/absolute/data/directory
```

The guest reads at most 4096 bytes through std_fs/read_to_end and publishes the
contents through the explicit io host. A larger file or failed open returns a
nonzero guest status and no buffered stdout is published. The file handle and
partial buffers are released on every path. No writing authority is requested.
