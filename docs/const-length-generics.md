# Constant length parameters

Generic functions and nominal declarations can mix type parameters with explicit bounded length values:

```selka
record Chunk[T, const N: u64]:
    items: FixedArray[T, N]


func make[T, const N: u64](items: FixedArray[T, N]) -> Chunk[T, N]:
    return Chunk[T, N](items=items)


func first[T, const N: u64](items: FixedArray[T, N]) -> T:
    return items[0]


func main() -> i64:
    const values = FixedArray[i64, 2]([40, 2])
    const chunk = make[i64, 2](values)
    return first[i64, 2](chunk.items) + chunk.items[1]
```

- A `const N: u64` parameter is a value, distinct from a type parameter. It may appear as `FixedArray[T, N]`, be forwarded
  to another length parameter, or be read as a u64 in a generic function body. It cannot be used as a type or shadowed
  by a local binding.
- Nominal fields may store arrays sized by these parameters.
- Explicit arguments are positional. A call may omit the whole list when its argument types determine every type and
  length parameter, as in `first(chunk.items)` (see [generic inference](generic-inference.md)).
- An explicit length argument is an unsuffixed integer literal in any base (`2`, `0x2`, `1_024`) or an enclosing constant
  length parameter, from 0 to 1,048,576 inclusive. General expressions, module constants, calls in argument positions,
  defaults and other constant parameter types are not supported: use a literal or forward a declared length parameter.
- Type and length arguments both make up a specialization: `Chunk<A,2>`, `Chunk<A,3>` and `Chunk<B,2>` are distinct even
  when A and B share a layout. Empty arrays are valid. API metadata marks constant parameters `constant_length`.
- Limits: at most 16 combined arguments and 4,096 function specializations.
- An invalid template rejects even if never called: type/value confusion, missing element contracts and incompatible
  symbolic lengths are not rescued by one favorable instantiation. An array literal cannot establish an arbitrary
  `FixedArray[T, N]` length, so a template rejects it; pass an existing `FixedArray[T, N]` value to a generic factory.
- Indexing keeps its runtime bounds check: a helper that reads element zero traps on an empty array.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/const-length-generics.md).
