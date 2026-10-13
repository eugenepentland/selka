# Toolchain priming for "cold (primed)" builds

A plain cold build starts from an empty `{cache}`. That charges a port for work that is
not its own: Go compiles its standard library into an empty `GOCACHE`, and Zig compiles
its build runner, `compiler_rt` and ubsan runtime into an empty global cache. Rust ships
its standard library precompiled, so it pays nothing extra.

For the primed variant, `measure.py compile` / `tests` first run the matching command
from `<lang>/prime.json` with the port's `bench.json` env and the same `{cache}`, then
time the port's own build. `prime.json` maps a profile name (or `test`) to a command run
from its own directory. A language with no `prime.json` is not primed. The primed
programs share no code with the ports.
