# Bootstrap v1 language subset

`bootstrap-v1` is the candidate language contract allowed in the self-hosted
compiler. It is a whitelist, not a survey of everything mylang implements. The
compiler may adopt an item only after it is implemented and satisfies the
one-version delay in [D7](adr/D7-feature-delay.md).

This document is **not frozen**. It freezes only after the Wave 2 program
boundary work and `Cell[T]` land and the one-version delay is satisfied.

## Status

### Implemented now

- `module`, `import`, `export`, and the declaration forms listed below.
- Function-scoped locals with `E_UNBOUND` definite assignment. Every `while`,
  ordinary `for`, `range`, `reversed` and `zip` loop is treated as
  potentially zero-iteration, so only predeclared state is definite after the
  loop.
- Contextually typed, expression-bodied noncapturing `lambda`.
- The existing prelude builtins, including `sum`, `min`, `max`, `sorted`, `any`,
  `all`, `reversed`, `list`, and `zip`. The compiler does not use every one of
  them, but they stay part of the public vocabulary.
- The standard-library functions listed under Standard library, subject to the
  effects and capability limits below.

### Pending Wave 2 boundary work

- `Cell[T]` construction plus `.value` read and replacement.
- `main -> Result`, `eprint`, and restricted-capability stderr parity.
- `const` `str`/`bytes` and `?` propagation over `Option`.

Wave 2 item 1 has landed: `main(args: list[str], ...)`, the `--` guest boundary,
and `build --run` module detection are available.

### Migration in progress

- The accepted `record` spelling from [D2](adr/D2-record-keyword.md) is now a
  contextual declaration head, and repository examples and standard-library
  modules use it. `class` remains accepted during the compatibility window;
  final removal waits on the planned agent-idiom check and the one-version
  delay.

### Deferred from compiler internals

- `json`, `pool`, `random`, and `time` standard modules.
- `network`, `clock`, `random`, unrestricted `host`, ambient authority, and
  compile-time I/O.

## Syntax and declarations

- UTF-8 source, `#` comments, newline/indentation suites, and parentheses for
  continuation; no brace dialect or semicolon-dependent style.
- `module`, `import`, and `export`; top-level `const`, `type`, `record`, `enum`,
  `union`, `result`, and `def` declarations. `class` remains the compatibility
  declaration head during the migration window.
- Annotated parameters, fields, non-unit results, generic `[T]` parameters with
  the existing `copy`, `storable`, `integer`, and `equality` requirements, and
  explicit or inferred call type arguments.
- Literals for `int`, `float`, `bool`, `None`, `str`, `bytes`, homogeneous lists,
  dictionaries, records, enums, unions, results, and options.
- Assignment, annotated assignment, indexed/field assignment, augmented
  assignment, expression statements only for unit calls, and `_ = value` discard.
- `if`/`elif`/`else`, `while`, `for ... in`, `range`, `enumerate`, `break`,
  `continue`, `match`/`case`, `return`, `pass`, `assert`, and postfix `?`.
- Arithmetic, comparisons, Boolean operators, membership, indexing, slicing,
  calls, field access, f-strings, comprehensions, and contextually typed,
  expression-bodied noncapturing `lambda`.
- Function-scoped introduced locals with sound zero-iteration loop handling, as
  described in [D1](adr/D1-block-scope.md). Lambdas use only parameters and
  module constants; nested functions, captures, tuples, inheritance, record
  methods, exceptions, pointers, references, and compile-time I/O are excluded.

## Types and managed operations

The allowed types are `int`, `float`, `bool`, `None`, `str`, `bytes`, `list[T]`,
`dict[K, V]`, `Option[T]`, `Result[T, E]`, declared value types, noncapturing
function values, and `Cell[T]`. `Cell` permits only construction plus `.value`
read and replacement. Fixed integers and arrays may appear only in runtime ABI or
codec adapters, not ordinary compiler data structures.

Lists may use `append`, `pop`, `clear`, `extend`, `index`, `remove`, `reverse`,
`sort`, `copy`, indexed get/set, slicing, length, concatenation, repetition, and
iteration. Dictionaries may use indexed get/set, `get`, membership, `pop`,
`keys`, `values`, `items`, length, and iteration. Strings and bytes may use
length, indexing, slicing, membership, concatenation, `find`, prefix/suffix
tests, `split`, `join`, conversion, and iteration. Repeated text construction
must use the approved managed builder once its measured contract lands.

## Prelude

Compiler code may use `len`, `str`, `int`, `float`, `print`, `enumerate`,
`range`, `sum`, `min`, `max`, `sorted`, `abs`, `round`, `any`, `all`,
`reversed`, `list`, and `zip`; constructors `Ok`, `Err`, `Some`, `None`, and
`Cell`; and `todo[T]` only in code that cannot ship. Removed aliases and raw
`f64_*` spellings are excluded.

## Standard library

The compiler may call only these imported functions:

- `strings.is_digit`, `is_alpha`, `is_alnum`, `is_space`, `starts_with`,
  `ends_with`, `find`, `count`, `strip`, `lstrip`, `rstrip`, `lines`, `upper`,
  `lower`, `to_int`, and `format_int`;
- `sort.sort_ints`, `sort.sort_strs`, `sort.sort_by_key`,
  `sort.is_sorted_ints`, `sort.binary_search`, `sort.unique_ints`, and
  `sort.unique_strs`;
- `path.separator`, `path.is_absolute`, `path.join`, `path.join_all`,
  `path.basename`, `path.dirname`, `path.splitext`, `path.stem`,
  `path.extension`, `path.components`, and `path.normalize`;
- `hex.encode`, `hex.encode_upper`, `hex.decode`, and `hex.is_hex`;
- `base64.b64encode`, `base64.b64decode`, `base64.urlsafe_b64encode`, and
  `base64.urlsafe_b64decode`; and
- `math.is_nan`, `math.is_inf`, `math.is_finite`, `math.sqrt`, `math.trunc`,
  `math.floor`, `math.ceil`, `math.round`, `math.pow`, `math.min`, `math.max`,
  `math.clamp`, `math.abs`, `math.isqrt`, `math.gcd`, and `math.lcm`.

`json`, `pool`, `random`, and `time` are excluded from compiler internals unless
a later measured requirement amends this version. Compiler diagnostics and build
manifests use purpose-built checked records/codecs at the runtime boundary.

## Effects and capabilities

Allowed effect names are `managed_allocation`, `filesystem`, `environment`, and
`output`. Pure helpers use `effects()` where a stable callback contract needs it;
other functions omit a ceiling or state the narrow exact ceiling. `network`,
`clock`, `random`, unrestricted `host`, ambient authority, and compile-time I/O
are excluded.

The entry point may take `args: list[str]`, followed by `Filesystem` and
`Environment`. It reads project files only through the filesystem capability,
reads selected environment values explicitly, writes normal machine output to
stdout and diagnostics through the canonical stderr operation, and returns
`int` or `Result[int, str]`. The `list[str]` argument and `--` launch boundary are
implemented; stderr and the environment operations remain Wave 2 work.

## Runtime boundary

Compiler source emits QBE text and calls only `runtime-abi-v1` adapters described
by [D6](adr/D6-runtime-boundary.md). Managed allocation, traps, process startup,
capability providers, platform calls, assembly, and linking stay outside `.my`
compiler code. No implementation detail of the Zig launcher is part of this API.
