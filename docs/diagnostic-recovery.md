# Checking independent function faults

One `check` or `check-project` reports the first semantic fault in each independently checked ordinary or generic
function, with its usual code and original byte range, sorted by source range and code. Both undefined names are reported
here:

```selka
# doc: expect-error E_UNKNOWN_NAME
func first() -> i64:
    return missing_first


func second() -> i64:
    return missing_second


func main() -> i64:
    return first() + second()
```

- A failed function is abandoned at its boundary: its unfinished scopes and loans are not carried into the next function.
- Several callers that find the same invalid signature produce one diagnostic for it.
- An error means checking is incomplete: no typed program or Core IR is published and execution is rejected. Whole-program
  ownership, effect and codec passes wait until all bodies pass.
- Recovery starts after syntax, type-catalog, namespace and entry-point construction succeed; a failure there can prevent
  body checking. Generic contract errors still allow ordinary bodies to be checked, but concrete generic instantiations
  and whole-program effect propagation wait for valid contracts.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/diagnostic-recovery.md).
