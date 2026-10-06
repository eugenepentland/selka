# S2-X coverage evidence

Source `090dabd5`; compiler source `b70a6a3f`; before compiler `72eaae74`.

| Count definition | Before accepted | Final accepted | Total |
|---|---:|---:|---:|
| Qualified function names, deduplicated within each corpus | 2329 | 3185 | 3627 |
| Per-file function instances | 2756 | 3687 | 4250 |
| Checked loop instances in accepted functions | 607 | 1260 | 1539 |

The standard coverage wrapper checked all four child statuses and complete reports;
all four stderr files are empty. Its run took 71.18 s with RSS 38100 KiB. The
before/after admission and loop comparison took 312.48 s with RSS 38856 KiB.
Both are read-only frontend work, run at nice 10 on CPUs excluding 2, 3, 10 and
11. An initially queued standard-coverage build wrapper was cancelled before
any child started; no native compilation bypassed build-slot admission.

The loop definition counts typed loop instances within independently accepted
whole functions. Loops in a refused function are attributed to that function’s
first refusal, including when the refusal occurs outside its loop. This is not
a standalone loop-fragment check. The unchanged frontend rejected seven example
files and four language files identically for both compilers.

Raw standard reports and checked child statuses are in `coverage-standard/`.
`coverage-standard/all-reasons.json` retains every standard first-refusal count.
`coverage-loops.json` retains every before/after function and loop attribution,
including reasons eliminated by S2. Its legacy totals match the standard report.

The final accepted functions contain 4757 proven and 3764 exact checks, counted
across 3017 qualified function names by the inherited coverage tool.

All 71 remaining observed refusal reasons follow. The per-file count retains
function instances independently in each checked source file. Fixed-array live
dictionary-view storage has an additional precise boundary demonstrated in
`test/core/d_view_identity.my` and design §18; it is outside these four corpora.

| First refusal | Standard functions | Per-file functions | Checked loops |
|---|---:|---:|---:|
| capability type | 52 | 104 | 3 |
| byte_buffer type | 77 | 81 | 42 |
| aggregate storage of live dictionary views | 29 | 29 | 28 |
| shift_right | 12 | 26 | 46 |
| f64_sqrt | 10 | 22 | 25 |
| text of a non-integer value | 18 | 18 | 28 |
| count | 11 | 13 | 3 |
| operator on an aggregate value | 10 | 13 | 6 |
| equality of a recursive value | 11 | 11 | 2 |
| replace | 8 | 10 | 10 |
| shift_left | 3 | 10 | 9 |
| extend | 9 | 9 | 10 |
| find_any | 9 | 9 | 4 |
| view | 9 | 9 | 1 |
| decode | 7 | 8 | 1 |
| interior mut argument ancestor changed during later argument evaluation | 8 | 8 | 0 |
| resource type | 6 | 8 | 0 |
| strip | 7 | 8 | 0 |
| host function | 3 | 7 | 1 |
| live dictionary view of an interior place | 7 | 7 | 8 |
| ordinary dictionary snapshot combined with a live view | 7 | 7 | 6 |
| f64_cos | 3 | 6 | 0 |
| f64_sin | 3 | 6 | 0 |
| lower | 5 | 6 | 0 |
| number_format | 6 | 6 | 0 |
| parse_float | 5 | 6 | 2 |
| parse_int_range | 6 | 6 | 0 |
| extern | 3 | 5 | 0 |
| live dictionary view with unproved source identity | 5 | 5 | 8 |
| text_repr | 5 | 5 | 1 |
| upper | 4 | 5 | 2 |
| contains | 3 | 4 | 0 |
| escaping live dictionary view | 4 | 4 | 4 |
| is_alpha | 3 | 4 | 0 |
| is_digit | 3 | 4 | 0 |
| is_space | 3 | 4 | 0 |
| lstrip | 3 | 4 | 0 |
| reverse | 4 | 4 | 2 |
| rstrip | 3 | 4 | 0 |
| text_chr | 4 | 4 | 10 |
| array | 3 | 3 | 0 |
| f64_to_u64 | 3 | 3 | 0 |
| find_range | 3 | 3 | 1 |
| index_of | 3 | 3 | 0 |
| rfind_range | 3 | 3 | 0 |
| text_ord | 3 | 3 | 4 |
| aggregate or captured dictionary alias combined with a live view | 2 | 2 | 3 |
| dictionary key type | 2 | 2 | 0 |
| f64_floor | 2 | 2 | 0 |
| find_start | 2 | 2 | 0 |
| float_round | 2 | 2 | 0 |
| hex | 2 | 2 | 2 |
| keyword call with a mut argument that is not a local | 2 | 2 | 0 |
| list storage of live dictionary views | 2 | 2 | 4 |
| mut live dictionary view argument | 2 | 2 | 2 |
| rebinding a live dictionary view | 2 | 2 | 1 |
| strip_chars | 2 | 2 | 0 |
| f64_from_u64 | 1 | 1 | 0 |
| f64_trunc | 1 | 1 | 0 |
| file handle type | 1 | 1 | 0 |
| from_hex | 1 | 1 | 0 |
| parse_int receiver | 1 | 1 | 0 |
| pop_at | 1 | 1 | 0 |
| print options | 1 | 1 | 0 |
| record field type | 1 | 1 | 0 |
| rfind | 1 | 1 | 0 |
| saturating_add | 1 | 1 | 0 |
| scalar_count | 1 | 1 | 0 |
| slice_step | 1 | 1 | 0 |
| splitlines | 1 | 1 | 0 |
| text_format | 1 | 1 | 0 |
