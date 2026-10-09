# Local packages

Two applications can share one library checkout without copying its source into
either tree, and without a network registry. A small manifest names each package
and its local root, a lock file pins every file's content hash, and builds resolve
entirely offline from that lock. `selka packages` does both halves; it needs
nothing but the compiler. The design record is
[offline local packages](../experiments/local-packages.md).

## Local locked packages

`packages.json` lists `{"name": ..., "root": ...}` entries, each root relative to
the manifest's directory or absolute. The library root holds `<name>.selka`
declaring `module <name>` and optionally `<name>/*.selka` declaring
`module <name>.submodule`, and every library source must stay inside that
namespace. A name is an ASCII identifier that does not start with `std_`, which
the standard modules own.

`selka packages lock packages.json --output packages.lock.json` resolves each
root to an absolute path and records it with the SHA-256 of every module in a
`package-lock-v1` file. `selka packages build app/main.selka --lock
packages.lock.json` then inventories the entry's directory and every locked
root again, verifies all of those hashes, copies the verified bytes (and the
nearest `selka.json`, with its import policy when it sits beside the entry)
into a private directory under `TMPDIR`, and runs `project-dependencies` and one
project command over that snapshot: `check-project` by default, or the one
`--command` names (`run-project` or `index-project`). The
shared checkout is never compiled in place, the application tree stays
unchanged, and the snapshot is deleted afterwards.

These refuse with exit status 2 and a `packages:` line, before anything
compiles: a package whose files changed since locking, an application module
and a package module with the same path, a namespace locked twice (two versions
of one package need two distinct namespaces: nothing rewrites a module
declaration and there is no version solving), a module named like a standard
one, a symbolic-link source or directory, and more than 16 MiB of source or
50,000 walked entries. Moving a checkout means regenerating the lock.

The command's exit status is forwarded: for `run-project`, which runs with
`--print-result`, that is the program's own status, the value `main` returned.
`--receipt FILE` writes a `package-build-v1` record of the lock's SHA-256, the
compiler's identity and the snapshot's dependency report as soon as the snapshot
checks, before the command runs; a refused build leaves an earlier receipt
alone.

```console
$ cat packages.json
{"packages":[{"name":"numbers","root":"shared-numbers"}]}
$ cat shared-numbers/numbers.selka
module numbers


public func answer() -> int:
    return 42
$ cat app/main.selka
module main
import numbers

func main() -> int:
    return numbers.answer()
$ selka packages lock packages.json --output packages.lock.json
$ selka packages build app/main.selka --lock packages.lock.json \
    --command run-project --receipt build.json
42
$ echo $?
42
$ echo 'module numbers' > app/numbers.selka
$ selka packages build app/main.selka --lock packages.lock.json
packages: duplicate or invalid module path: numbers.selka
$ echo $?
2
```

The command replaced `scripts/packages.py`, a Python prototype, with the same
lock and receipt formats. Two things changed: `build` no longer takes
`--compiler`, because the compiler that runs it is the one it uses (the receipt
records its identity, and the snapshot's dependency report must carry the same
one), and the receipt is written once the snapshot checks rather than only when
the command exits 0, since `run-project` now exits with the program's value.
