# Compile-time interfaces: design note and prototype plan

23 October 2026 · written for the user's decision · nothing implemented

## Summary

**The idea.** Name a contract once, as a record of function signatures. Write each implementation as one explicit constant that lists its functions. Pass that constant to a generic as a compile-time argument. Every call through the contract is then a direct call, fixed when the program is built:
- no methods;
- no runtime dispatch;
- no search for which implementation applies, because the call site names it.

**Why consider it:**
- reuse: a contract such as "a writer" or "a key with hash and equality" is written once instead of repeated as callback parameters in every signature;
- a guarantee of direct calls in every build mode;
- it fits the netlisp port, where 381 of 559 `anytype` parameters are output writers.

**The honest counter-evidence:**
- release builds already turn today's callbacks into direct calls in every shape probed;
- the Selka EDA port uses 6 function-typed parameters in 31k lines.

So the case is reuse and readability more than speed, and it needs measuring.

**The plan:** a four-stage prototype behind an experimental flag (about 24 h in one lane). It ends in a measured comparison against today's callbacks, and you decide at the end. It would run after phase 3's lanes, before G2's syntax freeze. It's additive syntax, so it could also land after the freeze.

## 1. What Selka has today

**Generics are already compile-time only.** `func f[T](...)`, `record Box[T]` and `enum Slot[T]` get one specialization per concrete argument list when the program is built, with nothing left at run time:
- bounds are `copy`, `equality` and `integer`, plus structural field requirements (`T: copy + field(value: int)`);
- `const N: u64` adds a compile-time length parameter; it is the only compile-time value parameter today (`docs/const-length-generics.md`).

**Operations are passed as function values.**
- A function type is written `func(P, int) -> int`.
- A function value can be passed, returned and stored in a record field. A call through a field goes through a local, `const callback = handler.callback`, because `handler.callback(value)` reads as a method and is refused with `E_COLLECTION_METHOD` (`docs/functions.md`).
- A record of function values is therefore today's runtime "interface value".

**What was removed, and why.** On 14 October you decided:
1. **No methods on user types.** A reviewer can answer "what can this line change?" from the line itself.
2. **Remove scalar domains, `op(...)` requirements and named constraints.** Generics take operations as function values. The reason was one mechanism per concern.

Named constraints were the trait-like feature: they let a generic require that a type own an operation, found by name. A Go interface is a method set, so with no methods it has nothing to name.

The 15 September research (`interface-research-2026-09-15.md`) found checked contracts clearly worthwhile. It said runtime interfaces were plausible, but with an unproven benefit over modules and callbacks, and recommended a trial comparing the two. That trial was never run.

**This proposal keeps both decisions.** Operations stay function values: compile-time ones, named at the call site. Nothing attaches to a type.

### Probes of today's callbacks (main 03e60dfff, ReleaseFast compiler)

| shape | debug build | release build |
|---|---|---|
| `best(items, by_weight)`: a generic search with a comparator | 1 indirect call per comparison | inlined, 0 indirect calls |
| `emit_net[S](mut sink, write, net)`: a writer-style generic with two sinks (`Counter`, `Checksum`) | 7 indirect calls in each specialization | inlined, 0 indirect calls |
| a record of function values passed down three calls | inlined, 0 indirect calls | inlined, 0 indirect calls |

Sources: `~/ai/canopy/mylang-evidence-archive/experiments/compile-time-interfaces-20261023/probes/` (`cb.my`, `writer.my`).

Release is one LLVM unit, and LLVM inlines a known function at a known call site. That isn't guaranteed: a large generic body, many call sites with different functions, or a function value kept in a long-lived record can keep the indirect call. Stage P0 below looks for those shapes. Debug builds are what `mylang test` and the edit loop use, and they always call through the pointer in a generic.

## 2. Evidence from the code being ported

**netlisp** (`~/ai/canopy/eda/src`, 792 files, 669k lines of Zig):
- 559 `anytype` parameters: 319 `w: anytype` and 62 `writer: anytype` (output sinks), 56 `args: anytype` (format arguments), and a few contexts and probes;
- 161 `comptime T: type` generics;
- 43 runtime function pointers: command tables, HTTP handlers and callbacks. These are dynamic by nature, and today's function values cover them.

