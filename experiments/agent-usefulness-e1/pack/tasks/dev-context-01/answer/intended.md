# The intended answer — held separately from the brief

`ranking.my` declares

```mylang
public def rank_in_place(readings: list[model.Reading]) -> None effects(mutation) mutates(readings):
    return todo[None]()
```

The hole is filled with a stable insertion sort over the caller's own list: lift
`readings[index]` into a local record copy, shift the larger values (strict `>`
comparison on `value`, which is what keeps equal values in their original order)
one slot to the right, and drop the copy into the gap. Indexed assignment writes
through the parameter, so the caller's list holds the result; no allocation is
needed, so `effects(mutation)` is the whole contract.

```mylang
    index = 1
    while index < len(readings):
        current = readings[index]
        position = index
        while position > 0 and readings[position - 1].value < current.value:
            readings[position] = readings[position - 1]
            position = position - 1
        readings[position] = current
        index = index + 1
```

Other correct answers pass: the hidden probe grades behaviour only. A selection
sort, or a `sorted(...)` result copied back element by element, also passes if
the caller's list ends up ordered and the equal-value order is stable. A helper
that builds a sorted copy and answers it instead fails `tie` and `alias`, which
are the two lines that read the caller's binding.

`files/` mirrors the project layout; the reference solver copies every file in
it over the candidate tree.
