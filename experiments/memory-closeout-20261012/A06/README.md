# Application qualification

These four deterministic programs exercise application ownership across local
module boundaries. `manifest.json` pins every source file, generated dataset and
independently calculated answer. `freeze.py` generates the datasets and answers;
the language programs reconstruct the same inputs. The numeric sequence is
`(17*i + 11) % 97`; the seven-word vocabulary uses `(17*i + 11) % 7`.
Datasets are lossless gzip archives; the manifest hashes their uncompressed bytes,
including the word corpus's intentional trailing separator.

| Shape | Small / large input | Ownership and error coverage |
| --- | --- | --- |
| Word count | 64 / 8,192 words | A borrowed text input, independent dictionary keys, replacing the input, repeated calls, empty input |
| Nested JSON | 8 / 512 records | Parse/render across modules, replace original input, nested object lookup, integer extraction, wrong field type, malformed document |
| Resource file processing | 64 / 8,192 numeric lines | In-memory filesystem provider, nested scoped files, repeated processing, explicit early error, invalid input, propagated read error through a live file scope |
| Parallel computation | Primality over `[0,4096)` / `[0,262144)` | Ordered map of 1,024-number batches, independently owned result labels, clearing input after join, discarded managed output, 1/2/8 workers |

The filesystem workload exercises scoped resource handles using the deterministic
in-memory provider. It does not measure disk throughput. The parallel program
performs useful CPU work and is separate from the small-callback scheduling probes.
All four shapes use two application modules in addition to any standard library.

`originals/` preserves the existing example files from C0 and the application
sources before explicit-copy migration. The application sources are new workloads,
not pre-existing user programs. Their RC source versions are identical except
that word-count dictionary insertion uses `word` instead of `word.copy()`.
The word-count migration changes one source line and adds one explicit copy site.
No lifetime or ownership names appear in source types. The other three applications
use independent-return library APIs without new explicit copies in application code.

Run from this checkout after sourcing the shared development environment:

```sh
python3 -B experiments/memory-closeout-20261012/A06/qualify.py \
  --compiler /absolute/frozen/install/bin/mylang --zig "$ZIG" \
  --output "$PWD/.tmp/memory-closeout/A06/candidate"
```

Each native guest compilation acquires shared `build` admission. When the harness
already runs inside admission, it uses that reservation without nesting. It checks all five compiler pipelines,
both sizes, exact output, exit status, whole-program managed leaks and RC events,
the emitted ABI marker, and legacy retain/release/share symbols. `--uncounted`
builds separate timing binaries; A09 owns timing admission and paired measurements.
`--ownership default` qualifies ordinary commands after promotion.

Build elapsed fields include admission wait and must not be cited as compiler
performance. Managed counters do not include native provider storage or RSS.
Qualification is a separate result from workload preparation; consult the recorded
compiler hash and per-lane statuses before claiming a program passed.

`timing/` provides separate entrypoints with byte-identical application helper
modules, explicit repetition counts in `argv[0]`, and accumulated checksums so
every iteration contributes to the result. `timing-manifest.json` supplies A09's
measurement harness with initial repetition counts and exact source identities.
A09 can calibrate repetitions before freezing both compiler arms. These entrypoints
preserve the measured computation; correctness-only malformed-input checks remain
in the application matrix. They are a controlled compiler comparison when both
arms use the same timing sources, not a claim about migration-only performance.