The dominant pattern is **code generic over where its output goes**: the same emitter writes to a file, a growing buffer, or a byte counter. G3's full port will meet it hundreds of times. In today's Selka each such emitter takes one callback per sink operation and forwards it through every helper it calls.

**The Selka EDA kernels port** (31k lines) uses 6 function-typed parameters and 5 generic functions. Kernels are not where contracts pay; the application layers are.

## 3. The design

### 3.1 Compile-time function arguments

Extend the `const` generic parameter, today `const N: u64`, to function types:

```text
func emit_net[S: copy, const write: func(mut sink: S, value: int) -> Unit](mut sink: S, net: int) -> Unit:
    write(mut sink, net)
    for pin in range(net % 5 + 3):
        write(mut sink, net * 17 + pin)

emit_net[Counter, count_write](mut counter, 7)
```

Rules:
- The argument names a top-level function, or forwards an enclosing `const` function parameter. A lambda doesn't exist; a local function value is refused, because it is a runtime value.
- The function's identity is part of the specialization key, as types and lengths are. `emit_net[Counter, count_write]` and `emit_net[Counter, logged_write]` are different specializations.
- In the body, `write(...)` is a direct call in Core IR: no pointer exists, in debug or release.
- Reading `write` as a value (`const f = write`) gives an ordinary function value, so passing it on to code that takes a runtime callback still works.

### 3.2 Interfaces as named records of function signatures

```text
record Writer[S]:
    write: func(mut sink: S, value: int) -> Unit
    flush: func(mut sink: S) -> Unit

const COUNTER_WRITER: Writer[Counter] = Writer[Counter](write=count_write, flush=count_flush)
const FILE_WRITER: Writer[FileSink] = Writer[FileSink](write=file_write, flush=file_flush)

func emit_net[S: copy, const w: Writer[S]](mut sink: S, net: int) -> Unit:
    const write = w.write
    write(mut sink, net)

emit_net[Counter, COUNTER_WRITER](mut counter, 7)
```

- **The contract** is an ordinary generic record whose fields are function types. Nothing new is declared: `interface` is not a keyword.
- **An implementation** is one module constant whose fields each name a top-level function. Each function must match its field's signature exactly. This constant is the single, explicit "implements" statement. One type may have several implementations (`COUNTER_WRITER`, `COUNTING_DEBUG_WRITER`): there is no coherence or orphan rule, because nothing is looked up by type.
- **A generic takes `const w: Writer[S]`.** Each read of a field of `w` resolves when the program is built to the named function, so every call is direct.
- **Forwarding** passes `w` along as one argument, not one callback per operation.
- **The same record used as a runtime value** (`ops: Writer[S]`, a plain parameter) stays today's dynamic form: explicit, and visibly different in the signature.

### 3.3 How it compares

| | Go interfaces | Rust traits (generic) | Zig `anytype`/`comptime` | Selka today (callbacks) | This proposal |
|---|---|---|---|---|---|
| Resolved | run time (itab) | build time | build time | run time; release usually inlines | build time, guaranteed |
| Where the binding is written | implicit, by method names | `impl` blocks on the type | implicit, by field and method names | at every call, one callback per operation | at the call site, one name per contract |
| Needs methods | yes | yes | yes (decls on types) | no | no |
| Contract written once | yes | yes | no (duck typing) | no | yes |
| Debug-build cost | indirect call | direct | direct | indirect call | direct |

### 3.4 Costs and risks

- **Language rules.** Two additions: `const` function parameters, and constant records of named functions used as `const` parameters. Module constants are scalar only today, so the second widens them to "records whose fields are all named functions".
- **Code size and build time.** One specialization per type and implementation pair: the usual monomorphization cost, under the existing cap of 4,096 function specializations.
- **Inference.** Explicit generic arguments are positional and all-or-nothing today. `emit_net[Counter, COUNTER_WRITER](...)` repeats `Counter`, which the arguments already determine. Partial or named compile-time arguments (`emit_net[w=COUNTER_WRITER](...)`) would be a further rule. This is an open question.
- **The field-call rule.** `w.write(...)` is refused today (`E_COLLECTION_METHOD`). Allowing it for a `const` bundle reads like a method call, and keeping the rule costs one extra line per operation. This is an open question; I'd start by keeping the rule.
- **Incremental builds.** A specialization key gains function identities. Core IR calls by symbol, so editing `count_write`'s body doesn't change the key. The release unit's inlining is already recompiled whole.
- **Teaching.** "A const parameter can be a function, or a record of functions" is one sentence on top of `const N: u64`, but it is a second way to pass operations next to runtime callbacks. The prototype has to show that the split earns its place.

