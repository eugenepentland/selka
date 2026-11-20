# Fact certificates

A release build drops the guards of the checks it proves. `src/core/facts.zig` computes an interval for
every value, refines it by the branches that guard it, and marks an overflow, a division or a bounds
check `proven`; the emitter then writes `nsw`/`nuw` arithmetic, unsigned division and `!range`
metadata, so a wrong fact is an out-of-bounds access or undefined behaviour that shows only in a
release build. `--verify-facts` checks the facts at run time, but only on the inputs a test runs.

A **fact certificate** writes the final IR and the final fact tables down, and a validator that shares no
code with `facts.zig` checks them against the IR, so every compiled program is checked, not only the
inputs a test happens to run (design [fact-certificates](../design/fact-certificates.md)). Emitting a
certificate changes nothing else: a build with the flags off is byte for byte the build without them.

## Emitting fact certificates

```console
$ selka dump-ir examples/factorial.selka --fact-certificate > factorial.fact-certificate
$ selka build examples/factorial.selka -o /tmp/factorial --release --emit-certificates /tmp/factorial-certificates
$ ls /tmp/factorial-certificates
program.certificate  program.fact-certificate
$ selka validate-fact-certificates /tmp/factorial-certificates
/tmp/factorial-certificates/program.fact-certificate main accept
/tmp/factorial-certificates/program.fact-certificate factorial accept
summary files=1 functions=2 accept=2 reject=0 errors=0 derived=2 assumed=0 proven=1 unchecked=0
```

- **`selka dump-ir FILE.selka --fact-certificate`** prints the fact certificate of the program after the
  release passes on standard output.
- **`selka build FILE.selka -o OUT --emit-certificates DIR`** writes `program.fact-certificate` next to the ownership
  certificates when the build computed facts (an optimizing build: `--release`, or the default optimized
  debug build, which computes them for a certificate request), and removes the `.fact-certificate` file of an
  earlier build that this one did not write. `selka test PATH --release --emit-certificates DIR` writes one per
  program the tests build, as it does for the ownership certificates.

The format is `fact-certificate-v1`: UTF-8 text, deterministic, one item per line. It lists every function of the
module in order: the interval of each parameter and of the return value, each block with its instructions and
the interval stated for each, the form of every arithmetic operation (`check none`, wrapping; `exact`, checked;
`proven`, unguarded), the counted loops, the list-length facts, and for each `proven` check its **site**: the
operand intervals as seen at the instruction. The grammar is design
[section 4](../design/fact-certificates.md).

## Validating fact tables

```console
$ selka build examples/factorial.selka -o /tmp/factorial --release --verify-facts-static
selka: facts: 2 functions validated, 1 proven checks validated, 0 unchecked, 0 intervals assumed
$ selka validate-fact-certificates /tmp/factorial-certificates --detail
```

The validator does not replay the analysis. It checks that the stated intervals are an **inductive invariant** of
the IR: each stated interval contains what the transfer rule of its instruction derives from the other stated
intervals as seen at the instruction's block (the stated interval narrowed by the branch edges that dominate
it), a phi's contains the hull of its live operands, a counted loop's counter and accumulator survive one more
trip, a block stated dead has no live edge into it, a parameter interval holds at every call of the function,
and each `proven` check follows from the intervals at its site. A certificate that fails is rejected with the
failing check:

| Check | Meaning |
| --- | --- |
| `F1` shape | the certificate does not describe a well-formed function (a line out of order, an undefined or mistyped operand, a constant that does not fit, a predecessor list that disagrees with the terminators, a dominator tree that is not one) |
| `F2` transfer | a stated interval does not contain what its operands give |
| `F3` phi | a phi's interval contains neither the hull of its live operands nor that hull's meet with its counter or reduction bound |
| `F4` loop | a reduction's interval does not contain the bound its step and trip count give |
| `F5` reachability | a block stated dead can be reached |
| `F6` inter-procedural | a call argument or a returned value is outside the interval claimed for it |
| `F7` proven | a `proven` check has no site, or the intervals at its site do not imply it |

- **Every compiler validates the fact tables of every build that computed them** (a `--release` build; the default
  optimized debug build defers its facts), with nothing to ask for; `--no-validate` turns that off.
  `--verify-facts` and `--verify-written-copies` make any compiler do the same, and `--verify-facts-static` on
  `build`, `run` and `test` asks for it explicitly, forces the facts to be computed (the default optimized
  debug build defers them), and prints `selka: facts: N functions validated, ...`. The sabotage modes of the runtime
  checks state false facts on purpose and are not validated.
- **A rejection is an internal compiler error.** The build exits 2 and prints `error[E_FACT_VALIDATION]` with the
  function, block, value, check and what failed. With `--emit-certificates` the build keeps going so the
  certificate exists to inspect, and fails at the end.
- **What the validator accepts without deriving** is counted, never hidden. `assumed` counts the stated
  intervals of kinds it has no rule for (a record field, a dictionary entry, a float conversion) and the few
  results of list reads and calls that a pass after the analysis changed in a way the final IR cannot re-derive.
  `unchecked` counts `proven` checks whose reason is a list length (`list-bound`, `list-fill`, `list-keys`), the checks
  on every edge into a loop (`edge-checked`), a float or another operation without a row. `selka validate-fact-certificates PATH --detail` lists both by
  operation and reason. Both are the gaps the Lean model of the facts closes (plan C7.3): it proves the lists and the reductions of `assumed` that it can, and `proofs/facts/AXIOMS.md` says which remain.

## Fault injection and the gate

```console
$ selka dump-ir test/fixtures/fact-proof/bounded_branch.selka --fact-certificate > base.fact-certificate
$ selka mutate-fact-certificates base.fact-certificate mutants
0.fact-certificate narrow_range main
1.fact-certificate narrow_range main
$ selka validate-fact-certificates mutants
mutants/0.fact-certificate main reject F2 b0 %2
$ python3 scripts/fact_proof.py --compiler zig-out/bin/selka
```

`selka mutate-fact-certificates FILE OUTDIR` writes the single-edit faults of an accepted fact certificate, one
file each, and prints `FILE CLASS FUNCTION` per mutant: a narrowed range, a widened operand, a dropped branch
refinement, a `proven` check with no site or with a site that does not justify it, a wrong `!range`, a loop range
that does not survive a trip, a block wrongly stated dead, a narrowed return interval. The validator must reject
every mutant in the function it edited and in no other; every class must make a mutant of the fixture programs
(`src/core/fact_mutants_test.zig`).

`scripts/fact_proof.py` is the facts half of the gate action `ownership-proof` (see
[ownership-certificates](ownership-certificates.md#the-gate-action-ownership-proof)). It validates every fact
certificate the language gate's runs wrote (the debug runs; the release runs under `-Dtest-release=true`), and it lowers the programs in `test/fixtures/fact-proof/`,
mutates their certificates and requires every mutant to be rejected. The Lean side (package C7.3, `proofs/facts`) is
part of it: the action runs `lake build` in `proofs/facts` (the checker, the soundness proof and its axiom audit), runs
`lake exe factcheck` on the same certificates, and requires the Lean checker to print the same line as the validator for
every function of the corpus and of every mutant (the verdict, and for a rejection the check, block and value), and the
expected verdicts for the fixtures under `proofs/facts/fixtures/`. The agreed lines of each certificate file are kept in the
per-user verdict store by the file's digest and the checkers' identity, so a run checks only the files it has not seen. With
`-Dproofs=true` (which `ownership-proof` needs: without it the whole action is skipped) it fails, never skips; a missing `lake`
fails it.
