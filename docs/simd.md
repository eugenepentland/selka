# SIMD: `Simd[T, N]`

`Simd[T, N]` holds `N` lanes of one type in a single value. It is a value type: it may sit in records, lists and fixed
arrays, and it is passed in registers as one vector. A `Simd` is not a `FixedArray`, even with the same lanes: its
operators are elementwise, and the two do not compare or convert to each other.

`T` is `float` or `f32`, a fixed-width integer (`i8` to `i64`, `u8` to `u64`, or `int` for `i64`), or `bool` for a
comparison mask; `N` is 2, 4, 8 or 16.

## Lanes and operators

A `Simd` is written from a list of lanes, and a lane is read with `v[k]`; an index past `N` traps.

```selka
# doc: expect 42
func main() -> int:
    const v = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
    if v[2] != 3.0 or v[0] + v[3] != 5.0:
        return 1
    return int(v[1] * 21.0)
```

`+`, `-`, `*` and `/` act on each lane, and unary `-` negates each lane. Both operands have the same `Simd` type, so
`v - 1.0` is refused: write the scalar as `simd.splat(1.0)`, which takes its lane type and count from the other operand.

```selka
# doc: expect 42
import simd

func main() -> int:
    const x = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
    const y: Simd[float, 4] = x - simd.splat(1.0)
    if y[0] != 0.0 or y[3] != 3.0:
        return 1
    return 42
```

A comparison answers a mask, `Simd[bool, N]`, whose lanes are booleans. Read a mask lane with `m[k]`; a mask is not a `bool`
and cannot be a condition directly. An `f32` lane rounds per operation, as `f32` does.

```selka
# doc: expect 42
func main() -> int:
    const a = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
    const limit = Simd[float, 4]([2.5, 2.5, 2.5, 2.5])
    const below: Simd[bool, 4] = a < limit
    if not below[1] or below[2]:
        return 1
    return 42
```

## Integer lanes

An integer `Simd` takes `+`, `-`, `*` and unary `-` lane by lane, checked as a scalar integer is: an overflowing lane traps.
`wrapping_add`, `wrapping_sub` and `wrapping_mul` wrap each lane instead, and `bit_and`, `bit_or` and `bit_xor` combine lanes
bitwise. Comparisons answer a mask, with signed lanes compared as signed. `/` on integer lanes is refused, and so are the
`&`, `|` and `^` spellings, as on a scalar integer.

```selka
# doc: expect 42
func main() -> int:
    const a = Simd[int, 4]([1, 2, 3, 4])
    const wrapped = wrapping_add(Simd[u8, 4]([255, 1, 2, 3]), Simd[u8, 4]([1, 1, 1, 1]))
    if wrapped[0] != 0 or wrapped[1] != 2:
        return 1
    const masked = bit_and(a, Simd[int, 4]([3, 3, 3, 3]))
    if masked[3] != 0 or (-a)[2] != -3 or (a + a)[3] != 8:
        return 1
    const big: Simd[bool, 4] = a > Simd[int, 4]([0, 5, 0, 5])
    if not big[0] or big[1]:
        return 1
    return 42
```

## Mask logic

`and`, `or` and `not` act on a `Simd[bool, N]` mask lane by lane and answer a mask, so two comparisons combine without a loop.
On masks `and` and `or` evaluate both operands: there is no single truth value to short-circuit on. `bit_and`, `bit_or`
and `bit_xor` take masks as they take integer lanes. A mask and a scalar `bool` do not mix; splat the bool with `simd.splat`.

```selka
# doc: expect 42
func main() -> int:
    const x = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
    const inside: Simd[bool, 4] = (x > Simd[float, 4]([0.0, 0.0, 0.0, 0.0])) and (x < Simd[float, 4]([2.5, 2.5, 2.5, 2.5]))
    const outside: Simd[bool, 4] = not inside
    const either: Simd[bool, 4] = inside or outside
    if not inside[0] or inside[2] or not outside[3] or not either[1]:
        return 1
    return 42
```

## Lane operations

The `simd` module works on whole vectors, for every lane type and lane count.

