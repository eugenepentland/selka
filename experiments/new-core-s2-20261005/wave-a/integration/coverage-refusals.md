# Complete Wave A coverage refusals

Four corpora: 2321/3619 functions accepted; 1298 refused.

Counts use the inherited sweep's qualified-name deduplication within each corpus.
Raw occurrences also include repeated imported functions.

| First refusal reason | Functions | Raw occurrences |
| --- | ---: | ---: |
| dict type | 354 | 378 |
| bytes type | 326 | 354 |
| fixed array type | 152 | 167 |
| function value type | 53 | 57 |
| capability type | 49 | 97 |
| function_value | 38 | 38 |
| set type | 33 | 34 |
| slice | 28 | 32 |
| write to a list while it is iterated (live-place iteration) | 26 | 26 |
| index | 20 | 23 |
| string index | 15 | 18 |
| split | 15 | 17 |
| shift_right | 11 | 24 |
| f64_sqrt | 10 | 22 |
| equality of a recursive value | 10 | 10 |
| operator on an aggregate value | 9 | 12 |
| text of a non-integer value | 9 | 9 |
| extend | 7 | 7 |
| resource type | 6 | 8 |
| count | 6 | 8 |
| strip | 6 | 7 |
| replace | 6 | 8 |
| number_format | 6 | 6 |
| text_tail | 6 | 6 |
| find | 5 | 6 |
| lower | 5 | 6 |
| upper | 4 | 5 |
| parse_float | 4 | 5 |
| interior mut argument ancestor changed during later argument evaluation | 4 | 4 |
| extern | 3 | 5 |
| host function | 3 | 7 |
| shift_left | 3 | 10 |
| is_digit | 3 | 4 |
| is_alpha | 3 | 4 |
| is_space | 3 | 4 |
| starts_with | 3 | 4 |
| ends_with | 3 | 4 |
| lstrip | 3 | 4 |
| rstrip | 3 | 4 |
| f64_sin | 3 | 6 |
| f64_cos | 3 | 6 |
| f64_to_u64 | 3 | 3 |
| sort_keyed | 3 | 3 |
| index_of | 3 | 3 |
| contains | 3 | 3 |
| array | 2 | 2 |
| float_round | 2 | 2 |
| reverse | 2 | 2 |
| f64_floor | 2 | 2 |
| find_start | 2 | 2 |
| find_range | 2 | 2 |
| text_chr | 1 | 1 |
| saturating_add | 1 | 1 |
| print options | 1 | 1 |
| text_format | 1 | 1 |
| f64_from_u64 | 1 | 1 |
| slice_step | 1 | 1 |
| split_whitespace | 1 | 1 |
| text_ord | 1 | 1 |
| splitlines | 1 | 1 |
| strip_chars | 1 | 1 |
| rfind | 1 | 1 |
| text_repr | 1 | 1 |
| pop_at | 1 | 1 |
| file handle type | 1 | 1 |
| f64_trunc | 1 | 1 |
