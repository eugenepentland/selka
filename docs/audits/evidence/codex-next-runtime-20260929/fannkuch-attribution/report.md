# Exact LLVM fannkuch attribution

The new plain-ready inlining composition adds **73,732,151 simulated instructions** over the exact publication predecessor. The increase is in `entry_run`: repeated header reloads and register copies, rather than executed readiness helpers or extra element addressing arithmetic. This is a read-only attribution receipt; it is not a new corpus measurement or acceptance gate.

| Frozen side | Existing root dev hardware instructions | Independent Callgrind instructions |
|---|---:|---:|
| approved A5 `m17-codex` | 1,978,610,622 | 1,978,701,964 |
| publication `phase-b-publish-combined` | 1,978,607,977 | 1,978,697,982 |
| plain-ready `phase-b-plain-combined` | 2,052,340,072 | 2,052,430,133 |

The hardware counts above are copied from root's existing result files. No hardware sampling was performed here. The simulated publication-to-plain delta is +73,732,151; A5-to-publication is -3,982, and A5-to-plain is +73,728,169. The two kinds of measurements have distinct absolute totals and are not equated.

Each of the three exact frozen compilers rebuilt only fannkuch with the original LLVM3/full-LTO/RC options plus `--keep-symbols`. Every **26 allocated ELF sections**, including section addresses, flags, sizes, alignment, offsets and payload hashes, is identical to its stripped original. These are exact machine-code/data counterparts. All three admitted Callgrind executions used CPU4, passed with the same expected output, and kept caches/TMPDIR in this owned worktree. Binary, compiler, source and profiler digests remained stable before and after. No shared source was edited or Guardian gate invoked.

The exact publication-to-plain accounting is:

| Matched region / change | Instructions added |
|---|---:|
| Copy all ten permutation elements: ten extra source-header stack reloads ×3,628,800 permutations | +36,288,000 |
| Flip-prefix loop: two extra register moves ×22,169,434 iterations | +44,338,868 |
| Removed executed alignment nop before the flip loop | -3,265,920 |
| Removed one extra stack reload at the next-permutation backedge | -3,628,799 |
| Other `entry_run` instructions | +81 |
| Removed three readiness calls' helper self instructions | -93 |
| Other functions, net | +14 |
| **Total** | **+73,732,151** |

`hot-paths.json` pins the matched address ranges, each executed instruction and reconciliation assertions. The copy region has 330,220,800 versus 366,508,800 self instructions; its comparisons, branches, source/destination storage accesses otherwise have identical opcode counts. The source header was held in `%rsi` in publication and is repeatedly loaded from `-0x38(%rbp)` in plain. There are eleven plain header loads (one length read plus ten element reads) versus one publication header load. The flip region is 1,264,608,443 versus 1,305,681,391; the only counted opcode changes are two added moves at `0x1024880`/`0x10249d0` and removal of 3,265,920 padding instructions. The scalar swap loop performs the same addressing instructions with the same execution counts. The checksum/rotation region totals match exactly. The historical GEP clue therefore does not explain this observed increase. Why LLVM allocates/coalesces registers differently after this inlining change remains an inference, rather than a proved optimization-pass attribution.

Fresh production emission from the exact publication compiler confirms all three fannkuch readiness calls originate in **`qbe_rc_append.emit`**, at `@rcappend_query550`, `@rcappend_query1325` and `@rcappend_query2089`, using cached words `%rcappend0/1/2`. The machine-code call sites `0x1023288`, `0x1023507` and `0x10237e7` execute once each while constructing the three initial lists. They are not `qbe_rc_append_loop.presized` queries. The helper self cost is only 93 instructions, so force-inlining these cold sites has no useful direct instruction saving comparable to the hot-loop increase.

The existing independently archived alloc_churn attribution identifies its publication-predecessor query at `0x100dece` executing 3,000,000 times after capacity growth invalidates cached admission. Fresh publication emission here also uses `qbe_rc_append.emit`, with `@rcappend_query600` and `%rcappend0`, and contains no presized query. Selecting an inline alias only in `presized()` would therefore miss the observed alloc_churn benefit. A general hint based on already-certified nested/re-entered physical append loops is the proposed narrow experiment: leave first-level initialization queries callable/eligible for ordinary auto-inlining, and force-inline only a shared-body alias for queries in a certified loop enclosed by another physical loop. This is a hint about frequency, never an admission or lifetime proof; all null, queue, descriptor, cache and slow-call invalidation logic must remain identical. Candidate source, executable outputs/code shape and subsequent combined corpus results still need verification.

Raw Callgrind outputs, full disassembly, normalized assembly diffs, fresh emitted JSON/QBE and all input digests remain under this directory. `receipt.json` enumerates durable artifacts separately from regenerable caches. Earlier plain-ready/publication review receipts remain untouched.
