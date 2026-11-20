# Local packages

Two applications can share one library checkout without copying its source and without a registry. A manifest, `packages.json`, names each package and its local root, a lock file pins every file's content hash, and builds resolve offline from that lock. `selka packages` does both halves and needs nothing but the compiler.

## Laying out a package

A package is a folder, its root, that holds `NAME.selka` and, for submodules, a folder `NAME/`. A module's name is its path (a source file has no module header): `NAME.selka` is `NAME`, `NAME/scale.selka` is `NAME.scale`.

The root may hold no other Selka source: `selka packages lock` refuses the first stray `.selka` file with status 2, naming where to move it. Other files (`README.md`, `selka.json`) are not read. A package's tests live inside the folder (`NAME/scale_test.selka`); checkers and examples live outside the root.

```text
shared-numbers/          the package root, named in packages.json
    selka.json          {"version": 1}
    numbers.selka           module numbers
    numbers/
        scale.selka         module numbers.scale
        scale_test.selka    a test of numbers.scale
```

- A module reaches another by its full name: `numbers.selka` writes `import numbers.scale`. `import scale` fails when the snapshot is built (`E_MODULE_READ`).
- A package may import another package listed in the same `packages.json`.
- Run the package's own tests from its root with `selka test numbers`. The `selka.json` holding `{"version": 1}` there makes the root the import root; without it the tests cannot resolve their imports.

## Using a package from an application

