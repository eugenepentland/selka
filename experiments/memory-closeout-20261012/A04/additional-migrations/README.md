# Additional fixture migrations

The coordinator reserved fourteen existing `test/core` sources after the A10
release inventory. `originals.json` and `originals/` preserve C0 bytes; `sources.json`
records every changed source hash and the migration burden. All 42 public test
functions and all existing value assertions and intentional runtime traps remain.
The source changes currently add/remove 43 lines with 43 extra explicit copies.

Snapshots that remain readable after another value changes now call `.copy()`.
Borrowed arguments/elements copied into independent results or containers also use
explicit copies. The old byte `.view()` uses in `s1_bytes` and `t_methods` become
owned slices. These are independent snapshots, not allocation-free borrowed views.
The dedicated A04 positive/negative `.borrow()` tests remain separate. Existing
`s1_views_test.zig` checks the byte fixture's exact output; its assertion is unchanged.

`check-support3-01.json` admits 12/14 sources. Source compiler is support3 commit
`0d17e4e130706639c0f49e78b60502bfb2151ebc`, SHA256
`7b911f91acefccc9dbfd0d1bcfee46e1ec5acc7f47a7ca5954481d44393c7de7`.
This is source admission, not native qualification. The two remaining failures
are retained in the denominator and assigned to A07:

- `conditional_result.my`: the fresh result selected by an expression is treated
  as unavailable merge storage (`E_SINGLE_OWNER_MOVED <conditional>`).
- `optional_loop.my`: a narrowed recursive optional inside a while loop loses its
  hidden payload lifetime (`E_SINGLE_OWNER_MOVED <collection>`).

The original `t_scalar_fusion` fixture contains eight successful tests plus nine
intentional traps; `t_methods` has seven successes plus two intentional traps;
`t_text` has eight successes plus two intentional traps. A guest test command's
nonzero exit alone is therefore not a regression verdict. Exact diagnostic/status
oracles in the registered core tests must remain unchanged and be rerun on the
integrated compiler. `f_features` has five positive guest tests and
`v_buffer_format` has one. The other sources have executable main entrypoints;
string_join/split also require their existing runtime benchmark provider.

No memory or throughput saving is claimed. In particular, explicit recursive
copies in `v_text.length` preserve its old semantics but may increase source-level
copy work; report that tradeoff separately from compiler rendering changes.