## 4. Prototype plan

One lane (Haiku implementer, my review), behind `--experimental-comptime-functions` so nothing changes for programs that don't use it. Each stage commits with tests. The complete verification runs after P1, P2 and P3.

### P0: measure today's forms, no compiler change (3 h)
Write three workloads in today's Selka, each two ways: callbacks as parameters, and a runtime record of function values.
1. **A netlisp writer slice.** Port one real netlisp module that uses `w: anytype` (a netlist or s-expression writer). Run it with three sinks: a file buffer, a byte counter and a checksum.
2. **A generic open-addressing hash table** keyed through a hash-and-equality pair, with two key types (a string net name and a packed `u64` pin id).
3. **A provider swap for tests.** A small store contract with a real and a fake implementation and one consumer, as in the 15 September workflow.

For each workload record:
- tokens and lines at the contract, at each implementation, and at call sites, and the number of parameters forwarded through each call chain;
- indirect calls in debug and release binaries (objdump, as in §1);
- debug and release wall time, build time and binary size.

Also try to make release keep an indirect call: a large emitter body, ten call sites with different sinks, and a bundle stored in a long-lived record. That tells us how much the guarantee is worth.

### P1: compile-time function arguments (8 h)
- Parser and checker: `const name: func(...)` in generic parameter lists. The argument must be a top-level function or a forwarded `const` function parameter, with `E_GENERIC_*` diagnostics for everything else (local values, wrong signature, a runtime value).
- Specialization keys include the function identity, and the instance name prints it.
- Core IR lowers calls through the parameter as direct calls. Test this in IR, plus a debug-build objdump test with no indirect call.
- Guest tests in `tests/lang/comptime_functions.my`, and refusal tests in Zig.
- An experimental docs page; no `features.json` entry until adoption.

### P2: constant bundles (6 h)
- Module constants of a record type whose fields all name top-level functions, with exact signature checks.
- `const w: Writer[S]` parameters. A field read of `w` resolves when the program is built, and forwarding passes `w` whole.
- Tests: two implementations of one contract, forwarding through three generics, a refused mismatched signature, and a refused runtime record passed as `const`.

### P3: evaluation (4 h, plus a 3 h agent trial)
- Rewrite the P0 workloads with P1 and P2, and take the same measurements.
- **The agent trial the September research asked for:** three Haiku agents per style each implement a new sink and a consumer from the same short spec, once with callbacks and once with bundles. Record time to the first passing test, compiler-repair cycles and tokens.
- Write `experiments/compile-time-interfaces-20261023/REPORT.md` with the tables and a recommendation.

### The decision (yours, after P3)
Adopt only if all of these hold:
1. **Direct calls in every build mode,** shown by construction in IR and in debug binaries.
2. **At least 25% fewer tokens** at call sites and in forwarding chains on the workloads that pass two or more operations.
3. **Build time and binary size within 10%** of the callback versions.
4. **The agent trial is no worse** on repair cycles than callbacks.

Otherwise keep callbacks, delete the experimental flag's code, and record the measurements so the question doesn't reopen without new evidence.

If adopted: remove the flag, add `features.json` entries and a `docs/generics.md` section, and use bundles where they pay in the standard library and the netlisp port's writer layer. It's additive, so no migration is needed.

**Estimate:** about 24 h of lane time (P0 3, P1 8, P2 6, P3 7). It slots in after E1c and K4, and before G2's freeze. Being additive, it could also come after the freeze.

## 5. Open questions for you
1. Should `w.write(...)` be allowed for a `const` bundle, or should calls keep going through a local like today's stored callbacks?
2. Should a call be able to name only its compile-time arguments (`emit_net[w=COUNTER_WRITER](...)`) and infer the rest?
3. Should a runtime record of function values be the documented "dynamic interface" form, so both forms share one contract definition?