An application writes `import numbers` or `import numbers.scale`; no key of its own `selka.json` names the package. Only `selka packages build` supplies it, so you check, run and test through that command (below) and repair through `selka packages fix` ([repairing](#repairing-with-packages)). A plain `selka check`, `selka run` or `selka fix` of the entry answers `E_MODULE_READ: cannot load numbers.selka: there is no numbers.selka under the import root`.

## Local locked packages

`packages.json` lists `{"name": ..., "root": ...}` entries, each root relative to the manifest's directory or absolute. A name is an ASCII identifier that does not start with `std_` (`invalid or reserved package namespace`) and is not a standard module's name (`import strings` always loads the standard one); `lock` refuses both. Every library source must stay inside the package's namespace.

`selka packages lock packages.json --output packages.lock.json` records each root's absolute path and the SHA-256 of every module in a `package-lock-v1` file. `selka packages build app/main.selka --lock packages.lock.json` verifies those hashes, copies the verified bytes (and the nearest `selka.json`) into a private snapshot under `TMPDIR`, and runs one command over it: `check-project` by default, or the `--command` you name: `run-project`, `index-project`, `build` or `test` ([below](#building-and-testing-with-packages)), or `api` ([interface files](#symbolic-links-repeated-warnings-and-interface-files)). The shared checkout is never compiled in place.

The lock is not portable and goes stale at once:

| Cause | Result |
|---|---|
| It holds absolute paths: a copy on another machine, or a moved checkout | `packages: package numbers: cannot resolve root /home/me/shared-numbers: FileNotFound` |
| It holds hashes: any edit of a package source | `packages: locked dependency changed: numbers` |

Lock again before each build that follows a package edit, and do not commit the lock.

These refuse with exit status 2 and a `packages:` line before anything compiles:

- a package whose files changed since locking;
- an application module and a package module with the same path (`duplicate or invalid module path`);
- a namespace locked twice (two versions of one package need two namespaces; there is no version solving);
- a source file whose name starts with `std_`;
- a symbolic link to a folder or to a `.selka` file in a folder the walk reads ([below](#symbolic-links-repeated-warnings-and-interface-files));
- more than 16 MiB of source or 50,000 walked entries.

The command's exit status is forwarded; for `run-project` it is the value `main` returned. `--receipt FILE` writes a `package-build-v1` record (the lock's SHA-256, the compiler's identity, the snapshot's dependency report) once the snapshot checks; a refused build leaves an earlier receipt alone.

```console
$ cat packages.json
{"packages":[{"name":"numbers","root":"shared-numbers"}]}
```

The package's submodule and top module:

```selka
# doc: project packages-example
# doc: file numbers/scale.selka
public func factor() -> int:
    return 21
```

```selka
# doc: project packages-example
# doc: file numbers.selka
# doc: expect 42
import numbers.scale

public func answer() -> int:
    return scale.factor() * 2
```

The application, `app/main.selka`:

```selka
# doc: project packages-example
# doc: file main.selka
import numbers

func main() -> int:
    return numbers.answer()
```

```console
$ selka packages lock packages.json --output packages.lock.json
$ selka packages build app/main.selka --lock packages.lock.json \
    --command run-project --receipt build.json
42
$ echo $?
42
$ echo 'public const duplicate = 0' > app/numbers.selka
$ selka packages build app/main.selka --lock packages.lock.json
packages: duplicate or invalid module path: numbers.selka
$ echo $?
2
```

## Building and testing with packages

`--command build` builds a binary and `--command test` runs tests. Every word after `--` goes to that command: `build` takes `-o BIN` (required), `--release` and its other flags; `test` takes `--filter`, `--json`, `--allow-host` and the rest, and also a directory, as `selka test DIR`. Relative paths resolve where you ran the command. Both link the C of every package the application allows.

A test entry beside the application:

```selka
# doc: project packages-example
# doc: file main_test.selka
import numbers

public func test_answer() -> bool:
    return numbers.answer() == 42
```

```console
$ selka packages build app/main.selka --lock packages.lock.json --command build -- -o app.bin --release
$ ./app.bin; echo $?
42
$ selka packages build app/main_test.selka --lock packages.lock.json --command test
passed main_test::test_answer
1 passed, 0 cached, 0 failed, 0 skipped
$ selka packages build app/main_test.selka --lock packages.lock.json --command test
cached main_test::test_answer
0 passed, 1 cached, 0 failed, 0 skipped
$ selka packages build app --lock packages.lock.json --command test -- --filter answer --json
```

`build` and `test` stage into a directory that stays, one per application directory, so an unchanged snapshot replays the last build and the recorded test passes; a re-locked package rebuilds and re-runs only what reaches it. A test entry's `<stem>.cases.json` is staged beside it.

## Repairing with packages

`selka packages fix ENTRY --lock LOCK` is `selka fix` for a program that imports locked packages. It verifies the lock as `build` does and runs `selka fix` over the staged application with every other switch it was given (`--check`, `--warnings`, `--imports`, `--report`, `--diagnostics=json`, `--no-cache`), under `selka fix`'s rules ([fix](fix.md#selka-fix)): a file run repairs errors only, `--warnings` adds the warnings', a directory repairs both, `--check` writes nothing.

It repairs your files only: a repair that would edit a package's file is set aside whole (`` fix: left 2 fixes in package `rex` alone ``). If you edited one of your files while it ran, nothing is written back and the run exits 2 (`` packages: app/main.selka changed while `selka packages fix` ran ... run it again ``).

```console
$ selka packages fix app/main.selka --lock packages.lock.json --check
$ selka packages fix app/main.selka --lock packages.lock.json --warnings
$ selka packages fix app --lock packages.lock.json
```

A check or build through `selka packages` that printed repairable diagnostics names this command on its last line: `` `selka packages fix app/main.selka --lock packages.lock.json --warnings` repairs 3 of these 3 ``. A diagnostic in a package's file is never counted.

## Program arguments, and only your own tests

The first `--` ends `selka packages build`'s own options, so the program's arguments need a second `--`:

```console
$ selka packages build app/main.selka --lock packages.lock.json --command run-project -- -- 'ing$' file.txt
```

With one `--`, `ing$` is taken for an option of `run-project`, which refuses it with status 2 and shows the corrected line.

`--command test` on a directory runs every test entry under it, packages' included, so choose yours with the filter after the `--`:

```console
$ selka packages build app --lock packages.lock.json --command test -- --filter 'main_test::'
```

When a package holds test modules, a directory run needs a `selka.json` in the application folder (`{"version": 1}` is enough); without one those tests fail with `E_MODULE_READ`. `--no-cache` goes after the `--` too.

## Symbolic links, repeated warnings and interface files

- **Symbolic links.** `build` and `test` walk the folder of the entry (or the directory given) and each package root. They skip a folder whose name begins with `.`, `build`, `zig-out`, `node_modules`, the folder `--cache-dir` names, and a path in `release.exclude` of the project's `selka.json` ([directory runs](guest-tests.md#directory-runs)); a module there is not in the snapshot. In every other folder a symbolic link to a folder stops the run (`packages: symbolic-link directories are rejected: tmp/deep/linkdir`) and a link to a `.selka` file is refused (`symbolic-link sources are rejected`); a link to any other file is fine. Put scratch that holds links in a folder beginning with `.` or in `release.exclude`.
- **Warnings of a package.** A build, check, run or test through `selka packages` does not print the warnings of the package's own sources. Each package with warnings is one line after the diagnostics, `` 2 warnings in package `numbers` are not shown ``. Errors in a package's file are printed, and a project that denies warnings (`lint.warnings: "deny"`) prints the package's when it fails on them. After the `--`, `--warnings` (or `SELKA_WARNINGS=all`) prints every warning in full; `--diagnostics=json` carries every diagnostic and no count line.
- **`"interface_files": true`** in the application's `selka.json` asks for a current `.api` file ([interface files](interface-files.md)) beside each of the application's own modules the command loads, but none for a test module. A package's modules need none, since the lock pins their bytes. `selka api main.selka --write` cannot see the package, so `--command api` writes the files over the snapshot:

  ```console
  $ selka packages build app/main.selka --lock packages.lock.json --command api -- --check
  $ selka packages build app/main.selka --lock packages.lock.json --command api -- --write
  ```

  `--write` copies back the files it wrote or deleted, and refuses, writing none, when one changed since the snapshot was taken. `--check` writes nothing and exits 1 for a file that is missing, stale or orphaned. A package that sets the key in its own root `selka.json` writes its files there with `selka api numbers.selka --write`.

## C sources in a package

A package may list C sources in a `selka.json` at its root (`links`, relative to that file), as a project does ([project links](../c-ffi.md#project-links)). `lock` pins each file's SHA-256, and `build` refuses a package whose files or list changed (`locked dependency changed: NAME (its links)`). The C is used only when the application's `selka.json` names the package in `allow_links`; otherwise `build` stops, naming the line to add:

```console
$ cat shared-sqlite/selka.json
{"version": 1, "links": ["shim.c", "vendor/sqlite3.c"]}
$ selka packages build app/main.selka --lock packages.lock.json --command run-project
packages: package sqlite links C (2 sources in /src/shared-sqlite/selka.json); to build it, add "allow_links": ["sqlite"] to /src/app/selka.json
$ echo '{"version": 1, "allow_links": ["sqlite"]}' > app/selka.json
$ selka packages build app/main.selka --lock packages.lock.json --command run-project
```

The lock pins the listed files, not their headers: a changed header still rebuilds the object but is not reported as drift. `run-project`, `build` and `test` link the application's own `links`, then each allowed package's, in lock order; `check-project` and `index-project` compile no C.

### Devices in a package

A package offers a device as an application describes one ([a device project](native-build.md#a-device-project-one-command)): a `devices` object in the `selka.json` at its root, with paths inside the package. An application chooses it with `"device": "PACKAGE/NAME"` in its own `selka.json` (or `--device PACKAGE/NAME` after the `--`) and allows the package's C with `allow_links`:

```console
$ cat rp2040/selka.json
{"version": 1, "devices": {"ram": {"target": "thumbv6m-none", "linker_script": "device/ram/memmap.ld",
  "links": ["device/ram/platform.c"], "include": ["device/ram"], "image": "bin"}}}
$ cat app/selka.json
{"version": 1, "device": "rp2040/ram", "allow_links": ["rp2040"]}
$ selka packages lock packages.json --output packages.lock.json
$ selka packages build app/blink.selka --lock packages.lock.json --command build -- -o blink.bin
```

- **The lock pins a device's files**: its linker script, its C files and every file under its include folders (so a header a device's C includes belongs under one of them). `build` refuses a package whose device files changed, naming the file (`locked dependency changed: rp2040 (its device ram: device/ram/board.h)`). A lock written before locks recorded devices builds everything that uses no package device; for one that does, `build` says to lock again.
- **A device may describe itself** with `memory`, `place`, `stack`, `boot` and `hooks` ([a device described by its memory](native-build.md#a-device-described-by-its-memory-mcu-noc4a)), checked as an application's are. A hook names `MODULE.FUNCTION` as the application writes the import, so the package's `qemu/board.selka` is `qemu.board`, and the application must import it (`import qemu.board`) or the build refuses the hook with `E_DEVICE_HOOK`. A device that names no file holds no C, so the application needs no `allow_links` for it:

  ```console
  $ cat qemu/selka.json
  {"version": 1, "devices": {"virt": {"target": "thumbv6m-none",
    "memory": {"boot": ["0x0", "1K"], "ram": ["0x20000000", "264K"]},
    "place": {"vectors": "boot", "code": "ram"}, "stack": "16K",
    "hooks": {"start": "qemu.board.start", "write": "qemu.board.write", "exit": "qemu.board.finish"}}}}
  $ cat app/selka.json
  {"version": 1, "device": "qemu/virt"}
  $ selka packages lock packages.json --output packages.lock.json
  $ selka packages build app/main.selka --lock packages.lock.json --command build -- -o app.elf
  ```

  The lock records the description as the file spells it, and `build` refuses a package whose description changed, naming the key (`locked dependency changed: qemu (its device virt: the stack key)`); a key's order counts. A lock written before descriptions were recorded names the first key it lacks.
- **A device that names files** needs `"allow_links": ["PACKAGE"]`, or the build stops first and names the line to add. `selka build F.selka` alone refuses a package's device with one line that names `selka packages build`.
- **No path leaves its folder**, by its spelling or through a symbolic link; the refusal names the real location.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/packages.md).
