Source: `42041fa45387acade0b14889a9b26da077a1feae`. CPU 10 under `cpu10.lock`; K=4,5,6 in order.

| corpus / arm | cells | geomean | cells >1.03 | verdict |
|---|---:|---:|---:|---|
| rows / B | 5 | 0.997061 | 0 | PASS |
| rows / C | 5 | 0.997773 | 0 | PASS |

| cell | arm | K=4 | K=5 | K=6 | median |
|---|---|---:|---:|---:|---:|
| bytes_scan/64 | B | 0.99925 | 0.97980 | 0.96877 | 0.97980 |
| bytes_scan/64 | C | 1.01772 | 0.98461 | 0.97340 | 0.98461 |
| string_search/64 | B | 1.00628 | 1.01691 | 1.03829 | 1.01691 |
| string_search/64 | C | 1.00930 | 1.05187 | 1.01390 | 1.01390 |
| binary_search/4096 | B | 0.92424 | 0.94694 | 0.95553 | 0.94694 |
| binary_search/4096 | C | 0.93131 | 0.94906 | 0.96288 | 0.94906 |
| json_transform/4096 | B | 1.02237 | 1.02608 | 1.02609 | 1.02608 |
| json_transform/4096 | C | 1.05088 | 1.01137 | 1.02178 | 1.02178 |
| json_transform/64 | B | 1.01026 | 1.02631 | 1.01787 | 1.01787 |
| json_transform/64 | C | 1.03052 | 1.01498 | 1.02153 | 1.02153 |
