# Evaluated dictionary write tails

The unchanged two-million-update `dict_count` now executes 44.2% fewer retired
instructions on QBE and 43.8% fewer on LLVM. It still costs 6.5742 and 7.3791 times
the immutable accepted GC binaries. This is a bounded component improvement;
neither row meets the 1.3 limit, and this receipt establishes no whole-corpus
geomean or median-RSS acceptance.

## Measured result

All numbers are median three `instructions:u` observations on CPU 10. Every
receipt reports 100% running. Source size, expected output and accepted GC
binary hashes are fixed. Both compilers are Debug builds; guest QBE builds use
ReleaseFast and actual LLVM builds use O3/full LTO. Counted runs are separate.

| Backend | Accepted GC | RC before | RC after | After/before | Before/GC | After/GC | Above 1.3 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| QBE | 661,305,024 | 7,793,541,000 | 4,347,539,492 | 0.557839 | 11.785093 | 6.574182 | 5.274182 |
| LLVM | 441,034,623 | 5,790,415,595 | 3,254,453,343 | 0.562041 | 13.129163 | 7.379133 | 6.079133 |

Reaching 1.3 from this candidate would require another 80.23% QBE or 82.38% LLVM
instruction reduction. The original first uniqueness and key lifetime traffic
remain substantial; this slice deliberately does not change them.

Counted builds agree exactly between backends:

| Physical counter | Before | After |
| --- | ---: | ---: |
| Ordinary acquires | 2,002,001 | 2,002,001 |
| Ordinary releases | 2,004,031 | 2,004,030 |
| Lifetime hold acquires and releases, each | 12,001,999 | 4,002,001 |
| Uniqueness checks | 4,001,000 | 2,001,000 |
| Heap allocations and retirements, each | 2,030 | 2,029 |
| Clone shells | 0 | 0 |

The one-allocation difference is real and is not hidden in an “otherwise
unchanged” claim. A source-based explanation is that the removed scope held
dictionary backing: `myl_rc_storage_extend` refuses held blocks, whereas the
same original reserve operation may `realloc` an unheld large block. This is an
inference from the unchanged runtime paths, not a traced allocation-site result.
Every execution balances owners, holds and retirements; no count saturates.

## Change and physical proof

The compiler recognizes only the exact evaluated five-op tail
`LOAD root; STORE receiver; LOAD key; LOAD value; BUFFER write`. The original
first root uniqueness stays at its original instruction. Its successful result
cannot change before the raw receiver store. The new certificate removes only
the duplicate uniqueness there and the temporary receiver scope's begin, pin and
end calls. The original dictionary write, root/key/value owners, operand and
private journals, guard storage, receiver scratch, frame linkage and admission,
logical steps and all runtime write failures remain.

The capture is a compiler alias with one raw store and one terminal write use.
Whole-function explicit and implicit writer checks exclude other definitions,
reads, pattern bindings, references, moves, clone installations, projected
places and child aliases. It starts and remains physically empty; the terminal
write does not publish an owner into it. Every normal backedge repeats the same
empty state, and a failed write unwinds instead. Independently, the exact root
load leaves its operand guard empty. No planned release, SHARE, read capture,
field transfer, external middle entry or scope transition occurs in the tail.

Roots must be canonical independent named dictionary homes. Values are nonzero
plain builtin integers or booleans; keys are the same or immutable builtin
strings. Parameters, references, patterns, rebinding, caller storage, held roles,
managed values, projections and alternate borrowed entries refuse. A string key
with semantic `collection_copy` provenance is accepted only after a single
static named canonical store immediately following a list string read. That
store has already acquired its ordinary owner and cleared the input loan before
this tail. Semantic liveness ending at its load does not remove that physical
owner: the unchanged named journal remains until its later store or frame exit.

Function size is at most 4096 instructions. The 262144 allowance charges one
code-length unit after a candidate's shape/type/role preflight succeeds, before
the detailed writer/quiet checks. Preflight itself can scan code and held roles
before that charge. This is successful candidate-code accounting, not a bound
on every primitive visit or total planning work. The complete finite code bound
and conservative refusals remain explicit.

