# Bounded source evaluation in constants

Module constants can call ordinary scalar source functions:

```selka
const CHECKSUM: u64 = checksum(10u64)


func checksum(count: u64) -> u64:
    mut value = 0u64
    for index in range(0u64, count):
        value = wrapping_add(value, index)
    return value


func main() -> i64:
    return i64(CHECKSUM)
```

This extends the existing constant evaluator, which runs inside the checker. It is not an unrestricted macro system, and it is the only way source runs at tool time: there is no separate command that executes a project without building it. No new source keyword is required.

Supported callees are nongeneric free functions with integer/bool parameters and results. Integer aliases are accepted. Arguments evaluate once, left to right. Bodies may contain scalar bindings and assignments, `_ = expression` discards, return, if/else, while, integer range for, break and continue. Calls may recurse within the nesting/work limits. Imported functions retain normal name and visibility checks, and each call has its own lexical locals.

An unsuffixed integer literal (in any base, `0xFF` or `1_000`) takes the type its context declares: the constant's own type, an annotated binding, a call argument's parameter type, a return type, the local an assignment writes, and the type of the other operand of arithmetic or a comparison. `const MASK: u32 = 4278190080` and `twice(0x10)` therefore need no suffix, and a value outside that type is `E_INTEGER_RANGE`.

Validation walks the entire reachable function syntax, including untaken branches and short-circuit operands. Foreign (`extern func`) functions, capabilities, managed values, resource operations, aggregate construction, domain values and unsupported expressions reject. The normal language checker still validates the full program, including unreachable type errors; an invalid program is never built. Constant dependency cycles reject even when short-circuited.

Evaluation shares a fixed 256-level nesting limit and 65,536 work-unit limit across validation, expression/statement execution and name lookup for one constant. Infinite loops and recursion produce located `E_CONSTANT_LIMIT` errors. Invalid arithmetic produces `E_CONSTANT_ARITHMETIC`; forbidden effects/signatures produce `E_CONSTANT_EFFECT` or `E_CONSTANT_TYPE`; unsupported syntax produces `E_CONSTANT_EXPRESSION`. Normal compiler allocation failures propagate and clean up all temporary state. These compile-time budgets are distinct from guest runtime budgets and are not configurable in this stage.

Arithmetic uses the existing fixed-width evaluator, including checked, wrapping, saturating and raw binary64 operations. No target pointer width, host layout or machine addresses enter a computed value. Binary64 operations have the environment requirements specified in [floating-point.md](floating-point.md).

Each compilation evaluates against its complete source and input-module snapshot. Results are cached only within an individual evaluation; no cross-compilation generated-result cache is introduced. Changed imported input source is therefore evaluated anew, while existing compiler/checker cache identity rules continue to include the whole snapshot and compiler identity. Future target-dependent builtins would require an explicit target dependency before they could be admitted.

The final constant getter contains a folded scalar literal. The built program does not rerun the source computation: a regression computes a 1,000-iteration loop during checking, then reads the constant with a ten-step guest budget. Getter calls retain ordinary call/step accounting.

This stage deliberately excludes generated aggregate tables, schema ASTs, generic/domain function evaluation and arbitrary compile-time I/O. Those require further explicit value/authority/budget design. Focused tests cover runtime equivalence, allocation failure, changed input modules, lexical isolation, forbidden effects and located limits; a native example verifies the folded result survives native emission.
