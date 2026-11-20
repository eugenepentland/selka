# Selka

Selka is a statically checked, compiled language with Python-like indentation. A program is made of `func`s and
`record`s with explicit types, `const` and `mut` declarations, and explicit failure handling (`fails`, `try`).
Memory is checked ownership: lists, dictionaries, strings and records are values that are moved between owners,
borrowed for reads and cleaned up when their owner ends. There is no garbage collector and no reference counting.
The compiler is written in Zig, turns a program into LLVM and builds a native executable; an edit recompiles only the
modules whose text changed. It targets Linux on x86-64, and nothing else yet.

Selka is experimental. This is version 0.1.0, the first public release: the language and its diagnostics change between
releases, and a change that breaks working code ships with a `selka fix` migration that rewrites a project across it.

## Install

It runs on Linux with glibc 2.31 or later (Debian 11, Ubuntu 20.04, Fedora 32 and newer) on an x86-64 processor with
AVX2 (the `x86-64-v3` level: most Intel and AMD desktop and laptop processors made since 2015).

Download `selka-0.1.0-x86_64-linux.tar.xz` from the [Releases page](https://github.com/eugenepentland/selka/releases)
(its `.sha256` file is beside it), then:

```sh
tar -xJf selka-0.1.0-x86_64-linux.tar.xz
./selka-0.1.0-x86_64-linux/install.sh
```

That installs `selka` under `~/.local` (set `PREFIX` to choose another place) and needs nothing else: the download
carries the copy of Zig that compiles the generated code. Make sure `~/.local/bin` is on your `PATH`, then check:

```sh
selka --version
```

## Hello, Selka

Save this as `hello.selka`:

```selka
func main(out: Stream) -> int:
    print(out, "Hello, Selka!")
    return 0
```

and run it with `selka run hello.selka`. Output goes through a `Stream` that `main` asks for, and `main`'s value is the
process exit status. A program asks in the same way for everything else it uses: `fs: Filesystem` for files,
`net: Network` for sockets, and so on.

## Tests live beside the code

A public function whose name starts with `test_` and returns `bool` is a test:

```selka
func double(x: int) -> int:
    return x * 2

public func test_double() -> bool:
    return double(21) == 42
```

`selka test double.selka` runs every test of a file in its own process, and `selka test DIR` runs a whole folder.
`selka fmt --check FILE` checks formatting (`--write` repairs it), and `selka check FILE` type-checks without building.

## Learn more

- `selka docs` lists the guides that ship inside the compiler; `selka docs primer` is a one-page tour for Python
  programmers and `selka docs card` lists the rules writers trip on. The same pages are in [docs/](docs/README.md).
- `selka --help` lists the commands. `selka reference --query TERM` looks up a feature or a diagnostic code.
- [examples/](examples/) holds small programs, from `factorial.selka` to an HTTP server and a project that calls C. One that
  reads a file through the `Filesystem` it is given:
  `selka run examples/boundary-cli/main.selka -- examples/factorial.selka`.
- Memory, ownership and the checked rules are in [the ownership guide](docs/ownership-rules.md) and
  [the language guide](docs/python-syntax.md).

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) says how to build the compiler from source, run its tests and what a change should
carry. Selka is released under the [MIT license](LICENSE).