| Call | What it does |
| --- | --- |
| `simd.splat(value)` | every lane is `value` |
| `simd.load(values, index)` | lanes from the list at `index` |
| `simd.store(mut values, index, value)` | writes each lane into the list from `index`, each checked as a list element |
| `simd.select(mask, a, b)` | lane `i` of `a` where the mask holds, of `b` elsewhere (float, f32, integer or mask lanes) |
| `simd.sum(v)`, `simd.min(v)`, `simd.max(v)` | fold the lanes in order; `min` and `max` keep the earlier lane on a tie; an integer sum is checked |
| `simd.fma(a, b, c)` | each float lane's `a * b + c` rounded once; integer lanes are `E_SIMD_LANE` |

`simd.splat` and `simd.load` take their lane count from the `Simd` type their context expects: bind them to an annotated
name, pass them where a `Simd` is expected, or use a splat beside a `Simd` operand. A bare `simd.splat(2.0)` is
`E_SIMD_CONTEXT`. A literal lane value takes the lane type: `simd.splat(200)` is a `u8` vector when the type says so, and
`E_TYPE` when the value does not fit.

```selka
# doc: expect 42
import simd

func main() -> int:
    mut xs: float[] = [1.0, 2.0, 3.0, 4.0, 5.0]
    simd.store(mut xs, 0, Simd[float, 4]([7.0, 8.0, 9.0, 10.0]))
    const a = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
    const b = Simd[float, 4]([10.0, 20.0, 30.0, 40.0])
    const mask: Simd[bool, 4] = a < Simd[float, 4]([2.5, 2.5, 2.5, 2.5])
    const picked = simd.select(mask, a, b)
    if xs[3] != 10.0 or picked[2] != 30.0 or simd.sum(a) != 10.0 or simd.max(a) != 4.0:
        return 1
    return 42
```

A loop over the lanes of a `Simd` can be asked to vectorize with `@vectorize`.

## Square root

`simd.sqrt(v)` takes the correctly rounded square root of each lane of a float or f32 `Simd`. `math.sqrt` refuses a `Simd`
with the repair `simd.sqrt`; integer lanes are refused.

```selka
# doc: expect 42
import simd

func main() -> int:
    const v = Simd[float, 4]([1.0, 4.0, 9.0, 16.0])
    const r: Simd[float, 4] = simd.sqrt(v)
    if r[1] != 2.0 or r[3] != 4.0:
        return 1
    return 42
```

## Lane-wise minimum and maximum

`min(a, b)` and `max(a, b)` take two `Simd` values of one type and answer lane by lane, by the scalar rule: a tie, a signed
zero or a not-a-number lane keeps the first operand. Bool lanes are refused. `simd.min(v)` and `simd.max(v)` still fold one
vector's lanes.

```selka
# doc: expect 42
func main() -> int:
    const a = Simd[float, 4]([1.0, 5.0, 3.0, 7.0])
    const b = Simd[float, 4]([2.0, 4.0, 6.0, 1.0])
    const low: Simd[float, 4] = min(a, b)
    const high: Simd[float, 4] = max(a, b)
    if low[1] != 4.0 or high[3] != 7.0:
        return 1
    return 42
```

## Lane conversion between f32 and float

`float(v)` on a `Simd[f32, N]` widens each lane exactly, and `f32(v)` on a `Simd[float, N]` rounds each lane to binary32, as the
scalar conversions do. Other conversions of a `Simd`, integer lanes included, are refused.

```selka
# doc: expect 42
func main() -> int:
    const v = Simd[f32, 4]([1.0f32, 2.5f32, -0.5f32, 4.0f32])
    const w: Simd[float, 4] = float(v)
    const n: Simd[f32, 4] = f32(w)
    if w[1] != 2.5 or n[2] != -0.5f32:
        return 1
    return 42
```

## Lowering

A `Simd[T, N]` is one LLVM `<N x T>` vector: elementwise arithmetic is one vector instruction, and a vector crosses a call in
its registers. In memory a float vector is its lanes in order, and a mask is spilled lane by lane.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/simd.md).
