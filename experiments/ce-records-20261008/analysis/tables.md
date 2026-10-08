
### lox

| pattern | base | step1 | step2 | step3 | final | final vs base |
|---|---:|---:|---:|---:|---:|---:|
| P1 | 562.22 G | 7.05 G | 35.46 G | 35.46 G | 304.92 k | -100.0% |
| P2 | 263.09 G | 76.23 G | 122.31 G | 104.31 G | 7.73 G | -97.1% |
| P7 | 101.74 G | 101.74 G | 101.74 G | 101.74 G | 5.34 G | -94.8% |
| P8 | 164.08 G | 164.08 G | 3.30 G | 3.30 G | 3.30 G | -98.0% |
| P3 | 4.67 G | 4.67 G | 4.67 G | 4.67 G | 4.67 G | +0.0% |
| P4 | 40.46 G | 40.46 G | 27.47 G | 27.47 G | 27.47 G | -32.1% |
| P5 | 27.47 G | 27.47 G | 27.47 G | 27.47 G | 27.47 G | +0.0% |
| P6 | 19.53 M | 19.53 M | 19.53 M | 19.53 M | 19.53 M | +0.0% |
| P9 | 112.14 G | 112.14 G | 112.14 G | 112.14 G | 112.14 G | +0.0% |
| P13 | 751.66 M | 752.64 M | 751.69 M | 750.81 M | 751.03 M | -0.1% |
| **P1+P2+P7+P8** | 1.09 T | 349.10 G | 262.81 G | 244.81 G | 16.36 G | -98.5% |
| **all** | 1.28 T | 534.62 G | 435.35 G | 417.34 G | 188.89 G | -85.2% |

### eda

| pattern | base | step1 | step2 | step3 | final | final vs base |
|---|---:|---:|---:|---:|---:|---:|
| P1 | 11.48 G | 3.37 G | 3.90 G | 3.90 G | 3.10 M | -100.0% |
| P2 | 6.85 G | 3.99 G | 3.99 G | 3.99 G | 1.37 M | -100.0% |
| P7 | 8.38 G | 8.38 G | 8.38 G | 8.38 G | 2.11 G | -74.8% |
| P8 | 9.28 G | 9.28 G | 7.78 M | 7.78 M | 9.45 M | -99.9% |
| P3 | 1.75 G | 1.75 G | 1.75 G | 1.75 G | 1.75 G | +0.0% |
| P4 | 38.41 M | 38.41 M | 38.18 M | 38.18 M | 38.18 M | -0.6% |
| P5 | 38.18 M | 38.18 M | 38.18 M | 38.18 M | 38.18 M | +0.0% |
| P6 | 1.55 G | 1.55 G | 1.55 G | 1.55 G | 1.55 G | +0.0% |
| P9 | 302.26 M | 302.26 M | 302.26 M | 302.26 M | 302.26 M | +0.0% |
| P13 | 1.01 G | 1.01 G | 1.01 G | 1.01 G | 1.01 G | +0.0% |
| P14 | 49.00 M | 49.00 M | 49.00 M | 49.00 M | 49.00 M | +0.0% |
| P10 | 4.90 M | 4.90 M | 4.90 M | 4.90 M | 4.90 M | +0.0% |
| P11 | 592.10 k | 592.64 k | 592.64 k | 592.64 k | 592.64 k | +0.1% |
| **P1+P2+P7+P8** | 35.99 G | 25.01 G | 16.28 G | 16.28 G | 2.13 G | -94.1% |
| **all** | 40.73 G | 29.75 G | 21.02 G | 21.01 G | 6.86 G | -83.1% |

### parity

| pattern | base | step1 | step2 | step3 | final | final vs base |
|---|---:|---:|---:|---:|---:|---:|
| P3 | 42.00 G | 42.00 G | 42.00 G | 42.00 G | 42.00 G | +0.0% |
| P4 | 21.00 G | 21.00 G | 21.00 G | 21.00 G | 21.00 G | +0.0% |
| P13 | 8.00 M | 8.00 M | 8.00 M | 8.00 M | 8.00 M | +0.0% |
| P14 | 146.91 M | 146.91 M | 146.91 M | 146.91 M | 146.91 M | +0.0% |
| **all** | 63.15 G | 63.15 G | 63.15 G | 63.15 G | 63.15 G | +0.0% |

### rows

| pattern | base | final | final vs base |
|---|---:|---:|---:|
| P1 | 363.03 M | 362.94 M | -0.0% |
| P9 | 26.23 M | 26.23 M | +0.0% |
| P13 | 17.51 M | 17.51 M | +0.0% |
| P14 | 468.25 M | 468.25 M | +0.0% |
| P11 | 148.48 k | 148.48 k | +0.0% |
| **P1+P2+P7+P8** | 363.03 M | 362.94 M | -0.0% |
| **all** | 875.16 M | 875.07 M | -0.0% |

