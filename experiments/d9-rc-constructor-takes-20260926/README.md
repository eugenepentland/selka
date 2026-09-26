# Constructor transfer diagnostic

`results.json` preserves the private n12 source, before compiler/source identity,
after source patch, exact output, compile commands, both counted runs, and three
interleaved instruction samples. `guests.json.gz` contains all 116 uncached
focused language verdicts. `run.py` and `guests.py` are the original driver files;
they use `.tmp-schematic/constructor-transfer` and the frozen before compiler
under `.tmp-schematic/install-before-constructor/bin`. Recreate those paths to
repeat them. These are diagnostics, not the complete WP-4 acceptance corpus.