No C runtime, allocator, ownership ABI, selector or GC lowering changes. The
terminal write retains its own staging, region, growth, rollback and drain
contract. Removing unused internal holds can eliminate their private metadata
or count-budget failures; actual first uniqueness, key publication and write
failures remain. The separate design records the reviewed finalizer boundary.

## Negative attempt and emitted/native identity

The first candidate passed the simple positives but declined the real workload:
its list-derived key was tagged `collection_copy`, while the first role check
accepted only `.local`. Its full-size after/before ratios were 0.995910 QBE and
0.999998 LLVM, with unchanged counters. Those receipts and binaries remain in
the archive as the initial negative, not evidence for the final speedup.

The approved refinement keeps the ordinary dictionary root restriction and
admits only the exact immutable-string list-read publication described above.
An added structural test compiles the unchanged benchmark source. Before new
timing, native-policy emission used the exact ReleaseFast drop-debug/step/frame
switches from `qbe_build`: the marker changes 0→1, uniqueness sites 3→2 and scope
begin/pin/end sites each 1→0. The one dictionary write and ownership-frame entry
remain, as do all five textual loan sites. Disassembly of the actual selected
QBE `main` confirms the same helper removal and unchanged surviving loan sites
(four after native dead-code elimination). Actual LLVM manifests verify backend,
O3 and full LTO; they are not QBE runs labeled LLVM.

## Validation and reproducibility

Final validation receipts are recorded in the companion archive. The focused
dictionary tests pass 16/16 (five named plus eleven mandatory unnamed blocks),
and the broader `RC ` filter passes 81/81. The final Debug install, formatting
check and whole-tree Guardian 88/88 pass. Final actual-backend validation has
188 uncached guest assertions, 16 expected trap executions and two finalizer
reentry controls passing. The earlier before/first-candidate controls remain
separate, and the archive verifier checks both sets.

The guest matrix covers insertion/overwrite, snapshots, evaluated key/RHS
callbacks, unoptimized pending callbacks, held views, managed-value fallback,
heap/arena growth, an older heap root used inside an arena and function-wide
string iteration roles. Paired controls preserve memory-budget growth refusal,
arithmetic overflow, step limits and arena/bounds trap codes and output. A native
embedding finalizer enqueues another finalizer, reenters the guest dictionary
loop, and observes the queued callback only after the guest returns. This
substantiates the reviewed active-drain case without changing runtime code.

The immutable source base is `a6a0e00739e44ddbf09b90b5161aa18dd66b4586`.
Before compiler SHA-256 is
`1365b6d176b4bfbbce1b442022877142ef4309ba93a9b07b411a002b7645d7c8`;
after is `e88d13f4d873a19b05c672c01c22219eb0bd2a730f149e4e370062b3dd682ee4`.
Accepted GC uses compiler `f6bea5d9`, SHA-256
`8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`.
All paths, source and binary hashes, commands, stdout/stderr, manifests, raw
instruction receipts, source patch and declined first attempt are preserved in
[the archive](../../experiments/d9-rc-dictionary-tail-20260927/README.md).
The later record-field snapshot correction is outside this isolated comparison;
integration must join it and run the combined gates separately.

## Residual attribution and next proof boundary

The two-million-iteration body still captures the stable keys list, loans its
selected immutable string, then canonically retains that string into the named
key before `get` and write. It also still calls the first dictionary uniqueness
once per update. The remaining counters are consistent with those sites, while
the 1000-key setup and final iteration add smaller traffic. This is static-site
and exact-counter attribution, not an unthrottled cycle profile.

A separate future certificate could compose the list anchor, projected string
and complete key-use interval. It would have to prove the containing list's
physical owner stays live and its contents cannot change through index
evaluation, `get`, first uniqueness and write; retain step/bounds trap order;
account for old key cleanup and every backedge; and keep the dictionary's own
key acquisition at insertion. A borrowed key would explicitly invalidate this
slice's current canonical-O prerequisite, requiring a new shared certificate,
not a relaxed origin test. No such extension is implemented or measured here.
