# Held live views crossing copied codecs

`bridge.my` exposes an admitted live-view parameter and a returned live view.
`before-invoke.json` records the native abort from decoding the input mapping
as an O token and then cleaning it through an H shape. The after responses
record normal values for input and result; `joined-invoke.json` uses the later
joined compiler.

`driver.c` tests the real shared library: ordinary copied-value admission refuses
this managed shape; the codec API accepts input and result, safely rejects a
truncated input, and reports the required output size. `run.py` builds both
backends, executes these five scenarios, and requires all four guest executions
to balance allocations, owners and holds. Results are in `libraries.json`.

```sh
TMPDIR="$PWD/.tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc-collections" \
python3 experiments/d9-rc-held-codecs-20260926/run.py \
  --compiler .tmp/rc-held-bridges-final/install/bin/mylang \
  --qbe .tmp/rc-held-bridges-final/install/bin/qbe \
  --work .tmp/rc-held-bridges-final/probes \
  --output experiments/d9-rc-held-codecs-20260926/libraries.json
```
