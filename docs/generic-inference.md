# Generic call inference

Generic function calls can omit their type arguments when the argument types determine every parameter:

```my
fn identity<T: copy>(value: T) -> T { return value; }
fn first<T: copy, const N: u64>(items: [N]T) -> T { return items[0]; }
fn forward<U: copy>(value: U) -> U { return identity(value); }
fn main() -> i64 {
    return forward(first(new [2]i64[40, 2]));
}
```

`identity(1u8)` infers `u8`; it does not widen the argument. Explicit calls such as `identity::<u8>(1u8)` remain available and share the same specialization. Recursive and mutually recursive calls infer from signatures without expanding bodies during abstract checking.

Inference matches checked argument types against parameter signatures, following fixed arrays (including const lengths), nominal applications, and callback signatures. Generic callers retain their own symbolic type and length identities. Every occurrence of a parameter must agree; `same(1, true)` cannot choose a common type for two `T` inputs. Normal requirements, structural contracts, effects, result handling, and ownership rules apply after inference. Expressions are checked and evaluated once, in their usual order.

The entire list is either explicit or inferred. Return context and requirements alone do not supply arguments: a parameter appearing only in the return type or only in a constraint requires explicit specialization. Inference does not choose defaults, perform coercions, infer nominal constructor syntax, or infer generic function values. Unmaterialized phantom types within nominal arguments also require explicit specialization. Missing or conflicting information produces `E_GENERIC_INFERENCE` with a related parameter declaration when available.

Both the VM and the QBE native backend consume the existing concretely specialized checked program; inference adds no runtime work.
