# S3 exit timing calibration

These are retained measurements and extrapolations, not an S3-X pass or wall-time receipt. The user requested greater parallelism; the parent matrix now allows three worker requests through the unchanged three build slots, without holding an artificial parent gate. Actual gates retain their gate and build slots. All exclusive Core rebuild and measured test-core checks finish before the overlap.

| Sweep | Retained measurement | 200-case estimate |
|---|---:|---:|
| Number | 50 in 500.67s | 33.4min |
| Extended character/text | 50 in 241.31s | 16.1min |
| S1 | 50 in 300.90s | 20.1min |
| S0 | 50 in 112.01s | 7.5min |
| Functions | 50 in 128.87s | 8.6min |
| Supplementary split | 50 in 145.83s | 9.7min |
| RC | Earlier S2 200 in 393.92s | 6.6min historical |
| Rebinding | Earlier S2 200 in 1327.99s | 22.1min historical |
| Iteration | Earlier S2 200 in 874.58s | 14.6min historical |
| Dictionary | Earlier S2 200 in 1177.99s; slower S3-L 50 in 785.64s | 19.6–52.4min |

The fixed number-first queue with three workers models approximately53–86minutes, before admission, short audit jobs and CPU-lock waits. Whole-kind estimates scale prior measured runs linearly; they do not establish final S3 throughput. A final all40 run measured283.10s. Report-writing time has not been measured.
