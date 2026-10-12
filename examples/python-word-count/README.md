This example counts space-separated words with managed strings, dictionaries,
and list iteration. Strings and dictionary keys compare by value. Iteration
borrows each split word; `word.copy()` gives the dictionary its own key storage.

```sh
zig-out/bin/mylang run-project examples/python-word-count/main.my
```

A successful run returns `42`. `histogram` is the reusable function; its input
borrows and its result owns independent storage, with ordinary type annotations.
