# Ranking: finish the in-place ranking helper

The `reading-rank` project sorts readings for a report. One body is not written
yet: `ranking.my` declares the exported helper below with an unfinished typed
hole, so `mylang check` reports `E_TYPED_HOLE` and every command that would run
the program refuses until the hole is filled.

```mylang
public def rank_in_place(readings: list[model.Reading]) -> None effects(mutation) mutates(readings):
    return todo[None]()
```

## What the helper must do

* Order `readings` by **descending** `value`, **in place**: after the call the
  caller's own list holds the result. Do not answer a new list.
* The order is **stable**: two readings with equal `value` keep their original
  relative order.
* Answer nothing: the declared result is `None`.
* Keep the declared contract `effects(mutation) mutates(readings)`. The caller
  passes the list it wants sorted, and an empty or one-element list is left
  alone.

## What must not change

* `model.Reading` keeps its name and its `name` and `value` fields.
* `main.my` keeps printing one `"<name> <value>"` line per reading, in list
  order, and exits `0`.
* Module names and exported signatures are used by other modules.

## Notes

* The compiler is `mylang`, on `PATH`.
* The repository documentation is readable at the `docs` path named in your
  prompt; the structured obligation for the hole travels with the
  `E_TYPED_HOLE` diagnostic under `mylang check --diagnostics=json`.
* An unseen grading probe passes lists with ties, negatives, one element and no
  elements, and reads the result through the same binding the caller passed.
