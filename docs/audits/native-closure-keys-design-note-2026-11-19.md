# Native results keyed by the system libraries, with no approval step (GH-3b, 19 November 2026)

Decision GH-D6: a machine's cache keys come from the digest of its system libraries; a library update is one cold cache; there
is no approval step. This note fixes the reuse rule before code.

## 1. Today

- **Digested:** `tool_identity.inventory` takes the six fixed Debian paths of `src/config_core_tool_platform.zig` (the loader,
  `/lib/x86_64-linux-gnu/{libc.so.6,libm.so.6,libgcc_s.so.1,libpthread.so.0}`, `/etc/ld.so.cache`), `/etc/ld.so.preload`,
  libasan in address mode and the C driver's discovery paths, each stat'ed and resolved by `realpath`. `contents` hashes path,
  resolved path, kind and bytes into the toolchain `digest`. On Fedora (`/usr/lib64/libc.so.6`) four paths are just absent.
- **The compiled-in list** is that file's SHA-256s, `discovery_state` and `address_runtime`.
- **Who asks:** one place, `approvedClosure`/`reviewClosure`, sets `Identity.cacheable` (pinned Zig and library tree,
  `standalone`, no `LD_*` or compiler override, then the list plus `discovery.approved`, else an approval in the file), memoised in
  `core-tools-v1/approval-v3/`. On "no" every consumer sees `cacheable == false`: objects and runtime objects go to private
  staging instead of the per-user store, linked programs and foreign objects are neither looked up nor published, `zig-global`
  and tool recipes are unused (`driver.zig`), replay records are not written (`build_replay.zig:122`), callable digests drop the
  tool (`pipeline.zig:1139`), the test store refuses (`uncacheable-toolchain`), native fixtures and tool tickets are not reused,
  and `native_notice.zig` prints the daily notice. Component preparation fails: the seed-built probe answers 0 and
  `components.zig:276` stops (`UnprovedNativeClosure`). The stage store and the shared compiler store never read the toolchain
  identity; the gate's identity (`verify_cache.py:763`) hashes `/etc/ld.so.cache` itself, with no approval.

## 2. What approval protected against

The fault: a verdict or program made under libc A served under libc B (a glibc fix changes `sin`; the stored verdict says pass).
Keys already prevent it: every key holds `digest`, which hashes the libraries' bytes (NP1.md, "an approval never crosses
closures"). Approval gave two things a key does not: a dpkg check that the bytes are the distribution's, which protects nothing a
key needs (a tampered libc is what every program runs); and the qualification probe, proving the named files are the whole
closure. That one matters, since a key covers only files it names: on Fedora a libgcc_s update keeps the old key today. It is
replaced by finding the closure the way the loader does (3), so nothing needs to build or run a probe.

## 3. The rule proposed

- `cacheable` stops depending on the system libraries and the discovery state; it keeps the pinned Zig, its library tree,
  `standalone`, no unsafe variable, and a preload file that can be keyed soundly (decision 1, section 7).
- **Closure resolved, not listed; the keyed set is a superset of every file the loader could load** (revised after review,
  R1 to R6): the loader at the interpreter path Zig writes, and for each name programs need (`libc.so.6`, `libm.so.6`,
  `libgcc_s.so.1`, `libpthread.so.0`): (a) every entry of `/etc/ld.so.cache` with that name (x86-64 libc6 flags, glibc-hwcaps
  ones included), read at the start of the file or, for the pre-2.32 `ld.so-1.7.0` layout, from the new block after the old
  table (string offsets relative to that block); (b) always, every NUL-terminated absolute path in the cache's bytes whose last
  component is the name, the floor that holds for any format; (c) always, whatever the cache says, every candidate in `/lib64`,
  `/usr/lib64`, `/lib/x86_64-linux-gnu`, `/usr/lib/x86_64-linux-gnu`, `/lib`, `/usr/lib`, each with `glibc-hwcaps/x86-64-v4`,
  `-v3`, `-v2` and the legacy `tls`/`haswell`/`x86_64` subdirectories, because the loader falls back there when a listed file
  cannot be opened. Names compare as `_dl_cache_libcmp` does (digit runs as numbers). The cache's bytes are keyed only when no
  table could be read. A file that exists but cannot be stat'ed, resolved or opened is keyed as unreadable with its error's
  name, the same at capture and refresh, never an error. Preload entries are read as glibc reads them (`#` comments; `$LIB`,
  `$PLATFORM` expanded to every x86-64 value); a relative path, another `$` token or a file over 64 MiB is the one case where
  reuse is off. Each file enters `digest` as today (path, resolved, bytes). No consumer changes: objects, programs, replays,
  verdicts and recipes already take `digest`. The domain becomes `core-tool-content-v5`.
- **`/etc/ld.so.cache`:** today its bytes are keyed and listed, so any install that runs `ldconfig` unapproved the machine
  (16 Oct, 4 Nov, 14 Nov, 18 Nov here; three changed no closure library). Proposed: its bytes leave the key, its status joins
  the generation with a role that forces a fresh resolution. Same resolution and bytes give the same `digest`. Reason: the cache
  matters only through what it maps the names to, and that is keyed.
