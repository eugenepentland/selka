# The instrument was fighting the sandbox

Status: finding, 19 September 2026, found while mining the cascade transcripts for
the research note's feedback-quality lever. It is not about the designs: it is
about the runner, and it changes how the cascade numbers above it should be read.

## What the transcripts show

Every one of the 80 maintainer and designer sessions hit toolchain failures that
had nothing to do with the change:

```text
error: failed to create output directory
  '/home/epentland/ai/canopy/mylang/.zig-cache/tmp/3f9d9bb0e9ed00e0': ReadOnlyFileSystem
mylang: host failure: NativeToolFailed
```

3,604 such lines across 80 sessions, median 45 per run, minimum 20, maximum 108.
No session escaped it. The agents worked around it — every run still verified, and
the workarounds are visible in the transcripts — but they paid for it in turns.

## Why

`run.py` puts the compiler in each working copy as a symlink to
`experiments/cascade/tools/bin/mylang`. The compiler resolves its *local* Zig
cache from its install location, which through the symlink is the repository —
and the session's `workspace-write` sandbox is rooted at the working copy, so that
directory is read-only. Every native test build therefore failed once on the
cache and had to be retried or redirected.

The round-2 fix set `ZIG_GLOBAL_CACHE_DIR`, which covers the global cache (the
`compiler_rt`/`libubsan` sub-compilations) but not the local one, so the noise
survived the whole sweep.

Reproduced outside the sandbox: running the frozen compiler from a scratch
working copy creates no cache there and writes into the repository instead. With
`ZIG_LOCAL_CACHE_DIR` pointed inside the working copy as well, the run is clean.

## What it cost

Same task, same arm, same compiler, same model; only the runner's environment
changed. `B/T2`:

| run | cost | host-failure lines | steps | compiler seconds |
| --- | ---: | ---: | ---: | ---: |
| 1 | 117,702 | 37 | 43 | 134.8 |
| 2 | 193,521 | 38 | 51 | 102.4 |
| 3 | 108,484 | 71 | 35 | 89.2 |
| **4** (both caches pinned) | **79,332** | **1** | **24** | **65.4** |

Across the 72 scored runs, host-failure noise correlates with session cost at
+0.464 overall and +0.262 within a task — sessions that fought the toolchain
longer cost more, as they must, since the fight is turns.

## What follows

- **The fix is in `run.py`**: both `ZIG_GLOBAL_CACHE_DIR` and
  `ZIG_LOCAL_CACHE_DIR` are forced inside the working copy for the session, the
  verification and the diff, and both are recorded in the run record's `env`
  field so the two cohorts can be separated.
- **The cascade result carries a caveat.** The arms were compared under equal
  conditions, so a systematic cost is a level shift rather than a bias between
  designs. But the friction is *variance*, and variance is what defeated the
  decision rule's first clause: every margin sat inside a spread of 20k–85k
  tokens, and a single fix already moved one cell 29% below its previous best.
  The null result stands as measured; whether it survives a low-noise instrument
  is now an open question worth answering before anything is concluded from it.
- **It also repriced the feedback-quality question.** Before the fix, the most
  common "diagnostic" an agent saw was an infrastructure error, not a language
  error: 91 of the 180 language diagnostics in the scored runs are invocation
  and entry-point confusion (`E_MODULE_NAME` 44, `E_MODULE_READ` 35, `E_MAIN`
  12), and 70 are `E_TYPE: expected i64, found bool` — the Python reflex that
  booleans are integers. Both are candidates for a note that names the
  alternative, which is what velocity lane C3 measures (baseline 0.02, target
  0.95). Any A/B on that has to run on the fixed environment, or it will measure
  the sandbox instead.

## Reproduce

```sh
python3 - <<'PY'
# per-run infrastructure noise, straight from the session logs
import re, subprocess
from pathlib import Path
sessions = Path.home() / '.dsh' / 'sessions'
for d in sorted(sessions.glob('*cascade-work-B-T2-*')):
    text = ''
    for log in d.glob('session-*/session.v3.jsonl.zstd'):
        text += subprocess.run(['zstd', '-dc', '--', str(log)], capture_output=True).stdout.decode(errors='replace')
    print(d.name, len(re.findall(r'host failure|ReadOnlyFileSystem', text)))
PY
```

The `zstd -dc --` matters: these directory names begin with `--`, and without the
separator zstd reads the path as a flag and silently returns nothing.
