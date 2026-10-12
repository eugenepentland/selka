# Guest RSS measurement correction

The old `Popen(taskset, guest)` plus outer `wait4` measurement reported Python
launcher memory in the child's high-water mark. With a native child touching
1 MiB, increasing the parent allocation from 0 to 256 MiB changed the old result
from 23,340 to 285,264 KiB. The 64 MiB child similarly reported 285,660 KiB under
the large parent. This reproduces the uniform approximately 254 MiB RSS in the
earlier guest pilots; their RSS fields are invalid.

The corrected memory-only runner executes `taskset ... /usr/bin/time ... guest`
and reads GNU time's report for its own guest child. It discards outer rusage and
the memory run's elapsed time. Across three observations at each parent size,
the 1 MiB child reports 2,840 KiB and the 64 MiB child reports 67,320 KiB. The
parent-memory variation has no effect in these controls. This establishes the
measurement boundary; it is not a language/runtime memory comparison.

Streaming the frozen 250 MB compiler's SHA-256 used at most 2,229,377 traced
Python bytes. Runtime records contain no RSS field; memory records contain no
wall-time field. Wrong expected output is rejected. `results.json` pins the
native source/binary, compiler, harness and GNU-time identities. `run.log` records
the ordinary shared build admission with zero queue wait; no timing window was
used, and no control elapsed time is interpreted as performance.

The command was:

```sh
scripts/build-slot.sh build bash -c 'cc -O2 -Wall -Wextra -Werror experiments/memory-closeout-20261012/A09/samples/rss_child.c -o .tmp/memory-closeout/A09/rss-qualification/program && python3 -B experiments/memory-closeout-20261012/A09/qualify_rss.py qualify --binary .tmp/memory-closeout/A09/rss-qualification/program --compiler .tmp/memory-closeout/A09/C0/bin/mylang --output .tmp/memory-closeout/A09/rss-qualification/results.json'
```

`invalid-pilots.json` hashes all three preserved guest pilot files. Their raw
bytes were not rewritten, and their workload-sizing wall observations and exact
outputs remain available. Native capacity measurements already used GNU time's
child report and are outside this defect. A08's sampled tree RSS has separate
sampling/shared-page limitations, unchanged by this repair.
