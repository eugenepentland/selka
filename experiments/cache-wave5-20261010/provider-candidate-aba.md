This Linux glibc probe demonstrates why direct loader-directory membership alone
does not guard a skipped library symlink's external target. A wrong ELF class is
skipped and the normal libc provider is selected. Writing compatible bytes to the
same external target inode temporarily selects the search-directory candidate;
restoring the wrong class restores the original provider. The search symlink's
stat identity remains unchanged throughout.

The first successful normalized-path probe ran through build admission ticket
832. The retained reproducer uses the same mutations and records JSON. It invokes
system `ldd` on `/usr/bin/true`, without executing guest main or a compiler. All
copied ELF data stays in a temporary directory and is deleted afterward; no
binaries are retained here.

The retained result was produced with:

```sh
env TMPDIR="$PWD/.mylang-cache/cache-wave5/tmp" PYTHONDONTWRITEBYTECODE=1 \
  scripts/build-slot.sh build python3 -B \
  experiments/cache-wave5-20261010/provider-candidate-aba.py \
  > experiments/cache-wave5-20261010/provider-candidate-aba.json
```

This is correctness evidence for watching symlink targets and missing target
parents, including targets of currently rejected loader candidates. It is not a
performance measurement, cache receipt, or compiler fuzz coverage result.
