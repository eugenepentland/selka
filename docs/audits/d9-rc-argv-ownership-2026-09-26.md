# Native argv ownership and the Lox exit imbalance

The four live allocations and six outstanding owner tokens observed after a
reduced Lox VM benchmark came entirely from native argument startup. They were
not retained VM state. On the frozen `685e2631` compiler, even
`main(args: list[str], out: Stream)` printing only `len(args)` left one live
allocation with no arguments, three with one argument, and four with two.
Both actual backends reproduced this; an entry without argv and a literal-path
filesystem read both balanced.

For a nonempty argument vector, the live objects were the list header, its raw
backing, and one text object per argument. The entry adapter never released the
list owner after calling borrowed `main`. The constructor also retained each
fresh text owner after append had acquired the list's own child edge. Thus the
list and backing had one owner each, and every text had two. With two arguments,
that is four allocations and six owner tokens. No allocation instrumentation or
VM patch was needed to explain the counts.

## Change and failure ordering

`myl_qbe_argv_list` now releases the fresh text token after append. If text
construction or append refuses, it releases the partial list before reporting
failure: reporting can immediately unwind with `longjmp`. The caller still owns
nothing until the helper returns a completed list, preventing double cleanup.

The generated native entry registers one construction journal slot before
building argv. Its pointer starts null and receives the returned owner before
capability grants or the borrowed guest call. Normal and nonzero guest returns
clean and leave the frame; traps unwind it through the existing runtime journal.
The construction slot uses a pointer-sized type and the allocation's registered
header descriptor, so no synthetic list-slot registration or ABI change is
needed. All added entry code is conditional on RC. GC argument construction and
guest-visible results remain unchanged.

## Validation

Validation completed on 2026-09-27; the report keeps the D9 closeout plan date
in its filename.

The production C fixture exercises 15 scenarios under ASan and UBSan and through
the Zig unit wrapper: zero, one, and 257 arguments; refusal at each of the five
allocation positions for three arguments; and append refusal after one committed
text. Failure cases run with both sticky errors and real `longjmp`, with an outer
caller journal guarding a still-null result. All leave no live objects, roots,
journals, or outstanding O/H tokens. The constructor reserves the complete argv
backing up front, so append has no normal allocation site; the fixture injects
its real generation-limit refusal to cover that distinct cleanup branch.

The permanent native build-driver regression compiles and executes the generated
entry and checks counted balance after empty/nonzero entry returns, 257 UTF-8
arguments, a missing-file result, capability denial before the guest, and a guest
bounds trap. Capability denial preserves its existing exit status 2.

Independent standalone controls run the actual QBE and optimized LLVM backends,
with GC stress controls for the same source. They also cover local mutation of a
copied argv snapshot, successful file reads, and frame-budget failure. The raw
records contain commands, compiler/binary hashes, backend checks, outputs, exits,
and full counters. Guest processes have explicit short timeouts; only each
runner's own process group is terminated on timeout.

The matched reduced Lox rerun retains the source and inputs used to discover the
problem. Its ordinary output is unchanged. These diagnostic inputs establish
cleanup correctness; they are not a full-corpus performance or acceptance claim.

| VM input | Allocations | Acquires | Releases before | Releases after | Retirements before | Retirements after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Empty script | 132 | 706 | 832 | 838 | 128 | 132 |
| Binary trees N=4 | 103,577 | 3,817,632 | 3,921,203 | 3,921,209 | 103,573 | 103,577 |
| Binary trees N=5 | 203,635 | 12,320,013 | 12,523,642 | 12,523,648 | 203,631 | 203,635 |

The table is identical on actual QBE and LLVM. Each two-argument VM execution
gains exactly four retirements and six releases;
allocation/acquisition counts do not change. H traffic remains balanced.

Evidence: [commands, inputs, and raw records](../../experiments/d9-rc-argv-ownership-20260926/README.md).
