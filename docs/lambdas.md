# Lambdas

## Expression-bodied noncapturing lambdas

A `lambda` is a short spelling for an existing function value. Its parameters and
result are typed from the callback expected at that position, so a lambda belongs
directly in a callback argument:

```mylang
# doc: expect 12
record Person:
    age: int

def main() -> int:
    people = [Person(age=30), Person(age=12)]
    ranked = sorted(people, key=lambda person: person.age)
    return ranked[0].age
```

Only `lambda name, ...: expression` is supported. Parameters have no annotations or
defaults, and there is no statement body. A lambda may read its parameters and module
constants. It cannot capture a function local; move the operation to a top-level
function or pass the state as another explicit parameter instead.

The expected callback type supplies the exact effect ceiling as well as the parameter
and result types. A lambda used where no callback type is expected is rejected rather
than inferred without a bound.

A lambda is one function with one callback type, so it cannot be written inside a
generic function body, where each specialization would need its own:
`E_GENERIC_BODY_UNSUPPORTED` says so at the lambda. Declare a top-level function and
pass it by name instead; a named key works in a generic body's `sorted` and `.sort`.

`sorted(values)` keeps its existing ordering for lists of `int`, `float`, or `str`.
`sorted(values, key=callback)` accepts an effect-free callback from the element type to
`int`, evaluates it while performing a stable merge, and leaves the input list unchanged.