- **Existing entries** go cold once (new domain); nothing reads them again and `core_store_gc.py` removes them after 14 idle days
  (10 GiB cap). Here, read-only: `core-runtime` 12G, `runtime` 245M, `verification-shared` 954M, `core-tools-v1`
  78M go cold; stage records (1.4G) and the compiler store (5.8G) stay warm.

- **A hint is keyed by the rule that made it (GH-3f, 19 November):** the inventory hint's key holds every constant the candidate
  list is made from (`native_closure.policy`: the names, directories, all 27 subdirectories, token expansions, a rules version),
  so a compiler with another rule never reads a hint a compiler with the old one wrote. Until then the key held the default directories
  but not their subdirectories: a hint of 565 inputs outlived the change to 949, and the identity moved at the next `ldconfig`.

## 4. What goes

The list's digests and `discovery_state` as a gate; `native_approvals.zig`, `native_qualify.zig`, `native_probe.c`; the approvals
file and its readers (compiler, unit runner, CLI fixtures, `selfhost/component_native_approvals.zig`); `UnprovedNativeClosure`;
`native_notice.zig`; the dpkg check; `-Dtest-unreviewed-platform`. `mylang native approve` prints for one release "mylang native
approve is no longer needed: native results are keyed by the system libraries' digest" and exits 0. A new `mylang native show`
prints the resolved closure (path, resolved path, SHA-256) and its digest, so a cold build can be explained.
`MYLANG_NATIVE_APPROVALS` is read by nothing and stays a placement variable for one release. A user's
`~/.config/mylang/native-approvals` is never read, written or deleted; CHANGES says it can be removed.

## 5. What a second machine sees

- **First build:** no notice, no step; cold, and the second build replays. `zig build` passes component preparation (given 7).
- **Library update:** next build cold for native results, front end warm. An install that leaves the closure alone stays warm.
- **A store on a network folder:** different closures write different keys and never serve each other; identical ones (paths,
  bytes, CPU) share. Older compilers keep their `v4` keys beside the new ones; neither reads the other's.

## 6. Tests

As written (after the review, step 2):
- `src/core/native_closure_test.zig` (replaces `native_approvals_test.zig`): the parser and its refusals; a compat cache read
  through its new block; caches written by a real `ldconfig` in both layouts (`test/fixtures/native-closure/`); the scan of
  an unparsable cache; names compared as `_dl_cache_libcmp`; the default candidates kept whatever the cache says; the 24
  legacy subdirectories; the preload file read as glibc reads it (comments, `$LIB`, `$PLATFORM`, refusals); a cache over the
  size limit and a list past the candidate cap turning reuse off.
- `src/core/tool_identity.zig`: an unlisted closure is reusable and a changed byte moves the digest; a rewritten cache mapping
  the same files keeps it; a cache mapping a name elsewhere moves it; without a cache the defaults are keyed; a default
  library moves the digest even when the cache lists the name elsewhere (R1); a non-empty preload keeps reuse on and its
  file's bytes key; a preload emptied; a preload entry that cannot be keyed turns reuse off without an error; a path through a
  regular file, and (not as root) a file that cannot be opened or searched, are keyed as unreadable with no capture failing;
  an approvals file changes nothing. The seam is `MYLANG_TEST_SYSTEM_ROOT`, read only under `builtin.is_test`; a compiler
  built with `-Dtest-system-root=DIR` says so in `native show` and `--version`.
- `test/native_cli_test.zig` and `test/integration.zig`: usage; `native approve` says it is no longer needed; `native show`
  prints the closure, the toolchain identity and `reuse: on`; a build with no `dpkg` and no approvals file replays; the
  empty-`PATH` test runs `native show` and `native approve`.

## 7. Risks, open questions, not checked

- **Decided (coordinator, 02:10 UTC), component preparation:** the seed-built probe (`components.zig` about 100 to 190), the
  check near 276 and `selfhost/component_native_*.zig` go with the seed in lane GH-3a, which owns all of `selfhost/`; this
  lane edits nothing there, and the two `component_support_test.zig` tests above are dropped.
- **Decided (coordinator, 02:10 UTC), `/etc/ld.so.preload`:** reuse stays on; each file it names is keyed like a closure
  library (path, resolved path, bytes); a missing one is keyed as absent, one that exists but cannot be read as unreadable
  with its error's name (the same marker every closure file gets). `LD_*` is unchanged.
- **Where reuse is off on purpose** (the only three cases besides `LD_*` and an unpinned toolchain): a preload entry that
  cannot be keyed soundly (a relative path, a `$` token other than `$LIB`/`$PLATFORM`); a cache or preload file over 64 MiB;
  a candidate list past 4096 files. `native show` prints every reason that holds, not only the first.
- **`--link` and `extern` library flags**, today and after (unchanged here): such a library is not in the closure, so its
  bytes key nothing; a build with link inputs neither replays (`driver.zig:595`) nor serves a test verdict (`native-links`),
  and callable digests drop the tool (`pipeline.zig:1139`); its foreign objects are keyed by their sources and headers.
- Discovery paths were reviewed against Clang for known layouts; Fedora may read one the inventory misses. The explicit
  `x86_64-linux-gnu.2.31` target uses bundled headers and CRT, so I expect no effect; proof 4 checks it. libasan's path stays
  Debian's. NSS, iconv and DNS modules were never keyed and are not now.
- Not checked: Fedora's cache flags in practice, NFS, the cost of a cold complete gate after a library update.
