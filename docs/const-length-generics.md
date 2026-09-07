# Constant length parameters

Generic functions and nominal declarations can mix type parameters with explicit bounded length values:

```my
struct Chunk<T: copy, const N: u64> {
    items: [N]T
}
fn make<T: copy, const N: u64>(items: [N]T) -> Chunk<T, N> {
    return new Chunk<T, N> { items: items };
}
fn first<T: copy, const N: u64>(items: [N]T) -> T {
    return items[0];
}
fn main() -> i64 {
    let chunk = make::<i64, 2>(new [2]i64[40, 2]);
    return first::<i64, 2>(chunk.items) + chunk.items[1];
}
```

A `const N: u64` parameter is a value, distinct from a type parameter. It may appear as `[N]T`, be forwarded to another length parameter, or be read as a u64 value in a generic function body. It cannot be used as a type or shadowed by a local binding. Nominal fields may store arrays sized by these parameters; constructing a nominal value from a matching existing array preserves its length and element identity.

Arguments remain explicit and positional. A length argument is an unsuffixed decimal literal or an enclosing constant length parameter. Supported values are 0 through 1,048,576 inclusive, a bound independent of host pointer width. General expressions, module constants, calls in argument positions, defaults, inferred lengths and other constant parameter types are not supported in this stage. Use a literal specialization or forward a declared length parameter.

Both type and length arguments participate in specialization identity. `Chunk<A,2>`, `Chunk<A,3>` and `Chunk<B,2>` are distinct, even when A and B have identical layouts. Empty arrays remain valid. Generic API metadata marks constant parameters with `constant_length`; generated instance names print their numeric arguments. Existing limits remain: at most 16 combined arguments, 4,096 function specializations, bounded nominal/array shape counts and layout work.

Symbolic checking keeps unknown lengths separate from concrete zero. Invalid templates reject even if never called: type/value confusion, missing element contracts and incompatible symbolic lengths cannot be rescued by one favorable instantiation. An array literal with a fixed number of initializers cannot establish an arbitrary `[N]T` length and rejects in a template. Pass an existing `[N]T` value to a generic factory instead. Indexing retains ordinary runtime bounds checks; a helper that reads element zero can still trap when called with an empty array.

Tests cover nominal element identities, zero and distinct lengths, forwarding, exported constructors and source relocation, formatter round trips, allocation-failure cleanup, specialization key ownership and invalid uncalled templates. Existing generic array, nominal, API and execution suites also pass. Native execution uses the resulting concrete array layouts; no dynamic array length is added to the representation.
