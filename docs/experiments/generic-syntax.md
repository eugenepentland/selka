# Declared-requirement generic syntax

This is the frontend stage of track D. Executable generics are **not implemented**.
The parser and interface index retain generic declarations and explicit call
arguments so later specialization can use checked identities and source locations
rather than rewriting source text.

```text
fn choose<T: copy + equality, U: integer>(x: T, y: U) -> T {
    return x;
}
// Explicit type arguments use a distinct suffix:
choose::<i64, u8>(1, 2u8)
```

Requirements are currently retained names, not resolved traits or verified
operator/ownership guarantees. Each type parameter needs a nonempty requirement
list. Duplicate parameters or duplicate requirements on one parameter are errors.
At most 16 type parameters, 16 requirements per parameter, and 16 call type
arguments are accepted. These are frontend resource bounds, not a specialization
budget; the latter still needs implementation.

The `::<...>` suffix distinguishes explicit type arguments from existing relational
expressions. It works after ordinary names, module-qualified names, and domain
methods, and requires an ordinary parenthesized argument list. Existing builtin
forms such as `cast<i64>(...)` keep their syntax. Borrowed-call parsing retains the
same explicit type-argument metadata.

Type parameters and requirements live in the function signature AST; call type
arguments live on the call node. Generic source spans and slices are copied and
relocated by the existing owned AST mapper. The syntax cache retains them across
fresh projects. Exported signature checking treats a function's type parameters
as local type names while still checking privacy for concrete signature types,
including nested array elements. Interface listing still does not check bodies.

Before record collection or function checking, semantic preflight rejects generic
declarations and explicit type arguments with `E_GENERIC_UNSUPPORTED`. This
prevents annotations from being ignored or a template body from accidentally
running as an ordinary function. Thus formatting/parsing/interface inspection can
accept the new syntax, but check/VM/native/schema execution cannot yet accept it.

Acceptance covers owned copies with allocation-failure sweeps, source relocation,
formatter round trips, reference/method call forms, malformed/duplicate lists,
16/17 boundaries, export privacy, and syntax-cache reuse. Full ordinary-language
core tests continue to guard existing parsing and execution.

## Next implementation requirements

- Resolve declared requirements and define the operations they permit, including
  copying/moving, equality, arithmetic, references, and effect bounds.
- Check template bodies against those requirements, including uncalled templates;
  do not infer a universal guarantee from one sample concrete type.
- Intern bounded specializations by resolved declaration and nominal type identity,
  including recursive calls, module ownership/privacy, and deterministic diagnostics.
- Substitute types without changing source identity, preserving result handling,
  reference provenance, resource ownership, cleanup, and transitive effects.
- Integrate concrete instances with VM/C emission, schema/public invocation,
  duplicate discovery, and reference/quality roots; add corresponding acceptance.

Generics remains an open roadmap item until those requirements are implemented
and verified. This frontend milestone is not a narrower completion definition.

Validation: the full core suite passed 540 tests in Debug and ReleaseFast, all 60
CLI tests passed, and the final generic-focused run passed seven tests including
the additional qualified-module formatting fixture. All Zig tests compiled and
the build gate passed all 88 Guardian checks without baselines. No executable
generic or native-specialization acceptance is claimed.
