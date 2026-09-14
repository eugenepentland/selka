# Native guest tests

These are guest-behavior tests written in the language and run by
`mylang test`. Each `.my` file is an independent single-program project: it
declares `module <file stem>`, exports its `test_*` functions, and ends with
`def main() -> int: return 0`. Every test returns `bool`, so the runner's
default expected value `true` applies and no `cases.json` is needed.

Run the whole suite:

```console
$ zig-out/bin/mylang test tests/guest --filter '*'
```

The directory runner selects every `.my` program in sorted order, builds one
native test library per program, and caches each successful case under
`.mylang-cache/tests`. A cold run compiles and executes; an unchanged rerun
reports `cached` instead of executing:

```console
$ zig-out/bin/mylang test tests/guest --filter '*'
42 passed, 0 cached, 0 failed, 0 skipped across 11 programs
$ zig-out/bin/mylang test tests/guest --filter '*'
0 passed, 42 cached, 0 failed, 0 skipped across 11 programs
```

A directory run rejects `--cases` (its keys name one project), and none of
these cases needs typed arguments or a non-`true` expectation, so there is no
manifest. Provider (`providers`) fixtures are likewise unavailable to a
directory run.

## Coverage

- `arithmetic.my` — operator precedence, floored `//`/`%`, truncating
  `divtrunc`/`remtrunc`, comparisons, short-circuit `and`/`or`, float
  arithmetic and `floor`/`ceil`/`trunc`/`sqrt`/`abs`.
- `integers.my` — fixed-width conversions and widening, signed/unsigned
  extremes, `wrapping_*`, `saturating_*`, `bit_*`, shifts, and division
  rounding.
- `lists.my` — append, indexing, negative indexes, slices (copy semantics),
  membership, iteration, `enumerate`, `break`/`continue`, comprehensions and
  `range`.
- `dicts.my` — insertion-ordered `dict[str, int]`, alias-shared updates,
  `get`, `keys`, `values`, membership and `len`.
- `text.my` — Unicode `str` length/index/slice, concatenation, `split`/`join`,
  the intrinsic string methods, `f"..."` interpolation and `str(value)`.
- `bytes.my` — `bytes` literals, indexing/slicing, iteration, `find`,
  `startswith`/`endswith`, membership, `split`/`join`, `bytes(list[int])`,
  `to_list`, `hex`, `encode`/`decode` into a `Result`.
- `records.my` — value records and field-copy semantics, enums, tagged
  unions with `match`, fixed arrays and enum-indexed tables with `replace`.
- `results_options.my` — `Result` matching, exhaustive handling,
  `expression?` propagation, `Option`/`Some`/`None`, and the `int(str)` /
  `float(str)` option-returning parsers.
- `generics.my` — generic functions, generic nominal records, generic
  `Result` payloads, the `integer`/`equality` contracts and a structural
  `field(value: int)` contract.
- `callbacks.my` — noncapturing function values with explicit signatures and
  empty effect ceilings, plus `noalloc` effect bounds.
- `loops.my` — `range`, `enumerate`, `break`/`continue`, filtered
  comprehensions and `while`.

## Deliberately left to the Python drivers

- **Environment, clock, entropy and callback providers**
  (`tests/native_environment.py`, `tests/native_providers.py`): the native test
  runner registers no host callbacks and grants no ambient authority, so a
  `host def` dependency fails with `HostMissingRegistration`. Those files
  exercise the real VM and native provider implementations; that host
  machinery is not available to a guest test process.
- **Filesystem/network resource lifecycles** (`tests/native_resources.py`):
  the cases install deterministic providers, check acquire/complete/read/write
  release order and assert allocation-failure behavior. The native runner has
  no provider registration, and a directory run cannot supply a `providers`
  fixture, so these stay with the Python driver.
- **Provider source-substitution fixtures** (`cases.json` `providers`): useful
  for replacing a host declaration with guest source, but a directory run
  rejects `--cases`, and substitution exercises deterministic guest code rather
  than the host implementation.
- **Trap and generated stress fixtures** (`tests/native_cases.py`): cases that
  expect a trap (`divtrunc(1, 0)`, aggregate bounds, `ENUM_TRAP`, …) cannot be
  positive `bool` tests because a trap is reported as a failed case, and the
  native runner compares values rather than trap codes. The deep packed/boxed
  variant chains are generated and are covered here by the representative
  union/match cases; the trap parity itself remains in the Python driver.
- **Named laws** (`tests/laws.py`): sampled laws and bounded reduction are
  driven by `scripts/laws.py` and provider configuration, not by `mylang test`.

## Link note

A managed `str`/`bytes`/`dict` test library compiles into a shared library, so
the guest object's references to the `myl_t_*` type descriptors must bind inside
that library. `src/qbe_build.zig` links `--library` output with
`-Wl,-Bsymbolic` for that reason; without it the link fails with
`R_X86_64_PC32 ... recompile with -fPIC`.
