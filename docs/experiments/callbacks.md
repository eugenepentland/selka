# Noncapturing function values

A function name can be copied into a local, record or array, passed to another
function, returned, and invoked through a local name:

```mylang
fn increment(x:i64)->i64 effects(){return x+1;}
fn twice(f:fn(i64)->i64 effects(),x:i64)->i64{return f(f(x));}
fn main()->i64{let f=increment;return twice(f,5);}
```

Callable types declare concrete value parameter/result types and an explicit
effect ceiling. The named target must be a nongeneric free function with a
declared ceiling. Types and ceilings match exactly at value boundaries; a
wrapper can supply a different declared ceiling. The compiler checks the target's
body against its ceiling, and indirect calls add that ceiling to their caller's
effects. Callback values retain no authority or local state and allocate no guest
storage. Function identities are opaque, have no numeric conversion or equality,
and cannot cross portable data/host-value serialization boundaries.

Arguments transfer and results retain ordinary ownership and handling rules. A
callback consuming a buffer moves it once; a returned result still needs matching,
propagation, acknowledgment, or onward transfer. The VM and generated native code
check each dynamic target against the signature. Ordinary frame/instruction limits
and trap/OOM unwinding apply to callback recursion and aggregate results.

`std_collections.sort_by_i64` and `transform_i64` use pure callbacks for ordering
and transformation. Callable values may also pass through type-only generic
records or generic helpers with concrete callback signatures.

This stage supports at most 16 value parameters and 4096 inferred signatures.
Captures, borrowed callback parameters/results, generic function values,
parameter-dependent callable signatures, and arbitrary expression-call syntax
remain unsupported. Bind a callback field or returned callback to a local before
calling it. Stored reference lifetimes remain a separate feature.
