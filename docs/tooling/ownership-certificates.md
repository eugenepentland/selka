# Ownership certificates

An ownership certificate states, for one function of a compiled program, who owns each
value its final Core IR holds: the owned values it must destroy or hand over exactly once, the
borrowed values and the owners they live in, the static blocks that are never freed, and the
slots of a container that an owned read has taken. The ownership pass computes all of this to
schedule the destruction of values (`drop`), then used to discard it; with a certificate request
it writes it down. A small validator checks the certificate against the IR (design
[ownership-certificates](../design/ownership-certificates.md)), so a wrong schedule can be refused
instead of freeing a block twice.

Certificates describe the **final IR**, the instructions LLVM emission receives, so they differ
by build mode: `--release` inlines and promotes lists to the stack, a default build keeps more
calls. Emitting them changes nothing else: a build with the flags off is byte for byte the build
without them.

## Emitting ownership certificates

```console
$ selka dump-ir examples/factorial.selka --certificate > factorial.certificates
$ selka build examples/factorial.selka -o /tmp/factorial --emit-certificates /tmp/factorial-certificates
$ ls /tmp/factorial-certificates
module-3d2c6e0b5b0b7f6c9a1f3e0d2c8e4a1b7d9f5c3a6e8b0d2f4a6c8e0b1d3f5a79.certificate
$ selka test tests/lang --force --emit-certificates /tmp/test-certificates
```

- **`selka dump-ir FILE.selka --certificate`** prints the certificates of every function of the
  program on standard output, after the release passes. It exits 1 when a function cannot be
  described and names it on standard error.
- **`selka build FILE.selka -o OUT --emit-certificates DIR`** writes one `UNIT.certificate` file per
  emitted unit into `DIR` (a source module, a generic instance, a compiler adapter, or the single
  `program` unit of a `--release` build), and removes the `.certificate` files of an earlier build that
  are not among them, so `DIR` holds what the last build wrote. Such a build runs the passes itself, so
  it is neither replayed nor served from the optimizer caches.
- **`selka test PATH --emit-certificates DIR`** writes the certificates of each program the tests
  run into `DIR/MODULE/`. A test whose result is served from a receipt builds nothing: add `--force`.
- **`scripts/export_certificates.py --out DIR`** exports the clean corpus (`tests/lang`,
  `tests/value_semantics`, `tests/ported`, `test/core`, `benchmarks/`, `examples/`), counts the functions
  and the unchecked ones, and with `--twice` checks that two runs write the same bytes.

