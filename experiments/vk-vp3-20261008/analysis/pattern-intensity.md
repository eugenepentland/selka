# Copy intensity: bytes moved per 1,000 instructions retired (ordinary build), per corpus

Summed bytes of the pattern over the corpus's programs, divided by the summed instructions of their ordinary runs. The last column averages the four corpora.

| pattern | lox | eda | parity | rows | mean |
|---|---:|---:|---:|---:|---:|
| P3 element copied out of a list | 11.5 | 103.2 | 2955.7 | 0.0 | 767.6 |
| P1 record moved into a phi slot at a join | 1386.5 | 678.4 | 0.0 | 15.3 | 520.0 |
| P4 record written back into a list element | 99.8 | 2.3 | 1477.8 | 0.0 | 395.0 |
| P2 whole-record copy before a field store | 648.8 | 404.9 | 0.0 | 0.0 | 263.4 |
| P7 record returned through sret | 250.9 | 495.2 | 0.0 | 0.0 | 186.5 |
| P8 other record copy (record_get) | 359.4 | 377.8 | 0.0 | 0.0 | 184.3 |
| P9 copy-on-write of a whole list | 276.6 | 17.9 | 0.0 | 1.1 | 73.9 |
| P6 record pushed into a list | 0.0 | 91.5 | 0.0 | 0.0 | 22.9 |
| P8 other record copy (release) | 3.1 | 84.8 | 0.0 | 0.0 | 22.0 |
| P8 other record copy (union_payload) | 0.0 | 84.7 | 0.0 | 0.0 | 21.2 |
| P5 old element copied out to release it | 67.8 | 2.3 | 0.0 | 0.0 | 17.5 |
| P13 list growth (class move or realloc) | 1.9 | 59.6 | 0.6 | 0.7 | 15.7 |
| P8 other record copy (retain) | 34.0 | 0.3 | 0.0 | 0.0 | 8.6 |
| P14 dictionary, buffer or text growth | 0.0 | 2.9 | 10.3 | 19.7 | 8.2 |
| P8 other record copy (list_get_field) | 7.0 | 0.0 | 0.0 | 0.0 | 1.8 |
| P8 other record copy (record_make) | 1.1 | 0.1 | 0.0 | 0.0 | 0.3 |
| P10 dictionary copy | 0.0 | 0.3 | 0.0 | 0.0 | 0.1 |
| P8 other record copy (union_make) | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 |
| P8 other record copy (dict_entry_value) | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 |
| P8 other record copy (dict_set_value) | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| P11 text copy / view materialized | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| P8 other record copy (dict_insert) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| **all patterns** | 3148.3 | 2406.4 | 4444.4 | 36.8 | 2509.0 |

Instructions: lox 405.5 G, eda 16.9 G, parity 14.2 G, rows 23.8 G
