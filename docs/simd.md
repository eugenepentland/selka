# SIMD: `Simd[T, N]`

`Simd[T, N]` holds `N` lanes of one floating type in a single value. It is a
value type: it may sit in records, lists and fixed arrays, and it is passed and
returned in registers as one LLVM vector. A `Simd` is not a `FixedArray`, even
with the same lanes: its operators are elementwise, and `FixedArray` has none.

`T` is `float` or `f32`, a fixed-width integer (`i8` to `i64`, `u8` to `u64`, or `int`
for `i64`), or `bool` for a comparison mask; `N` is 2, 4, 8 or 16. Integer lanes are
described in their own section below, and the lane operations of the `simd` module
after it.

## Lanes and operators

A `Simd` is written from a list of lanes, and a lane is read with `v[k]`. The
lane index is checked as an array index is, so an index past `N` traps.

```selka
# doc: expect 42
func main() -> int:
    const v = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
    if v[2] != 3.0 or v[0] + v[3] != 5.0:
        return 1
    return int(v[1] * 21.0)
```

`+`, `-`, `*` and `/` act on each lane, and unary `-` negates each lane. Both
operands have the same `Simd` type, so a `Simd` and a bare scalar do not mix: `v - 1.0` is
refused. Write the scalar as `simd.splat(1.0)` instead; in a binary operation the splat takes its
lane type and count from the other operand, so it needs no annotation.

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

```selka
# doc: expect 42
func main() -> int:
    const a = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
    const b = Simd[float, 4]([0.5, 0.5, 0.5, 0.5])
    const c = a + b * b
    if c[0] != 1.25 or (-c)[3] != -4.25:
        return 1
    return int(c[1] * 16.0 + 6.0)
```

A comparison compares each lane and answers a mask, `Simd[bool, N]`, whose lanes are
booleans. Read a mask lane with `m[k]`; a mask is not a `bool`, so it cannot be used
as a condition directly.

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

Vectors go through functions and records like any value, and an `f32` lane rounds
per operation, as `f32` does.

```selka
# doc: expect 42
record Body:
    pos: Simd[float, 4]
    mass: f32

func step(body: Body, dt: float) -> Body:
    return Body(pos=body.pos + Simd[float, 4]([dt, dt, dt, dt]), mass=body.mass)

func main() -> int:
    const moved = step(Body(pos=Simd[float, 4]([1.0, 2.0, 3.0, 4.0]), mass=2.5f32), 0.5)
    if moved.pos[2] != 3.5 or moved.mass != 2.5f32:
        return 1
    return 42
```

## Integer lanes

An integer `Simd` takes `+`, `-`, `*` and unary `-` lane by lane, checked as a scalar
integer is: an overflowing lane traps. The wrapping forms `wrapping_add`,
`wrapping_sub` and `wrapping_mul` wrap each lane instead, and `bit_and`, `bit_or` and
`bit_xor` combine lanes bitwise. Comparisons answer a mask, with signed lanes compared
as signed. Integer division is not a `Simd` operator yet, so `/` on integer lanes is
refused; the `&`, `|` and `^` spellings are refused too, in favour of `bit_and` and
its siblings, as on a scalar integer.

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

`and`, `or` and `not` act on a `Simd[bool, N]` mask lane by lane and answer a mask, so two
comparisons combine without a loop. On masks, `and` and `or` evaluate both operands: there is no
single truth value to short-circuit on, so the right operand is always computed, even when the left
one already decides every lane. `bit_and`, `bit_or` and `bit_xor` take masks as they take integer
lanes. A mask and a scalar `bool` do not mix; splat the bool with `simd.splat`, which takes its lane
count from the mask.

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

The `simd` module works on whole vectors, for every lane type a `Simd` takes (`float`, `f32`
and the integers) and every lane count (2, 4, 8, 16). `simd.splat(value)` and
`simd.load(values, index)` take their lane count from the `Simd` type their context expects, so
bind them to an annotated name, pass them where a `Simd` is expected, or use a splat as an operand of
a binary operator whose other operand is a `Simd`: a bare `simd.splat(2.0)` is refused with
`E_SIMD_CONTEXT`. A literal lane value takes the lane type: `simd.splat(200)` is a
`u8` vector when the type says so, and refused with `E_TYPE` when the value does not fit.

```selka
# doc: expect 42
import simd

func main() -> int:
    const v: Simd[float, 4] = simd.splat(2.5)
    const xs: float[] = [1.0, 2.0, 3.0, 4.0, 5.0]
    const w: Simd[float, 4] = simd.load(xs, 1)
    if v[3] != 2.5 or w[0] != 2.0 or w[3] != 5.0:
        return 1
    return 42
```

`simd.store(mut values, index, value)` writes each lane into the list from `index` (the list
is passed with `mut`, and each lane is checked as a list element is). `simd.select(mask, a, b)`
picks lane `i` of `a` where the mask holds and of `b` elsewhere. `simd.sum`, `simd.min` and
`simd.max` fold the lanes in lane order; `min` and `max` keep the earlier lane on a tie, as the
scalar `min` and `max` do. On integer lanes the sum is checked, as `+` is, so an overflowing
lane traps. `simd.fma(a, b, c)` rounds each float lane's `a * b + c` once; integer lanes have no
fused form and are refused with `E_SIMD_LANE`. `simd.select` takes float, f32, integer or mask lanes.

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

```selka
# doc: expect 42
import simd

func main() -> int:
    mut bytes: u8[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    const v: Simd[u8, 16] = simd.splat(200)
    simd.store(mut bytes, 0, v)
    const doubled = wrapping_add(v, v)
    const top: u8 = simd.max(v)
    if bytes[15] != 200 or doubled[0] != 144 or top != 200:
        return 1
    return 42
```

A loop over the lanes of a `Simd` can be asked to vectorize with `@vectorize`; see
loops that vectorize.

## Square root

`simd.sqrt(v)` takes the square root of each lane of a float or f32 `Simd`, as one vector square
root. Each lane is correctly rounded, as the scalar `math.sqrt` is. `math.sqrt` takes a float and
refuses a `Simd` with the repair `simd.sqrt`; integer lanes are refused.

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

`min(a, b)` and `max(a, b)` take two `Simd` values of one type and answer lane by lane. Each lane
follows the scalar rule: `min` takes `b` only where `b` is smaller, `max` takes `b` only where `b` is
larger, so a tie, a signed zero or a not-a-number lane keeps the first operand, as the scalar `min`
and `max` do. Bool lanes are refused. `simd.min(v)` and `simd.max(v)` still fold one vector's lanes.

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

`float(v)` on a `Simd[f32, N]` widens each lane exactly, and `f32(v)` on a `Simd[float, N]` rounds each
lane to binary32, as the scalar `float` and `f32` conversions do, for subnormal, overflowing and
not-a-number lanes alike. Other conversions of a `Simd`, including integer lanes, are refused.

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

A `Simd[T, N]` is an LLVM `<N x T>` in SSA. Elementwise arithmetic is one `fadd`,
`fsub`, `fmul`, `fdiv` or `fneg` on the vector, and a comparison is one `fcmp` that
answers `<N x i1>`. A lane read is one `extractelement`, after the same bounds check
an array index runs. Passing a vector to a function or returning one does not
spill it: the vector crosses the call in its registers. In memory a float vector is
its lanes in order, and a mask is spilled lane by lane, because LLVM packs an
`i1` vector into bits.

A `Simd[T, N]` and a `FixedArray[T, N]` with the same lanes are different types:
`Simd` has elementwise operators, and the two do not compare or convert to each
other.
