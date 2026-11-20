# Named callback functions

Lambdas were removed. Declare a top-level function with explicit parameter and
result types, then pass its name as the callback or sort key.

```selka
# doc: expect 12
record Person:
    age: int

func person_age(person: Person) -> int:
    return person.age

func main() -> int:
    mut people = [Person(age=30), Person(age=12)]
    mut ranked = sorted(people, key=person_age)
    return ranked[0].age
```

`E_LAMBDA_REMOVED` recognizes the retired spelling. `selka fix` creates a fresh
named function when the checker can establish its exact parameter and result
types, including inferred sort-key types. The helper stays in the original module.
Functions cannot capture caller locals; pass state explicitly. Generic function
bodies require a manually declared generic helper rather than a repair inferred
from one concrete specialization.
