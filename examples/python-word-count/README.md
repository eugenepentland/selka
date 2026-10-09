This example counts space-separated words with managed strings, dictionaries,
and list iteration. Strings and dictionary keys compare by value; the GC owns
the storage.

```sh
zig-out/bin/selka run-project examples/python-word-count/main.selka
```

A successful run returns `42`. `histogram` is the reusable function; its input
and result have ordinary type annotations.
