# Local packages

Two applications can share one library checkout without copying its source into
either tree, and without a network registry. A small manifest names each package
and its local root, a lock file pins every file's content hash, and builds resolve
entirely offline from that lock. `selka packages` does both halves; it needs
nothing but the compiler. (The design record, `docs/experiments/local-packages.md`,
lives in the compiler's repository and is not a `selka docs` page.)

## Laying out a package

A package is a folder, its root, that holds `NAME.selka` and, for submodules, a folder
`NAME/`. A module's name is its path (a source file has no module header):
`NAME.selka` is `NAME`, `NAME/scale.selka` is `NAME.scale`, `NAME/units/si.selka` is
`NAME.units.si`. The root may hold no other Selka source, tests, examples and
checkers included: `selka packages lock` refuses the first stray `.selka` file with
`packages: package numbers: shared-numbers/numbers_test.selka is neither numbers.selka nor under numbers/`,
then where to move it (`shared-numbers/numbers/numbers_test.selka`) and the import it becomes
(`import numbers.numbers_test`), exit status 2, whatever other `selka.json` sits beside it. Files of other kinds
(`README.md`, `selka.json`) are not read. A test of the package therefore lives
inside the folder, as `NAME/scale_test.selka`, and the checkers and examples live
outside the root.

```text
shared-numbers/          the package root, named in packages.json
    selka.json          {"version": 1}
    numbers.selka           module numbers
    numbers/
        scale.selka         module numbers.scale
        scale_test.selka    a test of numbers.scale
```

A module of the package reaches another by its full name: `numbers.selka` writes
`import numbers.scale`, as an application does. `import scale` is not found when the
snapshot is built (`E_MODULE_READ: cannot load scale.selka`), though `lock` accepts the
file. A package may import another package the same way (`import other`), when both
are listed in the same `packages.json`; a package that imports `other` without it
being locked fails to build.

The package's own tests run from its root with `selka test numbers`: the
`selka.json` holding `{"version": 1}` there makes the root the import root, so that
`import numbers.scale` in `numbers/scale_test.selka` is found. Without that file a test
in the folder cannot resolve its imports.

## Using a package from an application

An application writes `import numbers` for the package's top module and
`import numbers.scale` for a submodule: no path and no key of its own `selka.json`
names the package. Only `selka packages build` supplies it, so the application is
checked, run and tested through that command (below), and repaired through
`selka packages fix` ([repairing](#repairing-with-packages)). A plain `selka check main.selka`,
`selka run main.selka` or `selka fix main.selka` does not know the package and answers
`E_MODULE_READ: cannot load numbers.selka: there is no numbers.selka under the import root`.
An application module whose path equals a package module's is refused
(`duplicate or invalid module path`). A package name must not start with `std_`
(`invalid or reserved package namespace`) and must not be the name of a standard
module either: `import strings` always means the standard module, so a package called `strings`
would never be used. `lock` refuses it, and `build` refuses a lock written before with the same words:
`` packages: package strings is named like the standard module `strings`, which `import strings` always loads: the package's `strings.selka` would never be used. Rename the package (its namespace and its `strings.selka` and `strings/` files) and lock again ``.

## Local locked packages

`packages.json` lists `{"name": ..., "root": ...}` entries, each root relative to
the manifest's directory or absolute. The library root holds `<name>.selka` and
optionally `<name>/...`, and every library source must stay inside that
namespace. A name is an ASCII identifier that does not start with `std_`, which
the standard modules own.

`selka packages lock packages.json --output packages.lock.json` resolves each
root to an absolute path and records it with the SHA-256 of every module in a
`package-lock-v1` file (`"root": "/home/me/shared-numbers"`). The lock is not
portable and goes stale at once: it holds absolute paths, so a copy made on another
machine, or after the checkout moved, fails with `packages: package numbers: cannot
resolve root /home/me/shared-numbers: FileNotFound`; and it holds hashes, so any
edit of a package source makes `build` stop with `packages: locked dependency
changed: numbers`, until `lock` is run again. Write the lock again before each build
that follows an edit of a package, and do not commit it as if it were the same on
every machine. `selka packages build app/main.selka --lock
packages.lock.json` then inventories the entry's directory and every locked
root again, verifies all of those hashes, copies the verified bytes (and the
nearest `selka.json`, with its import policy when it sits beside the entry)
into a private directory under `TMPDIR`, and runs `project-dependencies` and one
project command over that snapshot: `check-project` by default, or the one
`--command` names (`run-project`, `index-project`, or `build` and `test`, which
[build a binary and run tests](#building-and-testing-with-packages), or `api`, which
[writes the application's interface files](#symbolic-links-repeated-warnings-and-interface-files)). The
shared checkout is never compiled in place, the application tree stays
unchanged, and the snapshot is deleted afterwards.

These refuse with exit status 2 and a `packages:` line, before anything
compiles: a package whose files changed since locking, an application module
and a package module with the same path, a namespace locked twice (two versions
of one package need two distinct namespaces: nothing rewrites a module
declaration and there is no version solving), a source file whose name starts
with `std_`, a symbolic link to a folder or to a `.selka` file in a folder of the application or of a package root
that the walk reads ([below](#symbolic-links-repeated-warnings-and-interface-files)),
and more than 16 MiB of source or 50,000 walked entries. Moving a checkout means
regenerating the lock.

The command's exit status is forwarded: for `run-project`, which runs with
`--print-result`, that is the program's own status, the value `main` returned.
`--receipt FILE` writes a `package-build-v1` record of the lock's SHA-256, the
compiler's identity and the snapshot's dependency report as soon as the snapshot
checks, before the command runs; a refused build leaves an earlier receipt
alone.

```console
$ cat packages.json
{"packages":[{"name":"numbers","root":"shared-numbers"}]}
```

The package's `shared-numbers/numbers.selka` publishes the helper, built from its own
submodule `shared-numbers/numbers/scale.selka`:

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

The application's `app/main.selka` imports it:

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

`--command build` builds the snapshot into a binary, and `--command test` runs its tests. Every word after `--` goes to
the command after the staged entry, so `build` takes `-o BIN` (required), `--release`, `--report`, `--cache-dir DIR` and
its other flags, and `test` takes `--filter`, `--json`, `--allow-host` and the rest; relative paths among them resolve
where the command was run. `test` also takes a directory, and runs every entry under it as `selka test DIR` would. Both
link the C of every package the application allows, as `run-project` does, and the lock is checked first: a package
whose files changed since locking is refused with the same `packages: locked dependency changed: NAME` line, before
anything is built or run.

A test entry beside the application imports the package as `main.selka` does:

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

Unlike the other commands, `build` and `test` stage into a directory that stays: one per application directory, at
`packages-v1/<digest of its path>` under `$XDG_CACHE_HOME/selka` (or `~/.cache/selka`), with a lock file beside it
that one run holds until its command ends. Each run rewrites only the files whose bytes changed and removes every file
the snapshot no longer holds, so the build and test caches, which name sources by path and digest, see an unchanged
snapshot as unchanged: the build replays its last identical build and the tests replay their recorded passes. A
changed package (locked again) changes its staged module's bytes, so the binary is built again and the tests that reach
it run again; no new cache key is involved. A test entry's `<stem>.cases.json` is staged beside it. `test` runs no
`project-dependencies`, since a test entry needs no `main` and a directory has no one entry, so its receipt records
`"dependencies": null`.

## Repairing with packages

`selka packages fix ENTRY --lock LOCK` is `selka fix` for a program that imports locked packages. It verifies the lock
as `build` does (a package whose files changed is refused with the same `packages: locked dependency changed: NAME`),
stages the application and the packages into a private directory, and runs `selka fix` there with every other switch
it was given: `--check`, `--warnings`, `--imports`, `--report`, `--diagnostics=json`, `--no-cache`. It follows
`selka fix`'s rules ([fix](fix.md#selka-fix)): a file run repairs errors only, `--warnings` adds the warnings', a
directory (`selka packages fix app --lock LOCK`) repairs both, `--check` writes nothing and lists what it would change,
and the rounds and the summary are `fix`'s, with your own paths in them.

It repairs your files only. A repair that would edit a file of a package is set aside whole, as `fix` sets aside one
in a generated file, and the summary says how many it left and where, in one line:
`` fix: left 2 fixes in package `rex` alone: `selka packages fix` never writes a package's files ``. The package's
warnings are counted as `build` counts them (`` 2 warnings in package `rex` are not shown ``). When the run ends, each
of your files that `fix` changed is written back, and only those; each must still hold the bytes it was staged from.
If you edited one while the run was going, nothing at all is written and the run exits 2 with
`` packages: app/main.selka changed while `selka packages fix` ran, so none of its repairs were written back; run it again ``.

```console
$ selka packages fix app/main.selka --lock packages.lock.json --check
$ selka packages fix app/main.selka --lock packages.lock.json --warnings
$ selka packages fix app --lock packages.lock.json
```

A check or build through `selka packages` that printed diagnostics with a repair names this command on its last line,
with the entry and the lock as you gave them: `` `selka packages fix app/main.selka --lock packages.lock.json --warnings`
repairs 3 of these 3 ``. A diagnostic in a package's file is never in the first number.

## Program arguments, and only your own tests

`selka packages build` takes the first `--` as the end of its own options: every word
after it goes to the command, here `run-project`, as one of that command's options.
The program's own arguments therefore need a second `--`:

```console
$ selka packages build app/main.selka --lock packages.lock.json --command run-project -- -- 'ing$' file.txt
```

With one `--`, `ing$` is taken for an option of `run-project`, which refuses it: the run
ends with exit status 2 and a message that names the word and shows the same line with
the second `--` (`... --command run-project -- -- 'ing$' file.txt`). A real usage error of
the command, such as an option given twice, prints that command's usage instead
(`usage: selka run <file.selka> [options] [-- ARGS...]`). The program sees `'ing$'` and
`file.txt` in `args`.

`--command test` on an entry file (`app/main_test.selka`) runs that file's tests. On a
directory (`app`) it runs every test entry under it, and the staged copy holds the
packages too, so the tests of each package run with yours (`rex.inner_test::test_base`
scrolls past before `main_test::test_answer`). Choose yours with the filter of
`selka test`, which goes after the `--`:

```console
$ selka packages build app --lock packages.lock.json --command test -- --filter 'main_test::'
```

A directory run needs a `selka.json` in the application folder (`{"version": 1}` is
enough) when a package holds test modules: without one the package's tests cannot
resolve their imports, the run reports them as failed with an `E_MODULE_READ` for a
module of the package, and the other tests still run. `--no-cache` goes
after the `--` as well, to run tests that are recorded as passed again.

## Symbolic links, repeated warnings and interface files

- **Symbolic links.** `build` and `test` walk the folder of the entry (or the directory they were given), and a package root,
  in every folder but the ones `selka test DIR` leaves out, by one rule: a folder whose name begins with `.` (`.git`, `.zig-cache`
  and the default cache folder `.selka-cache` among them), `build`, `zig-out` and `node_modules`, at any depth beneath the folder named (which is walked whatever it is called); the folder
  `--cache-dir` names among the words after `--`; and a path in `release.exclude` of the project's `selka.json`
  ([directory runs](guest-tests.md#directory-runs)). Nothing in those is read, staged or looked at for links, and a module there is
  not part of the snapshot, so a program that imports one cannot be built through `packages`. `tmp/` and every other folder are
  walked: a symbolic link to a folder in one of them stops the run, `packages: symbolic-link directories are rejected:
  tmp/deep/linkdir`; a link to a `.selka` file is refused as `symbolic-link sources are rejected`. A link to any other file is not.
  Scratch that holds links (a test fixture of a program that follows links) belongs in a folder whose name begins with `.`, such as
  `.tmp/`, or in `release.exclude`, as it does for a directory run. Links above the entry's folder are not walked.
- **Warnings of a package.** A build, check, run or test through `selka packages` does not print the warnings of
  the package's own sources, which the application's author cannot change: each package with warnings is one line
  after the diagnostics, `` 2 warnings in package `numbers` are not shown `` (`` 1 warning in package `numbers` is not shown ``
  for one). Its closing line names `selka packages fix` with your entry and lock, never `selka fix` (which does not
  know the package: in the application's own folder it reports `E_MODULE_READ`) or the private snapshot it ran in, and
  counts your own repairs only ([repairing](#repairing-with-packages)). A program with an error stops at the
  snapshot's dependency check, which prints the error and no such line. A build that replays prints the same lines as
  the one it replays. An
  error in a package's file is printed and stops the command as before, and a project that denies warnings
  (`lint.warnings: "deny"`) prints the package's too when it fails on them, since they are why it failed. After the
  `--`, `--warnings` (or `SELKA_WARNINGS=all`) prints every warning in full, the package's among them (as the snapshot
  names the file, `rex/parse.selka:5:8`), and `--diagnostics=json` carries every diagnostic and has no count line. The
  package's own check, `selka check .` in its root, prints its warnings and its `selka fix` line as it always did.
- **`"interface_files": true`** in the application's `selka.json` asks for a current `.api` file
  ([interface files](interface-files.md)) beside each of the application's own modules that the command loads, and none
  for a test module (`main_test.selka` needs no `main_test.api`: it exports only `test_` functions that nobody imports). The
  snapshot holds the `.api` files that sit beside the application's sources, so a build, run, check or test through
  `packages` finds them. A package's modules need none: the lock pins their bytes, and the application's author cannot
  write files into a package. `selka api main.selka --write` in the application's folder cannot write the files of an
  application that imports a package, since it cannot see the package; `--command api` does it over the snapshot:

  ```console
  $ selka packages build app/main.selka --lock packages.lock.json --command api -- --check
  $ selka packages build app/main.selka --lock packages.lock.json --command api -- --write
  ```

  `--write` copies back the interface files it wrote, changed or deleted beside the application's sources, and refuses,
  writing none, when one of them changed since the snapshot was taken; `--check` writes nothing and exits 1 for a file that
  is missing, stale or orphaned. A build that finds one missing or stale says the same command
  (`` run `selka packages build app/main.selka --lock packages.lock.json --command api -- --write` and review its diff ``),
  never `selka api` of the private snapshot. A package that sets the key in the `selka.json` of its own root writes its files
  there, with `selka api numbers.selka --write`, as any project does.

## C sources in a package

A package may list C sources in a `selka.json` at its root (`links`, each relative to that file), as a project does
([project links](../c-ffi.md#project-links)). `lock` pins each listed file's SHA-256 in the package's entry
(`"links": [{"path": ..., "sha256": ...}]`), and `build` refuses a package whose listed files or list changed since
(`locked dependency changed: NAME (its links)`). The C is used only when the application's own `selka.json` names the
package in `allow_links`; otherwise `build` stops before anything compiles, naming the package and the line to add:

```console
$ cat shared-sqlite/selka.json
{"version": 1, "links": ["shim.c", "vendor/sqlite3.c"]}
$ selka packages build app/main.selka --lock packages.lock.json --command run-project
packages: package sqlite links C (2 sources in /src/shared-sqlite/selka.json); to build it, add "allow_links": ["sqlite"] to /src/app/selka.json
$ echo '{"version": 1, "allow_links": ["sqlite"]}' > app/selka.json
$ selka packages build app/main.selka --lock packages.lock.json --command run-project
```

Allowing a package's C runs nothing at build time beyond compiling the listed files, in place and with the headers they
include from the package's checkout. The lock pins the listed files only, not the headers they include: a changed header
still rebuilds the object (the foreign cache keys every header by its bytes), but `build` does not report it as drift. `run-project`, `build` and `test` link the application's own `links`, then each allowed package's, in
lock order; `check-project` and `index-project` compile no C. The staged copy of the application's `selka.json` leaves
out `links` and `allow_links`, since the staging directory holds none of the C.

### Devices in a package

A package offers a device the way an application describes one ([a device project](native-build.md#a-device-project-one-command)):
a `devices` object in the `selka.json` at its root, its paths relative to that file and inside the package. An
application chooses it with `"device": "PACKAGE/NAME"` in its own `selka.json` (or `--device PACKAGE/NAME` after the
`--`), allows the package's C with `allow_links`, and builds it with no other flag:

```console
$ cat rp2040/selka.json
{"version": 1, "devices": {"ram": {"target": "thumbv6m-none", "linker_script": "device/ram/memmap.ld",
  "links": ["device/ram/platform.c"], "include": ["device/ram"], "image": "bin"}}}
$ cat app/selka.json
{"version": 1, "device": "rp2040/ram", "allow_links": ["rp2040"]}
$ selka packages lock packages.json --output packages.lock.json
$ selka packages build app/blink.selka --lock packages.lock.json --command build -- -o blink.bin
```

- **The lock pins a device's files.** `lock` records, in the package's entry, each device's files with their SHA-256
  (`"devices": {"ram": [{"path": "device/ram/memmap.ld", "sha256": ...}, ...]}`): its linker script, its C files and every
  file under its include folders, so a header that a device's C includes belongs under one of them. `build` refuses a
  package whose device files changed since, naming the file (`locked dependency changed: rp2040 (its device ram:
  device/ram/board.h)`), as it refuses changed `links`. A lock written before locks recorded devices still builds
  everything that uses no package device; a build for one is refused with `run \`selka packages lock\` again`.
- **A device may describe itself** instead of naming a script and C: `memory`, `place`, `stack`, `boot` and `hooks` are the keys of
  [a device described by its memory](native-build.md#a-device-described-by-its-memory-mcu-noc4a), read and checked as an
  application's are (`lock` refuses a description a project's `selka.json` would refuse, naming the file and the device). They
  hold no path and need no file: a region name and a `boot` stage name stand alone. A hook names `MODULE.FUNCTION` as the
  *application* writes the import, so the package's module `qemu/board.selka` is `qemu.board`, and the application imports it
  (`import qemu.board`) or the build refuses the hook with `E_DEVICE_HOOK`, as for an application's own device. A device that
  names no file holds no C, so the application needs no `allow_links` for it:

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

  The lock records the description as the file spells it, beside the files (`"device_descriptions": {"virt": {"memory":
  {...}, "stack": "16K", "hooks": {...}}}`, present only when a device has one), and `build` refuses a package whose description
  changed since, naming the key (`locked dependency changed: qemu (its device virt: the stack key)`): a key's order counts,
  since the regions' order is the script's. The staged entry carries every key unchanged, and the compiler writes the linker
  script and binds the hooks from it in the snapshot, as for an application's device. A lock written before descriptions
  was checked still builds a device without one; for a device with one it names the first key it lacks, and `lock` again
  records it.
- **The snapshot holds the device.** The verified bytes are staged under `.devices/PACKAGE/` and the build compiles
  them there, never the checkout. A device that names files needs `"allow_links": ["PACKAGE"]`, or the build stops first and
  names the line to add.
- **An application's own device** builds through `selka packages build` too: its files are staged at the same paths,
  and its top-level `include` folders reach the staged build as absolute paths. `selka build F.selka` alone refuses a
  package's device with one line that names the `selka packages build` command.
- **No path leaves its folder**, by its spelling or through a symbolic link: a device path whose real location is
  outside the folder of its `selka.json` is refused with that location, and so is a symbolic link to a folder inside a
  device's include folder.

The command replaced `scripts/packages.py`, a Python prototype, with the same
lock and receipt formats. Two things changed: `build` no longer takes
`--compiler`, because the compiler that runs it is the one it uses (the receipt
records its identity, and the snapshot's dependency report must carry the same
one), and the receipt is written once the snapshot checks rather than only when
the command exits 0, since `run-project` now exits with the program's value.
