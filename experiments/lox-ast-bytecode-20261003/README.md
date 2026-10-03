# Selected AST84 + checked bytecode88 composition

This candidate combines the selected AST call/class projection change with the corrected `list[u8]` bytecode source. It changes no compiler or core source. The selected AST `interpreter.my` is copied unchanged into bytecode author commit `beaaf97c7397beafb0988f5ed73dde0bf4813ebb`'s `octets-shape-v3` source. All 37 files match that rule; the incremental patch changes six files relative to selected AST84 and retains its interpreter exactly. All 84 previous public tests and four added bytecode tests remain, with the bytecode driver's provider fixture structure unchanged.

The bytecode source retains checked indexing, checked byte writes, big-endian jump reads, and original operand/IP publication order. Only the three call-count emission sites mask diagnosed over-limit counts to their clox low byte; valid 0–255 counts are unchanged and failed compilation discards its chunk. The rejected v1 narrowing-trap prototype is excluded. Dispatch loads `u8` before total widening to `int`, and this composition includes no readonly-constant prototype or guarded-byte compiler variant. The AST call/class bodies and root protocol are the selected AST source byte-for-byte.

The private candidate is `/home/epentland/ai/canopy/mylang-worktrees/codex-lox-ast-bytecode-20261003/.tmp-lox-ast-bytecode-20261003/candidate`, built on branch `codex/lox-ast-bytecode-20261003` from `4596805a`. `source.json` pins selected AST, bytecode, and composed 37-file maps. `replay.json` records successful actual application and exact equality of every replayed file. `ast-bytecode.patch` SHA-256 is `abedc2ac23beed4d1f2d340f2e2f0f58ce2ed05f9b5dff6c6d9ee4b600e2b29a`.

To replay from the exact selected AST source into a new private directory, from this worktree:

```sh
cp -a /home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003/.tmp-lox-round3/ast .tmp-lox-ast-bytecode-replay
git apply --directory=.tmp-lox-ast-bytecode-replay experiments/lox-ast-bytecode-20261003/ast-bytecode.patch
```

Compare all replayed files against `source.json.candidate37`. `driver_cases.json` is preserved structurally; these directory qualification commands have no `--cases` and their provider identities are empty. They make no provider-backed execution claim.

The immutable compiler SHA-256 is `d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040`, with adjacent QBE `99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63`. All four actual native ELFs use project builds and retained symbols; LLVM uses optimization level 3 and LTO. Each backend has separate RC and tracing-GC builds, cache, output, and runtime archive. `build.py`, `public.py`, and `validate.py` record exact commands and execute through build slots, outside CPUs 2, 3, 10, and 11. Fresh directories are required because each runner refuses to overwrite its initial receipt.

All 352 public checks passed freshly: 88 tests × LLVM/QBE × RC/native-GC stress, with zero cache hits, failures, skips, dropped, or unloaded tests. These compiler-accounted checks remain separate from actual unaccounted native ELF validation.

Actual composed ELFs were compared against the selected AST RC controls (`180575c3fc2e46a16ed8dd290e289963a87603b5a7c0cf8bb0e03ba7cf794361` LLVM and `246f21781fd58c7141dbe0992101c842e62d732d9ce47e209d55821d02b11b25` QBE). The fresh matrix contains 1,192 bounded comparisons: 26 engine-specific smokes, 34 focused regressions, and 46 historical error cases across the two backends, RC/ordinary tracing GC/native GC stress, and Lox stress off/on. All focused and historical cases run under native stress. Ten other smoke names have 80 explicitly unrun native-GC-stress cells; these are omitted cells, not passes.

Twelve additional actual VM comparisons exercise constants 0 through 255. Another 192 comparisons cover direct/invoke/super calls with 256 arguments, malformed tails/commas and nested valid arguments, and the maximum legal argument/local slot. Ninety-six further comparisons exercise selected AST argument/class construction, allocating nested handlers, reassignment of the bound callee, and errors after side effects. In total, 1,492 actual native program comparisons match exact status, full stdout, full stderr, Lox error traces, and statistics. Eight additional pairs confirm the checked RC rejection of `MYLANG_OPTIONS=--gc-stress` with exit 2 and the `--gc-runtime` diagnostic; those are refusals, not program passes.

All 37 composed and control files, compiler and QBE executables, four candidate ELFs, control ELFs, manifests, receipts, runtime archives, shared helper, historical archives, fixtures, benchmark inputs, generated inputs, and runner files were hashed and verified unchanged. `pack.py` independently rechecks matrix completeness, identity uniqueness, all full stream comparisons, emitted commands, input hashes, source composition/replay, and all fresh public names. `receipts.json.gz` contains exact raw text for every recorded native stream and omission, generated input, native sidecar, public JSON report and stderr, build receipt and log. `qualification.json` pins each archived raw text hash and the archive itself. Its public reports retain their full dependency lists.

The four candidate binaries under the private scratch directory are:

| ELF | SHA-256 |
| --- | --- |
| `combined-rc-llvm` | `03ea51aecb0eecebb369da9eac7bc7a6ae2aaf9d0caaa9e8ba072b5f551d5a2c` |
| `combined-rc-qbe` | `79d0a71d2a53c554131fafff70199bd7dab13c8be36d4abcf4bf3ee4fbc03b4b` |
| `combined-gc-llvm` | `5d663dcf07136f7e9eb560c4cc4731ab5e2e298145d7a8d5cb2e9bd6c4d7c89d` |
| `combined-gc-qbe` | `8c1f6f1c6232376e8478f143c9e0a56a571bc570103680d72d602b499dbff368` |

Malformed internal AST or bytecode native helper-frame attribution may differ between source shapes; valid Lox diagnostics were compared exactly. This receipt runs no performance workloads and makes no speed or parity claim. Root owns canonical source selection and consolidated Guardian feedback.
