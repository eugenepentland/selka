# Results and options: how it works

Implementation detail moved out of the user guide, [results-and-options.md](../results-and-options.md). Each heading is the guide's heading.

## Flow-sensitive Option guards

This initial implementation lowers guards and payload reads through existing variant dispatch, including a defensive trap for an invalidated payload projection. It does not promise redundant-check elimination or prove integer bounds.

## Error return traces

Each site is a function's position table and an instruction index the compiler already emits, so no text is built while the program runs. Recording a site is one call to a small runtime recorder, on the error path only: an `Ok` passing through `try`, and a `return Ok(...)`, execute nothing extra. A `return` whose value could be either case tests the returned case once. In an LLVM build the recorder keeps every register but one intact, so a recording does not make an optimized loop spill and reload the values it holds in registers.
