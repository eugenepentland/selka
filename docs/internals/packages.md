# Local packages: how it works

Implementation detail and measurements moved out of the user guide, [docs/tooling/packages.md](../tooling/packages.md). Each section keeps the heading of the guide section it came from.

## Building and testing with packages

Unlike the other commands, `build` and `test` stage into a directory that stays: one per application directory, at
`packages-v1/<digest of its path>` under `$XDG_CACHE_HOME/selka` (or `~/.cache/selka`), with a lock file beside it
that one run holds until its command ends. Each run rewrites only the files whose bytes changed and removes every file
the snapshot no longer holds, so the build and test caches, which name sources by path and digest, see an unchanged
snapshot as unchanged: the build replays its last identical build and the tests replay their recorded passes. A
changed package (locked again) changes its staged module's bytes, so the binary is built again and the tests that reach
it run again; no new cache key is involved. A test entry's `<stem>.cases.json` is staged beside it. `test` runs no
`project-dependencies`, since a test entry needs no `main` and a directory has no one entry, so its receipt records
`"dependencies": null`.

### Devices in a package

- **The snapshot holds the device.** The verified bytes are staged under `.devices/PACKAGE/` and the build compiles
  them there, never the checkout. A device that names files needs `"allow_links": ["PACKAGE"]`, or the build stops first and
  names the line to add.
