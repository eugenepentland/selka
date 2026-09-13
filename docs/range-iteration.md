# Integer range iteration

`for index in start..end { ... }` visits a half-open ascending integer range:

```my
fn main() -> i64 {
    let mut total = 0;
    for i in 0..10 {
        if i == 2 { continue; }
        total += i;
        if total > 20 { break; }
    }
    return total;
}
```

The bounds evaluate once, left to right, before the loop begins. They must have
the same integer type; generic bounds require `integer`. Empty and reversed
ranges perform no iterations. The upper endpoint is excluded, so incrementing
the final iteration never needs to exceed the upper endpoint's representable
value.

The iteration binding is immutable and exists only inside the loop body. Each
`continue` cleans up the exited scopes and increments the index before testing
the bound again. `break` cleans up those scopes and skips the increment. Nested
loops always receive their own nearest `break` or `continue`.

Range loops use the same conservative outer-ownership rules and result
obligations as while loops. They support owned values and per-iteration
arenas; exited resources are released before incrementing. The first iteration
may never occur, so a range loop alone does not prove a function returns.

This form covers integer ranges. Collection iteration can currently use indices
with explicit reads; iterator protocols, descending ranges and custom steps are
not implied by this syntax.
