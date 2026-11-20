# G8. `check` and `build` give one verdict: pinned examples

The ownership matrix and the check-build agreement tests hold this goal in the gate. These examples pin the exceptions.

**G8-X1 (`@noalloc` reads callee bodies and is judged only at build; W14).** `check` accepts this program and the build
refuses it, inside the callee.

```selka
# doc: build
# doc: expect-error E_NOALLOC_ALLOCATES
func helper(x: int) -> int:
    const scratch = [x, x]
    return scratch[0] + 1

@noalloc
func hot(x: int) -> int:
    return helper(x) * 2

func main() -> int:
    return hot(3)
```

**G8-X2 (a typed hole).** `check` refuses a hole. A default build accepts the same program and the binary traps
`R_TYPED_HOLE`; `--release` refuses it. Only the `check` half can be pinned here.

```selka
# doc: expect-error E_TYPED_HOLE
func helper() -> int:
    return todo[int]()

func main() -> int:
    return helper()
```

A plain `bytes` parameter given to a task (`check` accepts, the build refuses with `E_CORE_UNSUPPORTED`) is already an
executed example under rule Z3 of `docs/ownership-rules.md`.