The format is `ownership-certificate-v2`: UTF-8 text, one item per line, deterministic, starting with
the operation-class table. Its grammar is design [section 4.1](../design/ownership-certificates.md#41-format-ownership-certificate-v2).
A constructor with an owned or `emptied` result names the borrowed operands it holds as views (`views %V,…`: their
slot types are not managed, so its destruction leaves them alone); only those may be loans the aggregate holds. A file
of format v1, written before that extra, is refused by name by `selka validate-certificates` and by `certcheck`; a
build writes its certificates afresh, so a v1 directory is replaced on the next `--emit-certificates`.
A function that uses a task group (`with parallel.group()`) is described and validated like any other
(design [section 10](../design/ownership-certificates.md#10-task-groups-package-c6)): a `box_make` that
lends a value to a group carries the extra `lent %G`, and the validator refuses to consume the lender
before the group is joined. Files written before C6 may still mark such a function `unchecked task-group`;
the reader accepts the mark, and the function is counted and never counted as validated.

## Validating ownership certificates

```console
$ selka build examples/factorial.selka -o /tmp/factorial --verify-ownership
selka: ownership: 4 functions validated, 0 unchecked
$ selka dump-ir examples/factorial.selka --certificate --validate > /dev/null
$ python3 scripts/verify_ownership_sweep.py examples --jobs 4
```

The ownership validator checks the certificate of every function the passes finish, before the
function is emitted (design [section 5](../design/ownership-certificates.md#5-the-checks)): each
owned value is consumed exactly once on every path, nothing is used after it is consumed, borrows end
with their owners, borrowed values are never consumed, one instruction never takes what it also reads,
stack values stay put, and every take of a container slot is closed. It imports nothing of the
ownership pass, so a bug in the pass cannot hide in the check.

- **Every compiler validates every function it compiles**, with nothing to ask for, unless `--no-validate` turns it off
  ([certificate validators](native-build.md#certificate-validators)). `--verify-facts`
  makes any compiler do the same, and `--verify-ownership` on `build`, `run` and `test` asks for it
  explicitly and prints `selka: ownership: N functions validated, M unchecked` (since C6 the compiler marks
  no function unchecked: a function that uses a task group is validated like any other).
- **A rejection is an internal compiler error.** The build exits 2 and prints `error[E_OWNERSHIP_VALIDATION]`
  with the function, the block and instruction, the judgment (`J1` to `J8`), the nearest source rule and
  what failed. Validation is part of the unit-object and replay cache keys, and a cached body is reused
  by a validating compiler only when it was validated when it was saved.
- **`selka dump-ir FILE.selka --certificate --validate`** prints the certificate as before, validates each
  function and prints `selka: ownership: N validated, M unchecked, K rejected` on standard error; it
  exits 1 when any function is rejected.
- **`scripts/verify_ownership_sweep.py PATH...`** builds every program under each path that has a `main`
  and runs every file that has tests, all with `--verify-ownership`, then prints per path the programs
  swept, the functions validated and unchecked, the rejections with their reasons, and the programs that
  stopped for another reason (a link that needs a C helper, a test that fails on purpose). It exits 1
  when any program was rejected.

## The gate action `ownership-proof`

```console
$ python3 scripts/ownership_proof.py --compiler zig-out/bin/selka
ownership-proof: lake build ok; 9140 functions in the corpus (4484 files read), 0 checked by the Zig validator and 0 by the Lean checker this run; 4 skipped on the Lean side for size (749 KB, above 100000 bytes; the Zig validator checked them); 249 mutants of 6 programs rejected by both; 7 disagreements (7 known; 51 validator fixtures compared); 1.2 s
$ selka validate-certificates .selka-cache/ownership-certificates/tests/lang/debug
$ selka mutate-certificates program.certificate mutants
$ selka link-certificates .selka-cache/ownership-certificates
$ python3 scripts/verify_cache.py --zig "$ZIG" --profile proofs
```

The complete gate ties the Zig validator to the Lean checker in `proofs/ownership` with one action, `ownership-proof`
(`zig build test-ownership-proof -Dproofs=true`; without the flag the step prints that it was skipped and exits 0, and
the maintainer's coordinator always passes it). With the flag it fails, and never skips, when any part cannot run:

- **The proof check.** `lake build` and `lake exe selftest` in `proofs/ownership`; a build error or a `sorry` fails the
  action. `lake` is found through `SELKA_LAKE` or `$HOME/.elan/bin/lake`, is keyed in the build's environment manifest like
  `zig`, `python3` and `git`, and a machine without Lean fails the action with a message. Lean is a developer and gate
  tool: it is never part of building or using selka.
- **The differential.** The language gate (`zig build test-lang`) writes the certificates of each program it builds with
  `--emit-certificates .selka-cache/ownership-certificates/SUITE/MODE` (see the stamps below), so nothing is lowered a
  second time. For every
  function the Zig validator (`selka validate-certificates`) and the Lean checker (`certcheck`) must give the same
  verdict: `accept`, or `reject` with the same judgment, block and instruction, or `unchecked` with the same reason. A
  disagreement fails the action unless `tests/ownership-proof-known.json` lists it, by the digest of the function's
  certificate, with a reason.
- **The validator's fixtures.** The hand-written functions in `src/core/validate_ownership_test.zig` (each accepted or
  rejected for one judgment) are read from that file and given to both checkers, one file each, so a shape no compiled
  program produces is compared too. The same known list applies.
- **The link.** Each function's callee table names its callees (design [§9, entry 57](../design/ownership-certificates.md)); the validator
  checks each call against its entry, and the link checks each `program` entry against the callee's own `function` and `param` lines,
  found by name among the functions of the program (a directory of certificate files). `selka link-certificates` and
  `certcheck --link` must print the same lines, and there must be none. It spans functions, so it is not part of the per-function
  verdicts and runs each time.
- **The mutants.** The programs in `test/fixtures/ownership-proof/` are lowered, `selka mutate-certificates` makes the
  single-edit faults of `src/core/ownership_mutants.zig` from their certificates, and both checkers must reject every
  mutant; every fault class must produce at least one.

**The certificates are stamped.** `selka test` writes a program's certificates only when it builds the program, and a
test served from a receipt (its own, or one another worktree or session published to the per-user test store) builds
nothing. So a certificate directory holds what the last run that built the programs left in it: after an edit and its
revert it can hold the edit's certificates, and in a new worktree whose tests all hit shared receipts it can hold almost
nothing. Each directory (three suites, a debug run each; the release runs of `-Dtest-release=true` add three more) therefore carries `stamp.json`: the
compiler's identity (`selka validate-certificates --identity`, the digest of its sources, Zig version and mode that
receipts are keyed by) and a digest of the suite's files. `scripts/test_lang.py`, which runs each suite for the gate,
writes the stamp only after a complete run, and empties and rebuilds (`--force`) a directory whose stamp is not the current
one, so a receipt cannot stand in for the build; a run whose stamp is current is not forced. The driver checks the stamps
again before it reads the directories and regenerates a stale one the same way (about 20 s for all six when the object
store is warm), so a gate on a tree that was reverted, or a driver started by hand, checks that tree's certificates.

**The verdicts are shared.** They live in the namespace `ownership-verdicts-v1` of the verification coordinator's shared
store (`$SELKA_VERIFICATION_SHARED_CACHE`, else `~/.cache/selka/verification-shared`; an empty variable turns sharing off,
and the verdicts then stay in `.selka-cache/ownership-proof`), one small checksummed file per verdict, keyed by the digest of
the function's certificate text and the digest of the checker: the Zig verdict under the digest of the validator's sources, the
Lean verdict under the digest of `proofs/ownership` and the Lean toolchain. A key names the checker and the function, so
any worktree and any session of the user may use any verdict: a new worktree finds the Lean verdicts that an earlier gate
computed instead of paying the checker's two minutes on its first gate. A run checks only the functions it has no verdict for,
so after a compiler edit only programs whose final IR changed are checked again, an edit under `proofs/` runs the Lean
checker alone, and an unchanged tree reuses the whole action. The store follows the other shared namespaces
([retention](cache-retention.md#ownership-verdicts)): every process holds a shared lease, collection is least-recently-used
to a bounded number of verdicts and skips a store in use, and a verdict that differs from a stored one is logged and not
published.

**The size cap.** The cap is off by default (`--lean-cap-bytes 0`) since 26 October. Lane 2 made the Lean checker itself
fast (C3.7: the solver's proposal is computed once instead of at every block lookup). The largest corpus function went from
168 s to 0.04 s, and the whole corpus takes about 4 s on one core. `--lean-cap-bytes N` still makes the complete profile skip
a function above N bytes of certificate text that it has no verdict for, and print how many it skipped. The Zig validator
checks every function in every build either way. The checkers run on batches of functions in as many processes as the
admission slot allows CPUs (less one, at most 16), largest functions first.

**The `proofs` profile.** `python3 scripts/verify_cache.py --zig "$ZIG" --profile proofs` is the complete gate followed by one
more run of the `ownership-proof` driver with the cap lifted (`--lean-cap-bytes 0`), under the gate's admission, over the
certificates that gate wrote and with the compiler it built: the Lean checker runs on every function whatever its size. It
selects, keys and certifies exactly what `complete` does, so it shares all of `complete`'s evidence (a `proofs` request
after a passing `complete` reruns nothing but this step), and a failing step fails the request (exit 1) while leaving the
gate's own evidence in place. The step keeps its verdicts in the same store as the gate action, so after one `proofs`
run the capped `complete` runs compare the large functions too until a checker changes. **Run it instead of `complete`
before landing a change to `src/core/own.zig`, to the validator or to anything named `ownership_*`, and to `proofs/`**:
the complete profile can miss a disagreement that only a very large function shows.

## The arithmetic lowering proofs (`arith-proof`)

```console
$ python3 scripts/arith_proof.py
arith-proof: lake build ok (no error, no sorry, axioms audited); templates.txt and FORMULAS.md are what the formulas render (409 cases); 0.8 s
$ cd proofs/arith && lake exe arith-templates --check templates.txt
$ zig build test-core -Dtest-filter="arithmetic sequences"
```

The lowering of `floor_div`, `floor_rem`, `div`, `rem`, `shift_left`, `shift_right`, `convert`, `float_to_int` and
`saturating_add` to LLVM has sign fix-ups, range tests and width-dependent constants. `proofs/arith` (a Lean 4 project,
core Lean only, the toolchain of `proofs/ownership`) proves, at every width the emitter uses, that each emitted sequence
computes what the language says on mathematical integers: it traps exactly when the operation's specification does (a zero
divisor, `MIN // -1`, a shift count outside `[0, width)`, a value the target type cannot hold, a NaN or out-of-range float),
returns the specified value otherwise, and reaches no LLVM undefined behaviour or poison value on the way. `FORMULAS.md` writes the
sequences down with references to `src/core/emit_llvm.zig` and `emit_number.zig`; `AXIOMS.md` says what the theorems assume (the
project declares no Lean `axiom`).

Two checks tie the proofs to the compiler:

- **The templates.** The Lean formulas are rendered as LLVM text (`lake exe arith-templates`, committed as
  `proofs/arith/templates.txt`, one case per operation, type and check mode, 409 in all). The gate action `arith-proof`
  (`zig build test-arith-proof`, `scripts/arith_proof.py`) runs `lake build`, which includes an audit that fails on a `sorry`
  or any axiom other than `propext`, `Classical.choice` and `Quot.sound`, and fails when `templates.txt` or the generated
  blocks of `FORMULAS.md` are not what the formulas render. It runs no compiler and reruns only when `proofs/arith` changes.
- **The emitter.** `src/core/arith_lowering_test.zig`, a test of `zig build test-core`, builds one small function per case as
  Core IR, emits LLVM and compares it, registers renamed and each trap reduced to `trapif CONDITION KIND`, with the template;
  a second test compiles 168 of the cases from tiny source programs (`a // b`, `shift_left(a, b)`, `u8(a)`, ...) through the
  whole compiler and compares them the same way. A change to the emitter or the builder that changes a sequence, or to a
  formula without the compiler, fails one of the two.

`lake` is found as for `ownership-proof` (`SELKA_LAKE`, else `$HOME/.elan/bin/lake`), and a machine without Lean fails the action
with a message. Lean is a developer and gate tool: it is never part of building or using selka.
