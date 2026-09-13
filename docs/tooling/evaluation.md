# Bounded evaluation

`mylang eval-project` runs a program at tool time instead of at run time: it
checks the project, lowers it, and executes the entry point under explicit step,
frame and byte budgets with no authority injected at all. It is the evaluator
foundation the language's compile-time work is built on, not yet a compile-time
expression form, a schema generator or a build cache. The design records are
[the restricted evaluation foundation](../experiments/restricted-evaluation.md)
and [evaluation dependency reports](../experiments/evaluation-reports.md).

## Bounded scalar source evaluation

The command loads the entry and its declared reachable import graph, checks every
body, and then requires a parameter-free `main` whose inferred transitive effect
set is empty. No allocator, clock, entropy, filesystem, network or environment
provider is supplied: an entry that declares a capability parameter is rejected
with `E_EVAL_INPUT` even when it never reads it, and a reachable effect is
rejected with `E_EVAL_EFFECT` before anything executes. The check covers untaken
branches and recursive calls, while an effectful helper that `main` never reaches
may stay in the project. Budgets default to one million instructions, 256 active
frames and 16 MiB of evaluation-VM storage, and `--max-steps`, `--max-frames` and
`--max-eval-bytes` override them with positive values. The byte budget bounds a
fixed buffer behind the evaluation VM, including bytecode validation, frames and
values, so allocation order and fragmentation can exhaust it even when guest
values were released; it is not a measure of peak live guest data, and source
loading, parsing, checking, lowering and report rendering all sit outside it.
Exhausting the byte quota reports `R_EVAL_MEMORY` at the entry's source start,
while step and frame exhaustion and ordinary traps keep their own locations and
bounded call traces. The result is printed only after a successful evaluation;
`--evaluation-report` adds an `eval-report-v1` document carrying the request
hash, the policy name, the compiler identity, the budgets and every loaded
source's hash, and `--evaluation-request` prints that request without executing.

```mylang
# doc: expect 12
module main

def scale(value: int) -> int:
    return value * 3

def main() -> int:
    return scale(4)
```

```console
$ mylang eval-project app/main.my
12
$ mylang eval-project app/main.my --max-steps=1000 --max-frames=32 --max-eval-bytes=1048576
12
$ mylang eval-project examples/modules/main.my --max-steps=3
shared/units.my:8:20: error[R_STEP_LIMIT]: instruction budget exhausted
          if value < 0 {
                     ^
  in shared.units::Distance.make at shared/units.my:8:20
  in main::main at main.my:10:19
```
