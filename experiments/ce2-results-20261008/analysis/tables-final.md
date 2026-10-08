## Bytes moved per pattern: CE-X final -> final

**lox**

| pattern | CE-X final | final | change |
|---|---:|---:|---:|
| P1 | 304.92 k | 304.92 k | +0.0% |
| P2 | 7.73 G | 7.73 G | +0.0% |
| P7 | 5.34 G | 5.33 G | -0.0% |
| P8 | 3.30 G | 3.06 G | -7.4% |
| P3 | 4.67 G | 1.66 G | -64.5% |
| P4 | 27.47 G | 27.47 G | +0.0% |
| P6 | 19.53 M | 19.53 M | +0.0% |
| P9 | 2.76 G | 1.07 G | -61.5% |
| P13 | 23.00 M | 23.26 M | +1.1% |
| **all** | 51.32 G | 46.35 G | -9.7% |

**eda**

| pattern | CE-X final | final | change |
|---|---:|---:|---:|
| P1 | 3.10 M | 3.10 M | +0.0% |
| P2 | 1.37 M | 1.37 M | +0.0% |
| P7 | 2.11 G | 2.63 M | -99.9% |
| P8 | 9.45 M | 9.45 M | +0.0% |
| P3 | 673.58 M | 397.98 M | -40.9% |
| P4 | 38.07 M | 38.07 M | +0.0% |
| P6 | 477.60 M | 477.60 M | +0.0% |
| P9 | 6.07 M | 6.07 M | +0.0% |
| P13 | 90.10 M | 90.10 M | +0.0% |
| P14 | 49.00 M | 49.00 M | +0.0% |
| P10 | 4.90 M | 4.90 M | +0.0% |
| P11 | 594.27 k | 595.35 k | +0.2% |
| **all** | 3.47 G | 1.08 G | -68.8% |

**parity**

| pattern | CE-X final | final | change |
|---|---:|---:|---:|
| P3 | 560 | 560 | +0.0% |
| P13 | 8.00 M | 8.00 M | +0.0% |
| P14 | 146.91 M | 146.91 M | +0.0% |
| **all** | 154.91 M | 154.91 M | +0.0% |

**rows**

| pattern | CE-X final | final | change |
|---|---:|---:|---:|
| P1 | 362.94 M | 0 | -100.0% |
| P9 | 26.23 M | 26.23 M | +0.0% |
| P13 | 17.51 M | 17.51 M | +0.0% |
| P14 | 468.25 M | 468.25 M | +0.0% |
| P11 | 148.48 k | 148.48 k | +0.0% |
| **all** | 875.07 M | 512.13 M | -41.5% |

## Target sites

| corpus | pattern | site | CE-X final | after | change |
|---|---|---|---:|---:|---:|
| lox | P7 | `vm.my:264` | 1.11 G | 1.11 G | +0.0% |
| lox | P7 | `vm.my:268` | 2.45 G | 2.45 G | +0.0% |
| lox | P7 | `interpreter.my:668` | 1.77 G | 1.77 G | +0.0% |
| eda | P7 | `sexpr_tokenizer.my (all)` | 1.33 G | 0 | -100.0% |
| eda | P7 | `sexpr_parser.my (all)` | 769.61 M | 0 | -100.0% |
| lox | P3 | `heap.my:361` | 1.51 G | 0 | -100.0% |
| lox | P3 | `heap.my:362` | 1.51 G | 0 | -100.0% |
| rows | P1 | `row_record_pass.my:48` | 362.94 M | 0 | -100.0% |
| eda | P6 | `sexpr_parser.my:225` | 444.83 M | 444.83 M | +0.0% |
| lox | P9 | `table.my:84` | 1.85 G | 154.03 M | -91.7% |

## Highlights

| | CE-X final | after | change |
|---|---:|---:|---:|
| eda_total | 3.47 G | 1.08 G | -68.8% |
| eda_rds3_flat | 238.96 M | 103.34 M | -56.8% |
| rows_record_pass | 362.94 M | 0 | -100.0% |
| lox_read_string | 4.91 G | 4.91 G | +0.0% |
| lox_read_constant | 2.22 G | 2.22 G | +0.0% |

**EDA `sexpr_*` functions (all patterns, site bytes)**

| function | CE-X final | after |
|---|---:|---:|
| `sexpr_tokenizer::next` | 583.07 M | 0 |
| `sexpr_tokenizer::next_in` | 491.84 M | 0 |
| `sexpr_parser::next_token` | 485.90 M | 0 |
| `sexpr_parser::parse_list` | 476.36 M | 476.36 M |
| `sexpr_parser::parse_node` | 283.72 M | 0 |
| `sexpr_tokenizer::read_atom` | 136.95 M | 0 |
| `sexpr_tokenizer::read_number` | 88.15 M | 0 |
| `sexpr_tokenizer::read_string` | 31.43 M | 0 |
| `sexpr_parser::parse_inner` | 416.78 k | 416.78 k |

## Top 10 sites still copying (all corpora)

| # | corpus | pattern | site | detail | function | bytes |
|---:|---|---|---|---|---|---:|
| 1 | lox | P4 | `vm.my:433` | list_set | `vm::run` | 11.09 G |
| 2 | lox | P4 | `vm.my:534` | list_set | `vm::run` | 11.09 G |
| 3 | lox | P2 | `interpreter.my:667` | record_set | `interpreter::execute` | 2.96 G |
| 4 | lox | P7 | `vm.my:268` | ret | `vm::read_string` | 2.45 G |
| 5 | lox | P2 | `vm.my:254` | record_set | `vm::read_string` | 2.45 G |
| 6 | lox | P7 | `interpreter.my:668` | ret | `interpreter::execute` | 1.77 G |
| 7 | lox | P8 | `interpreter.my:346` | list_get_field | `interpreter::evaluate` | 1.60 G |
| 8 | lox | P4 | `heap.my:363` | list_set | `heap::sweep` | 1.51 G |
| 9 | lox | P4 | `heap.my:124` | list_set | `heap::allocate` | 1.50 G |
| 10 | lox | P2 | `heap.my:106` | record_set | `interpreter::execute` | 1.19 G |
