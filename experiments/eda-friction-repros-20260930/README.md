# EDA friction reproducers (2026-09-30)

Minimal programs behind [the revised EDA friction repair plan](../../docs/audits/eda-friction-repair-plan-rev2-2026-09-30.md).
Each one was run against main 5041d690 (ReleaseFast) and the EDA port's pin e88fcf3c
(Debug) with the same outcome.

```bash
experiments/eda-friction-repros-20260930/run.sh /path/to/bin/mylang
```

```bash
experiments/eda-friction-repros-20260930/default-oracle/oracle.sh /path/to/bin/mylang
```

`run.sh` prints every program's exit status and first diagnostic lines, then times the
80k-iteration write-back programs. A file whose first line is `module …` is checked
with `check-module`; the others go through `mylang run`. Scratch goes under `$TMPDIR`.

| File | Outcome on 5041d690 | Wanted after the work package |
| --- | --- | --- |
| `wp1/svg_probe.my` (check-module) | `mylang: host failure: InternalError`, exit 2 | located error with the `set()` hint, as the program route gives |
| `wp1/set_ctor_program.my` (run) | `E_UNKNOWN_FUNCTION` at `set[bytes]()` | same, plus the hint |
| `wp1/str_probe.my` (check-module) | declaration accepted; call fails `E_ARITY: str conversion requires one argument` | `E_DUPLICATE_NAME` at the declaration, like the program route |
| `wp1/str_program.my` (run) | `E_DUPLICATE_NAME` at the declaration | unchanged, plus a rename hint |
| `wp1/shadow_earlier_local.my` | `E_SHADOWING` without the earlier declaration's location | still rejected; the message names line 2's `c` |
| `wp2/bytes_default_field.my`, `wp2/bytes_default_param.my` | `E_DEFAULT_ARGUMENT` although the records guide lists byte literals | accepted |
| `wp2/enum_default.my` | `E_DEFAULT_ARGUMENT` | accepted |
| `wp2/list_default.my` | `E_DEFAULT_ARGUMENT` | accepted; a fresh list per construction |
| `wp2/required_after_default.my` | `E_DEFAULT_ARGUMENT` | still rejected without a marker; see `kwonly_record_marker.my` |
| `wp2/kwonly_record_marker.my` | `E_SYNTAX` at `*` | accepted: fields after `*` are keyword-only |
| `wp2/kwonly_function_works.my`, `float_defaults_work.my`, `negative_zero_default_works.my` | work (exit 2, 3; prints `-inf`) | unchanged (controls) |
| `wp3/none_comprehension.my` | `E_TYPE: expected list[Option[int]], found list[unit]` | accepted |
| `wp3/assert_narrow.my` | `E_TYPE: expected int, found Option[int]` | accepted |
| `wp3/field_guard.my` | `E_TYPE: conditional arms must agree` | accepted |
| `wp3/array_compare.my` | `E_TYPE: expected [2]int, found list[int]` | accepted |
| `wp4/mut_record_field.my` | `E_MUTATION_MARKER` | accepted |
| `wp4/writeback_element_80k.my`, `wp4/writeback_dict_80k.my`, `wp4/copy_append_store_80k.my` | 4.9–9.1 s RC (load-dependent), 4.3 s GC: quadratic | well under 0.1 s, like the field form |
| `wp4/writeback_field_80k_fast.my`, `wp4/direct_mut_element_80k_fast.my` | ≤0.01 s | unchanged (controls) |
| `wp4/direct_collection_paths_work.my` | works (exit 33): `mut self.labels`, `self.comps[0].seen.add(...)`, `buckets[i].append(...)` | unchanged; the guide should show these forms |
| `wp6/int_bit_reinterpret.my` | `R_OVERFLOW` at `u64(-1)` | a named bit-preserving conversion exists and this file uses it |
| `fixed/*.my` | already work: nested `for _`, sequential loops reusing a name, `f(x) == Some(v)`, f-string specs | unchanged |

`default-oracle/` is a 4-module project whose record-field and parameter defaults are
edited one by one. Each incremental `--project` build must be byte-identical to a fresh
`--whole-program` build. It matches on main and on `claude/interface-cutoff`. Rerun it
after WP2 changes how defaults are represented.
