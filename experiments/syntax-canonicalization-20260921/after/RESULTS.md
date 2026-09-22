# Post-implementation evidence results

The capture used `zig-out/bin/mylang`, SHA-256
`10ba2f91c1c8e4c7007771526c2ee590f97504d712b59e503d3fd04574bdc4dd`.
That hash was unchanged before and after the run. The parent baseline files were
also unchanged: `evidence.json` remained
`09777fb8f2d440756ee931190dfd5f1ba0eacd857901fbb27bd300dc5246412c`
and `probe.py` remained
`0698d4d63712c5700af91a5e8e259d722088af1f56e1fd8b6e3efcf4bb174de6`.

Every after-case passed its static check except `removed_float_intrinsic`, whose
continued rejection is expected. The behavior program exited successfully and
showed identical builtin/library float results for whitespace, underscores and
infinity, followed by the expected stored-view totals `32` and `30`.

| Fix | Captured evidence |
| --- | --- |
| Shared scalable sorting | Non-key integer and text `sorted` each emit one `myl_native_list_sort` call. Direct `list[str].sort()` does the same. Compared with the baseline, integer-copy sorting falls from 63,829 to 14,271 emitted QBE bytes and text-copy sorting from 105,539 to 14,606. The keyed probe emits two list creations (the result copy and one scratch list) and one scratch clear site. |
| Canonical numeric parsing | `strings.to_float` now passes under `noalloc`; the behavior probe gives the same successful result as `float` for all three inputs. |
| Immediate byte ranges | Slice and view parse probes now pass under `noalloc` and emit `myl_native_bytes_range`, with no slice/view call. The ordinary slice probe shrinks by 1,722 emitted QBE bytes and the view probe by 1,435. |
| F-string assembly | The multi-piece probe replaces four text-concat call sites with one text-join site. The single-text-piece f-string passes under `noalloc` and emits no native runtime call in its source function. |
| Direct text comparison | The minimum-text probe replaces two `myl_native_bytes_encode` sites with one `myl_native_text_compare` site, shrinking from 34,195 to 12,134 emitted QBE bytes. Both `min(list[str])` and `sort.compare_strs` pass under `noalloc`. |
| Known list capacity | List comprehension, range comprehension and `list(range(...))` each pass a computed value to `myl_native_list_new`; none emits a literal zero-capacity argument. |
| Dictionary views | Direct and stored `items()`/`values()` probes pass under `noalloc`, emit indexed dictionary access, and emit no list creation. The behavior probe iterates both stored views successfully. |

The QBE byte counts and call-site counts are static code-shape evidence. This
capture did not measure elapsed time or dynamic allocation counts.
