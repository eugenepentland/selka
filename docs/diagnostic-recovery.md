# Checking independent function faults

One `check` or `check-project` invocation reports the first semantic fault in
each independently checked ordinary or generic function. Diagnostics keep their
existing codes and original module byte ranges, sorted by source range and code.
For example, both undefined names are reported here:

```my
# doc: expect-error E_UNKNOWN_NAME
def first() -> i64:
    return missing_first


def second() -> i64:
    return missing_second


def main() -> i64:
    return first() + second()
```

A failed function is abandoned at its boundary. Its unfinished scopes and loans
are not carried into the next function. Multiple callers discovering the same
invalid signature produce one diagnostic for that signature's range and code.
Fixing either independent body leaves the other diagnostic intact.

An error result means checking is incomplete. No typed program or bytecode is
published, execution is rejected, and whole-program ownership/effect/codec passes
are deferred until all bodies pass. Repeating `check`, `emit`, or `execute` on the
same rejected compilation preserves its errors without accumulating duplicates.
Use a new compilation for edited source, as before.

Recovery starts after successful syntax, type-catalog, namespace, and entry-point
construction; failures in those prerequisites can prevent body checking. It does
not invent types or executable function placeholders. Generic contract errors
still allow ordinary bodies to be checked, but concrete generic instantiation
bodies and whole-program effect propagation wait for valid contracts. This keeps
errors actionable without interpreting an incomplete semantic graph as valid.