```json
{
 "base": {
  "lox_vm_fib_dispatches": 7627457,
  "lox_vm_fib_bytes_per_dispatch": 6393.7610514225125,
  "lox_vm_fib_record_bytes_per_dispatch": 5893.732148998021,
  "lox_vm_run_fib_bytes": 44714690448,
  "eda_rds3_flat_bytes": 3673563854,
  "eda_rds3_flat_record_bytes": 2035326368,
  "eda_sexpr_functions_bytes": {
   "sexpr_tokenizer::advance": 13569568080,
   "sexpr_parser::parse_list": 5475441544,
   "sexpr_tokenizer::next": 4275883040,
   "sexpr_parser::next_token": 3401270600,
   "sexpr_tokenizer::skip_whitespace_and_comments": 2376595920,
   "sexpr_tokenizer::next_in": 1645574352,
   "sexpr_tokenizer::read_atom": 1267576744,
   "sexpr_parser::parse_node": 1247202544,
   "sexpr_tokenizer::read_string": 1161748376,
   "sexpr_tokenizer::read_number": 906152160,
   "sexpr_parser::parse_inner": 6807472,
   "sexpr_tokenizer::is_scale_letter": 0,
   "sexpr_tokenizer::is_unit_letter": 0,
   "sexpr_tokenizer::is_unit_required_scale": 0
  },
  "rows_record_pass_bytes": 363026976
 },
 "step1": {
  "lox_vm_fib_dispatches": 7627457,
  "lox_vm_fib_bytes_per_dispatch": 1065.7422351905752,
  "lox_vm_fib_record_bytes_per_dispatch": 565.7133327660845,
  "lox_vm_run_fib_bytes": 5537534536,
  "eda_rds3_flat_bytes": 3008936066,
  "eda_rds3_flat_record_bytes": 1370698568,
  "eda_sexpr_functions_bytes": {
   "sexpr_tokenizer::advance": 5427827232,
   "sexpr_parser::parse_list": 4956469160,
   "sexpr_tokenizer::next": 4275883040,
   "sexpr_parser::next_token": 3401270600,
   "sexpr_tokenizer::skip_whitespace_and_comments": 1792868784,
   "sexpr_tokenizer::next_in": 1645574352,
   "sexpr_tokenizer::read_atom": 1267576744,
   "sexpr_parser::parse_node": 1247202544,
   "sexpr_tokenizer::read_number": 682034352,
   "sexpr_tokenizer::read_string": 596475656,
   "sexpr_parser::parse_inner": 5834976,
   "sexpr_tokenizer::is_scale_letter": 0,
   "sexpr_tokenizer::is_unit_letter": 0,
   "sexpr_tokenizer::is_unit_required_scale": 0
  },
  "rows_record_pass_bytes": null
 },
 "step2": {
  "lox_vm_fib_dispatches": 7627457,
  "lox_vm_fib_bytes_per_dispatch": 806.3989505283347,
  "lox_vm_fib_record_bytes_per_dispatch": 410.3709553524851,
  "lox_vm_run_fib_bytes": 3890003944,
  "eda_rds3_flat_bytes": 2537151594,
  "eda_rds3_flat_record_bytes": 898934304,
  "eda_sexpr_functions_bytes": {
   "sexpr_tokenizer::advance": 5427827232,
   "sexpr_tokenizer::next": 2526658160,
   "sexpr_tokenizer::skip_whitespace_and_comments": 1792868784,
   "sexpr_parser::parse_list": 1315904496,
   "sexpr_tokenizer::read_atom": 1267576744,
   "sexpr_parser::next_token": 1166149920,
   "sexpr_tokenizer::next_in": 1074910088,
   "sexpr_parser::parse_node": 803175968,
   "sexpr_tokenizer::read_number": 682034352,
   "sexpr_tokenizer::read_string": 596475656,
   "sexpr_parser::parse_inner": 903032,
   "sexpr_tokenizer::is_scale_letter": 0,
   "sexpr_tokenizer::is_unit_letter": 0,
   "sexpr_tokenizer::is_unit_required_scale": 0
  },
  "rows_record_pass_bytes": null
 },
 "step3": {
  "lox_vm_fib_dispatches": 7627457,
  "lox_vm_fib_bytes_per_dispatch": 806.395017369485,
  "lox_vm_fib_record_bytes_per_dispatch": 410.3670221936354,
  "lox_vm_run_fib_bytes": 3890003944,
  "eda_rds3_flat_bytes": 2536746554,
  "eda_rds3_flat_record_bytes": 898529264,
  "eda_sexpr_functions_bytes": {
   "sexpr_tokenizer::advance": 5427827232,
   "sexpr_tokenizer::next": 2526658160,
   "sexpr_tokenizer::skip_whitespace_and_comments": 1792868784,
   "sexpr_parser::parse_list": 1315904496,
   "sexpr_tokenizer::read_atom": 1267576744,
   "sexpr_parser::next_token": 1166149920,
   "sexpr_tokenizer::next_in": 1074910088,
   "sexpr_parser::parse_node": 803175968,
   "sexpr_tokenizer::read_number": 682034352,
   "sexpr_tokenizer::read_string": 596475656,
   "sexpr_parser::parse_inner": 903032,
   "sexpr_tokenizer::is_scale_letter": 0,
   "sexpr_tokenizer::is_unit_letter": 0,
   "sexpr_tokenizer::is_unit_required_scale": 0
  },
  "rows_record_pass_bytes": null
 },
 "final": {
  "lox_vm_fib_dispatches": 7627457,
  "lox_vm_fib_bytes_per_dispatch": 448.03784118350325,
  "lox_vm_fib_record_bytes_per_dispatch": 52.009846007653664,
  "lox_vm_run_fib_bytes": 2908603768,
  "eda_rds3_flat_bytes": 1752998122,
  "eda_rds3_flat_record_bytes": 114780832,
  "eda_sexpr_functions_bytes": {
   "sexpr_tokenizer::next": 583074960,
   "sexpr_tokenizer::next_in": 491835128,
   "sexpr_parser::next_token": 485895800,
   "sexpr_parser::parse_list": 476313632,
   "sexpr_parser::parse_node": 283717336,
   "sexpr_tokenizer::read_atom": 136953400,
   "sexpr_tokenizer::read_number": 88148640,
   "sexpr_tokenizer::read_string": 31433240,
   "sexpr_parser::parse_inner": 416784,
   "sexpr_tokenizer::is_scale_letter": 0,
   "sexpr_tokenizer::is_unit_letter": 0,
   "sexpr_tokenizer::is_unit_required_scale": 0
  },
  "rows_record_pass_bytes": 362938368
 }
}
```
