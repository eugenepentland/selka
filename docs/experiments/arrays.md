# A1: fixed arrays and checked indexing

Status: implemented on Guardian's `0.17.0-dev.1683+5ceec001b` toolchain.
Together with records, complete conversions, and integer widths, this completes
A1. Domain types, borrowing, resources, and the other roadmap tracks are separate
pending work.

## Syntax and type identity

```selka
func sum(values: FixedArray[i64, 3]) -> i64:
    mut index = 0
    mut total = 0
    while index < len(values):
        total += values[index]
        index += 1
    return total


func main() -> i64:
    mut original: FixedArray[i64, 3] = FixedArray[int, 3]([4, 7, 9])
    mut changed = replace(original, 1, 11)
    return sum(original) + sum(changed)
```

`[N]T` is a fixed array type wherever a type annotation is accepted. `N` is an
unsuffixed, nonnegative integer literal in any base (`16`, `0x10`, `1_024`);
expressions, integer suffixes and decimal leading zeros are not allowed.
Whitespace and the spelling of the length do not affect identity. Types are
interned by resolved element type and length: `[2]i64` equals `[0x2] i64`, but
neither equals `[3]i64` or `[2]u64`. Arrays of different nominal record types
remain distinct. Nested arrays, arrays of records, and record fields containing
arrays are supported, including forward record declarations.

`new [N]T [expression, ...]` requires exactly N expressions of type T. There
are no implicit coercions, default elements, inferred lengths, or trailing commas.
`new [0]T []` constructs an empty array. Type metadata does not allocate one
entry per element. Lengths exceeding host addressable value-buffer storage are
rejected before runtime. Record/array dependency cycles are rejected, including
cycles through zero-length arrays, under the initial acyclic type policy. Array
type nesting shares the parser's 256-level budget.

## Evaluation, bounds, and copies

`array[index]` accepts any supported signed or unsigned integer width. The base
and then the index evaluate exactly once. A negative index counts from the end, as
for a list; an index below minus the length or at least the length traps with
`R_LIST_BOUNDS`, a source span, and the ordinary guest call trace. Full-range `u64` indices are checked before conversion
to host indices. These checks remain active in Debug and ReleaseFast. Indexing
binds as tightly as field access and permits `grid.rows[i][j].value`.

`replace(array, index, value)` produces an array of the same type, replacing
one element and preserving all others. Its three arguments evaluate left to
right before bounds checking, like an ordinary call; an invalid index does not
skip evaluation of the replacement. The replacement must have the exact element
type. Both `replace` and `len` are reserved keywords.

`len(array)` returns an `int`. Its operand is evaluated and released, even though
the length is statically known; initializer traps are never erased. Empty arrays
have length zero and no valid index. Whole-array equality is not defined; compare
selected elements explicitly. Mutable bindings can be reassigned, but indexed
assignment is not supported; use `a = replace(a, index, value)`.

Arrays use the same immutable, retained aggregate storage as records. An update
copies the immediate element buffer, sharing immutable nested values. Indexing
retains the result before releasing the containing array. Old copies survive
updates, calls, and returns. Storage is released on overwrite, function exit,
traps, and allocation failures; release is iterative. Replacement costs O(N)
work and storage for the immediate array; this is not an in-place mutable-buffer
or borrowing model. Guest instruction budgets bound instructions, not the time
or allocation cost of each aggregate instruction.

Complete record conversions account for array-valued source fields by explicit
field access or discard, just like other fields. Reading `source.values[0]`
accounts for `values`, not every element separately. Conversion declarations
still require record parameters/results; ordinary helpers can transform arrays.

## Evidence

- `src/arrays_test.zig`: structural identity, all integer index widths, empty and
  nested arrays, record composition, complete-conversion accounting, malformed
  schemas, length/element errors, cycle rejection, parser limits, bounds spans,
  evaluation order, VM validation, and allocation-failure cleanup.
- A source loop performs 10,000 replacements under a 4 KiB live-byte cap, then
  reports zero outstanding runtime bytes. Instruction-budget and bounds traps
  also release all runtime storage.
- Exact duplicate discovery `exact-v4` preserves array lengths, element types,
  index expressions, ordered construction, replacement, and length evaluation.
  Renamed bindings and equivalent type spelling still match.
- Actual CLI fixtures check successful execution (`examples/arrays.selka` prints
  `44`), schema rejection across all four commands, dumps, and bounds diagnostics.
- The complete suite passes 90/90 tests in Debug and ReleaseFast (74 core,
  16 actual CLI); formatting and whitespace checks pass.
