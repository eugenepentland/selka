# Local packages

Two applications can share one library checkout without copying its source into
either tree, and without a network registry. A small manifest names each package
and its local root, a lock file pins every file's content hash, and builds resolve
entirely offline from that lock. The design record is
[offline local packages](../experiments/local-packages.md).

## Local locked packages

`packages.json` lists `{"name": ..., "root": ...}` entries; the library root holds
`<name>.my` declaring `module <name>` and optionally `<name>/*.my` declaring
`module <name>.submodule`, and every library source must stay inside that
namespace. `scripts/packages.py lock` records each package's explicit absolute
root and the SHA-256 of every module into a `package-lock-v1` file.
`scripts/packages.py build` then verifies all of those hashes, copies the bytes
into an isolated temporary snapshot and runs one compiler command over it, so the
shared checkout is never compiled in place and the application tree stays
unchanged. Source drift, application and dependency collisions, duplicate
namespaces — including two versions of one package — reserved standard module
names and symbolic-link sources all reject before anything executes. Two versions
therefore need two distinct source namespaces: the tool never rewrites a module
declaration, there is no version solving, and moving a checkout means
regenerating the lock. A successful `--receipt` records the lock and compiler
identities together with the compiler's own source and dependency report; a
failed build leaves the previous receipt alone.

```console
$ cat packages.json
{"packages":[{"name":"numbers","root":"shared-numbers"}]}
$ python3 scripts/packages.py lock packages.json --output packages.lock.json
$ python3 scripts/packages.py build app/main.my --lock packages.lock.json \
    --compiler zig-out/bin/mylang --command run-project --receipt build.json
42
```
