# A short tour of Selka

Selka's [design goals](goals.md) start with understanding code locally. These
examples use the current language; each fenced program is checked or executed
by `selka doctest`.

## Ordinary data processing

Records describe data, arrays hold values, and a comprehension reads in the
order of its work: source, filter, output.

```selka
# doc: expect hot
record Reading:
    sensor: str
    value: int

func above(readings: Reading[], named minimum: int) -> str[]:
    return [for reading in readings if reading.value >= minimum yield reading.sensor]

func main(out: Stream) -> int:
    const readings = [
        Reading(sensor="cool", value=18),
        Reading(sensor="hot", value=31),
    ]
    const names = above(readings, minimum=25)
    out.print(names[0])
    return 0
```

The parameter is read-only and `minimum` must be named at the call. The result
is an array of strings. Those facts are visible without tracing the function's
implementation. Strings and collections use automatic memory management.

## Mutation is visible at both ends

The [README example](../README.md#a-look-at-the-language) marks the writable
parameter and its argument with `mut`. Assigning an array to another binding
preserves an independent value; changing one does not change the other.
A declaration using `const` cannot be passed as writable data.

For example, the compiler rejects this attempted mutation:

```selka
# doc: expect-error E_IMMUTABLE
func main() -> int:
    const count = 1
    count = 2
    return count
```

The repair is to declare `mut count = 1` if changing it is intended. That decision
belongs in the source rather than depending on a reader discovering a later write.
See [bindings](statements.md) and [value semantics](value-semantics.md).

## Expected failure is part of the contract

A function's header describes the successful value and the error it may return.
`try` makes propagation visible at the call; `match` handles the alternatives.

```selka
# doc: expect 42
# doc: expect invalid quantity
func quantity(text: str) -> int fails str:
    const value = parse_int(text)
    if value is None:
        fail "invalid quantity"
    if value < 0:
        fail "quantity must be nonnegative"
    return value

func line_total(text: str, named unit_price: int) -> int fails str:
    const count = try quantity(text)
    return count * unit_price

func main(out: Stream) -> int:
    match line_total("3", unit_price=14):
        case Ok(total):
            out.print(total)
        case Err(message):
            out.print(message)
    match line_total("three", unit_price=14):
        case Ok(total):
            out.print(total)
        case Err(message):
            out.print(message)
    return 0
```

Absence (`int?` from `parse_int`) and an expected error (`fails str`) have explicit
handling. Arithmetic overflow remains a bug trap. The language keeps runtime
checks in optimized builds; the compiler may remove a check it proves cannot fail.
See [results and options](results-and-options.md).

## Tests live beside the behavior

Tests are ordinary public functions. This example exercises parsing and price
calculation together, including their error boundary.

```selka
# doc: expect True
func total(text: str, named price: int) -> int fails str:
    const count = parse_int(text)
    if count is None:
        fail "invalid quantity"
    return count * price

public func test_total() -> bool:
    match total("3", price=14):
        case Ok(value):
            return value == 42
        case Err(_):
            return False

public func test_bad_quantity() -> bool:
    match total("three", price=14):
        case Ok(_):
            return False
        case Err(message):
            return message == "invalid quantity"

func main(out: Stream) -> int:
    out.print(test_total() and test_bad_quantity())
    return 0
```

The test runner discovers `public func test_*` functions, gives each test an
isolated trial, and can reuse successful results when its program and settings
are unchanged. It also supports property tests and deterministic stand-ins for
external capabilities. Larger integration tests can use the same workflow.
See [guest tests](tooling/guest-tests.md).

## Application experiments

The project uses larger programs to exercise language and compiler decisions:

| Program | What it exercises | Source or evidence |
| --- | --- | --- |
| Nine-module invoice calculation | Imports, typed records, validation, pricing, and incremental rebuilds | [Entry](../examples/corpus/invoice/main.selka), [calculation](../examples/corpus/invoice/pricing.selka), [build measurements](benchmarks.md#incremental-builds) |
| Lox interpreters | Parsing, tree and bytecode execution, recursive data, and hot loops | [New-core application measurements](../experiments/parity-measure-20261008/REPORT.md#reference-ratios) |
| Electronic-design workloads | Structured design data, parsing, and application-scale compiler/runtime costs | [New-core application measurements](../experiments/parity-measure-20261008/REPORT.md#reference-ratios) |

These are development experiments, not packaged applications. Their dated reports
identify the measured compiler and workload. Older schematic SVG and QBE reports
remain in the research archive; they do not describe the current runtime.

[Design goals](goals.md) · [Benchmarks](benchmarks.md) · [Full primer](primer.md)
