# Live dictionary views under counted RC

`run.py` copies the unchanged guest bodies from `dictionary_views.my` and
`rc_dictionary_views.my` into a temporary driver, runs all nine assertions, and
requires complete owner, hold and heap cleanup. The checked-in JSON records
source/compiler/binary hashes, exact commands and counts for both backends.

Run from the repository root with a freshly installed Debug compiler:

```sh
TMPDIR="$PWD/.tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc-collections" \
python3 experiments/d9-rc-held-views-20260926/run.py \
  --compiler .tmp/rc-held-views-final/install/bin/mylang \
  --qbe .tmp/rc-held-views-final/install/bin/qbe --backend qbe \
  --work .tmp/rc-held-views-final/qbe \
  --output experiments/d9-rc-held-views-20260926/qbe.json
```

Repeat with `llvm` and separate work/output paths. These are correctness and
lifetime checks, not a performance acceptance measurement.
