# Selka

**A simple, explicit language for fast, reliable AI-driven development.**

Selka aims to let agents understand and change code with little surrounding
context, and make those changes easy for humans to review. Fast incremental
compilation and testing keep feedback short. Native execution targets performance
competitive with Rust and Zig.

The language is experimental. This repository presents its design, working
examples, and measured progress.

Selka (pronounced **SELL-kuh**) was previously called `mylang`. The compiler
command is `selka`, source files use `.selka`, and projects use `selka.json`.
See the [rename guide](docs/tooling/selka-rename.md) for existing projects.

## Four goals

- **Local reasoning.** Understand what a call can change, how it can fail, and
  which external resources it needs from the code and its declared contract.
- **Competitive runtime performance.** Native speed is a core requirement,
  measured against equivalent Rust and Zig programs.
- **Fast compilation and testing.** Reuse unchanged work so small edits have
  short feedback loops and substantial integration tests can run frequently.
- **One way to express each concept.** Keep the language simple and consistent,
  with explicit information where it helps understanding and one canonical formatter.

These goals reinforce each other. Local reasoning reduces the context an agent
must read and the work a human reviewer must reconstruct.
[Read the design goals](docs/goals.md).

## A look at the language

```selka
# doc: expect 10 15
record Point:
    x: int
    y: int

func translate(mut points: Point[], named dx: int, named dy: int):
    for i in range(len(points)):
        points[i].x += dx
        points[i].y += dy

func main(out: Stream) -> int:
    const original = [Point(x=10, y=20)]
    mut moved = original

    translate(mut moved, dx=5, dy=-2)

    out.print(original[0].x, moved[0].x)
    return 0
```

`const` and `mut` distinguish immutable values from writable ones. The `mut`
argument makes the caller-visible change explicit; named arguments say what the
offsets mean. Values are independent: changing `moved` leaves `original` intact.
The compiler manages storage sharing and copying underneath that guarantee.
Output requires an explicit `Stream` parameter.

The [language tour](docs/tour.md) adds collections, typed failures, diagnostics,
and tests. Its examples are executable documentation.

## Performance and the development loop

The goal is Rust/Zig-class runtime performance alongside a short edit/check/test
loop. The [benchmark page](docs/benchmarks.md) presents dated snapshots, raw
samples, and measurement limits.

![Runtime snapshot: Selka and Rust with overflow checks, relative to Zig ReleaseSafe; lower is better](docs/figures/showcase-runtime.svg)

This 9 October 2026 snapshot covers all seven workloads in one confirmation
experiment. Selka takes about 1.08–2.60 times Zig ReleaseSafe's elapsed time on
these workloads. It records remaining work toward the goal; it is not a claim
of parity across programs or a measurement of every later compiler revision.

A separate small-project experiment measured a leaf-edit rebuild at **92 ms**
and an unchanged build at **12 ms** in Debug. Nine of ten compilation units were
reused after the edit. These are medians from a nine-module invoice project with
warm runtime/toolchain caches, not general project-size guarantees.
[See the comparisons and methodology](docs/benchmarks.md).

## What exists today

Selka has static types, Python-inspired indentation, records and enums,
`const`/`mut` bindings, growable arrays, dictionaries, optional values, typed
failures, generics, capability parameters, and native C interop. Values use
automatic memory management with reference counting and copy-on-write.

The compiler is implemented in Zig and emits native Linux x86-64 programs
through LLVM. Debug builds cache compilation units; release builds optimize the
whole program. The testing tools support property tests, deterministic capability
stand-ins, cached successful results, and affected-test selection. The
[current language reference](docs/current-language.md) describes the supported
surface and restrictions.

Application experiments include an invoice calculation spanning nine modules,
Lox interpreters, and electronic-design workloads. The
[tour's application section](docs/tour.md#application-experiments) links source
and evidence. These experiments guide language and compiler development.

## Explore

- [Goals and design principles](docs/goals.md)
- [Language tour](docs/tour.md) and [one-page primer](docs/primer.md)
- [Benchmarks and measurement notes](docs/benchmarks.md)
- [Language reference](docs/current-language.md) and [documentation index](docs/README.md)
- [Compiler working instructions](CLAUDE.md) and [design records](docs/design/)
- [Repository contents and retained evidence](docs/publication.md)

The language and tooling are changing actively. Runtime benchmarks, compilation
measurements, and agent task completion measure different things; broad agent
productivity gains remain a goal to evaluate on realistic tasks.
