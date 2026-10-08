
### lox

| pattern | CE-X final | CE2-A final | change |
|---|---:|---:|---:|
| P1 | 304.92 k | 304.92 k | +0.0% |
| P2 | 7.73 G | 9.22 M | -99.9% |
| P3 | 4.67 G | 4.67 G | +0.0% |
| P4 | 27.47 G | 1.94 G | -92.9% |
| P6 | 19.53 M | 19.53 M | +0.0% |
| P7 | 5.34 G | 6.40 M | -99.9% |
| P8 | 3.30 G | 2.85 G | -13.5% |
| P9 | 2.76 G | 2.76 G | +0.0% |
| P13 | 23.00 M | 23.36 M | +1.6% |
| **P2+P4** | 35.20 G | 1.95 G | -94.5% |
| **all** | 51.32 G | 12.30 G | -76.0% |

### eda

| pattern | CE-X final | CE2-A final | change |
|---|---:|---:|---:|
| P1 | 3.10 M | 4.10 M | +32.1% |
| P2 | 1.37 M | 58.45 k | -95.7% |
| P3 | 673.58 M | 673.58 M | +0.0% |
| P4 | 38.07 M | 37.60 M | -1.2% |
| P6 | 477.60 M | 477.60 M | +0.0% |
| P7 | 2.11 G | 2.11 G | -0.1% |
| P8 | 9.45 M | 7.83 M | -17.2% |
| P9 | 6.07 M | 6.07 M | +0.0% |
| P10 | 4.90 M | 4.90 M | +0.0% |
| P11 | 594.27 k | 595.35 k | +0.2% |
| P13 | 90.10 M | 90.08 M | -0.0% |
| P14 | 49.00 M | 49.00 M | +0.0% |
| **P2+P4** | 39.43 M | 37.66 M | -4.5% |
| **all** | 3.47 G | 3.46 G | -0.1% |

### parity

| pattern | CE-X final | CE2-A final | change |
|---|---:|---:|---:|
| P3 | 560 | 560 | +0.0% |
| P13 | 8.00 M | 8.00 M | +0.0% |
| P14 | 146.91 M | 146.91 M | +0.0% |
| **all** | 154.91 M | 154.91 M | +0.0% |

### rows

| pattern | CE-X final | CE2-A final | change |
|---|---:|---:|---:|
| P1 | 362.94 M | 362.94 M | +0.0% |
| P9 | 26.23 M | 26.23 M | +0.0% |
| P11 | 148.48 k | 148.48 k | +0.0% |
| P13 | 17.51 M | 17.51 M | +0.0% |
| P14 | 468.25 M | 468.25 M | +0.0% |
| **all** | 875.07 M | 875.07 M | +0.0% |

### Lox by step

| pattern | cex | step2 | step34 | step5 | step6 | final |
|---|---:|---:|---:|---:|---:|---:|
| P1 | 304.92 k | 304.92 k | 304.92 k | 304.92 k | 304.92 k | 304.92 k |
| P2 | 7.73 G | 4.16 G | 4.16 G | 9.22 M | 9.22 M | 9.22 M |
| P3 | 4.67 G | 4.67 G | 4.67 G | 4.67 G | 4.67 G | 4.67 G |
| P4 | 27.47 G | 27.47 G | 4.48 G | 4.48 G | 1.94 G | 1.94 G |
| P6 | 19.53 M | 19.53 M | 19.53 M | 19.53 M | 19.53 M | 19.53 M |
| P7 | 5.34 G | 1.77 G | 1.77 G | 6.40 M | 6.40 M | 6.40 M |
| P8 | 3.30 G | 3.30 G | 3.30 G | 3.30 G | 2.85 G | 2.85 G |
| P9 | 2.76 G | 2.76 G | 2.76 G | 2.76 G | 2.76 G | 2.76 G |
| P13 | 23.00 M | 23.65 M | 23.88 M | 23.59 M | 22.83 M | 23.36 M |
| P2+P4 | 35.20 G | 31.63 G | 8.64 G | 4.49 G | 1.95 G | 1.95 G |
| all | 51.32 G | 44.19 G | 21.20 G | 15.28 G | 12.29 G | 12.30 G |

### targets (Lox)

| site | CE-X final | CE2-A final | change |
|---|---:|---:|---:|
| P4 vm.my:433 | 11.09 G | 0 | -100.0% |
| P4 vm.my:534 | 11.09 G | 0 | -100.0% |
| P2 vm.my:254 | 3.56 G | 0 | -100.0% |
| P2 interpreter.my:667 | 2.96 G | 0 | -100.0% |
| P2 heap.my:106 | 1.19 G | 7.00 k | -100.0% |
| P4 vm.my:135 | 814.70 M | 444.38 M | -45.5% |
| P4 heap.my:124 | 1.50 G | 1.50 G | +0.0% |
| P4 heap.my:210 | 586.64 M | 0 | -100.0% |

### highlights

- cex: Lox VM fib(27) 257.4 bytes per dispatch (1.96 G over 7,627,457 dispatches)
- final: Lox VM fib(27) 22.7 bytes per dispatch (173.13 M over 7,627,457 dispatches)

### top 10 sites still copying, all corpora

| # | corpus | site | bytes |
|---:|---|---|---:|
| 1 | lox | P9 `table.my:84` list_copy in `table::set` | 1.85 G |
| 2 | lox | P8 `interpreter.my:346` list_get_field in `interpreter::evaluate` | 1.84 G |
| 3 | lox | P3 `heap.my:361` list_get in `heap::sweep` | 1.51 G |
| 4 | lox | P3 `heap.my:362` list_get in `heap::sweep` | 1.51 G |
| 5 | lox | P4 `heap.my:124` list_set in `heap::allocate` | 1.50 G |
| 6 | lox | P3 `vm.my:525` list_get in `vm::run` | 814.70 M |
| 7 | lox | P3 `vm.my:503` list_get in `vm::run` | 661.48 M |
| 8 | eda | P7 `sexpr_tokenizer.my:270` ret in `sexpr_tokenizer::next` | 583.07 M |
| 9 | lox | P8 `interpreter.my:265` list_get_field in `interpreter::call_node` | 518.97 M |
| 10 | lox | P9 `compiler.my:153` list_copy in `compiler::emit_byte` | 486.04 M |
