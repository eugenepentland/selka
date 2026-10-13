# EDA no-facts cache-plan DiskQuota diagnosis

The failed no-facts mode stopped before planner launch while the compiler wrote
`TMPDIR/mylang-cache-plan-<nonce>/request.bin`. The adapter prints the underlying
I/O error name and returns `ComponentIo` (`src/cache_plan_adapter.zig:114,168–170`).
Zig's threaded filesystem provider maps kernel `EDQUOT` (`DQUOT`) to `DiskQuota`.
This is a host request-file write failure, distinct from the earlier native
exit-70 trial failure and from a guest leak-check result.

`/tmp` is tmpfs mounted with `usrquota`. A read-only `quotactl_fd(Q_GETQUOTA,
USRQUOTA, uid1000)` query succeeds. The first diagnosis measured:

- Hard and soft limits: 12,839,478 × 1,024 = **13,147,625,472 bytes**.
- Current user usage: **12,903,403,520 bytes**.
- Remaining user block-quota headroom: **244,221,952 bytes** (~233 MiB).
- Inode hard/soft limits: zero (unlimited).
- Filesystem-wide `df` availability: about 12 GiB, which does not represent
  this user's remaining quota.

`evidence.json` records a timestamped repeated query, exact limits, usage,
headroom, filesystem availability, mount options, syscall number/command and
successful return/errno. `read-quota.py` reproduces the query without changing
quota, mounts, limits, source, compiler or system state:

```sh
python3 -B experiments/lox-eda-improvements-20261012/P4/diagnosis/quota/read-quota.py
findmnt -no SOURCE,FSTYPE,OPTIONS /tmp
df -h /tmp /home/epentland/ai
df -i /tmp /home/epentland/ai
```

The syscall constants/layout were read from `/usr/include/linux/quota.h` and
`/usr/include/x86_64-linux-gnu/asm/unistd_64.h`. The compiler's Zig toolchain is
`0.17.0-dev.1683+5ceec001b`; its `lib/std/Io/Threaded.zig` maps `.DQUOT` to
`error.DiskQuota` for host filesystem operations. The pinned compiler executable
remains SHA256 `2dcba1cb1a98846bb8c1319575da1b3564e60af70162e195c2fbb6ec3af0f329`.

The coordinator preserves the failed no-facts evidence and retries the same
frozen compiler/source/flags/leak-check setting with fresh cache and TMPDIR on
the root filesystem. No additional native diagnostic jobs were launched.
