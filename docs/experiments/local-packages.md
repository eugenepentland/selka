# Offline local packages

Two applications can consume one library checkout through a content-locked local
manifest, without copying library source into either application's tree.

Create `packages.json` beside the application directories:

```json
{"packages":[{"name":"numbers","root":"../shared-numbers"}]}
```

The library root contains `numbers.my` (`module numbers;`) and optionally
`numbers/*.my` (`module numbers.submodule;`). Every library source must use that
namespace. Imports and exports follow ordinary language rules. Run:

```sh
mylang packages lock packages.json --output packages.lock.json
mylang packages build app/main.my --lock packages.lock.json --command run-project --receipt build.json
```

(The first version was the Python script `scripts/packages.py`; `mylang packages`
replaced it on 2026-09-24 with the same lock and receipt formats. See
[local packages](../tooling/packages.md).)

The lock records explicit absolute local roots and every module's SHA-256. Builds
resolve offline, verify all hashes, then compile an isolated temporary snapshot.
Application/dependency collisions, duplicate namespaces (including two versions
of one package), reserved standard modules, symbolic-link source files and source
drift reject before execution. Two versions require explicit distinct source
namespaces; the tool does not silently rewrite module declarations or nominal
types. Changing location requires explicitly regenerating the lock. There is no
network registry, automatic version solving or transport dependency.

Build receipts include lock/compiler identities and the compiler's
source/dependency report, including embedded standard module bytes. A receipt is
written once the snapshot checks, before the command runs; refused builds do not
overwrite one. The snapshot copies bytes into temporary build
storage; shared library source remains in its original checkout. This tool does
not add aliases or re-exports, change core module identity, or supply implicit
filesystem/network runtime grants. A local manifest is trusted build configuration.

The `PACKAGES-LOCK-1` and `PACKAGES-BUILD-1` tests in `test/integration.zig`
verify two independent applications, unchanged app trees, locked drift
rejection, source collisions, duplicate version namespaces, reserved names and
symlink rejection.
