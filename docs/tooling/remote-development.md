# Develop on a remote Linux machine

This guide sets up a complete workspace on a remote **Linux x86-64** machine.
Run the commands in Bash on that machine after connecting over SSH. Source,
builds, tests, and caches stay there. An editor such as
[VS Code Remote SSH](https://code.visualstudio.com/docs/remote/ssh) can open the
remote checkout directly.

Run the numbered sections in order, stopping if a command fails. Keep the same
shell through setup so the repository and toolchain variables remain available.

Budget around 32 GiB RAM, 8 CPU cores, and persistent SSD space for comfortable
parallel development. These are planning suggestions, not tested minimums.
The commands below start conservatively with four build jobs and an 8 GiB Zig
scheduling budget.

## Which branch and dependencies to use

Use the **`development` branch** of
[eugenepentland/selka](https://github.com/eugenepentland/selka/tree/development)
for the current compiler, memory-management prototype, and development tools.
GitHub's `main` is an independently published Selka-branded snapshot. The current
development line still uses the `selka` executable, `.selka` files, and
`selka.json`. The clone commands below name the local branch `main`, tracking
`origin/development`, so tools that compare changes against local `main` work
normally. This does not change GitHub's `main`.

The setup uses Guardian commit `ae1ae2899cc60b575e9e1b9212d73eddf9e2df72`,
published as tag `selka-dev-2026-10-11`, for older commits only (below), and the complete Zig distribution in
the repository's `zig-0.17.1` release: the official 0.17.1 tarball from
<https://ziglang.org/download/>, published there by the maintainer step below. Commits before
the move to 0.17.1 name the development snapshot `0.17.0-dev.1683+5ceec001b` in `.zigversion`; its
download URL returned 404, and its tarball is the `zig-0.17.0-dev.1683+5ceec001b` release asset.

The latest Guardian or a newer Zig version is not an automatic substitute.
Maintainers updating these inputs should follow
[Publish the setup inputs](#publish-the-setup-inputs) and validate the pins together.

## 1. Install the development tools

These package commands target Ubuntu 24.04 LTS, x86-64, with an existing SSH
connection and sudo access:

```bash
test "$(uname -s)" = Linux
test "$(uname -m)" = x86_64
sudo apt-get update
sudo apt-get install --no-install-recommends \
  build-essential binutils git gh python3 bash ca-certificates curl xz-utils \
  util-linux coreutils findutils grep sed gawk openssh-client tmux ripgrep
```

GitHub CLI authentication lets the same instructions work with private
repositories and release assets. Authenticate using the interactive login:

```bash
gh auth login
```

Python is needed for developer tooling and parts of the gate. The installed
compiler and ordinary source builds do not require Python. Perf, Valgrind, and
Rust are optional tools for particular benchmarks, not prerequisites for the
normal development gate.

For a long-running SSH session, start `tmux new -s selka-dev`; reconnect with
`tmux attach -t selka-dev` if the connection drops.

## 2. Clone the source and Guardian

Clone Selka into a local directory named `selka` for the remaining examples.
Guardian was turned off on 18 November 2026 (GH-2), and since 19 November (GH-3a)
no build needs it or git history: the Guardian clone below is needed only to build
a commit older than that.

```bash
SELKA_GITHUB_REPO=eugenepentland/selka
mkdir -p "$HOME/src"
cd "$HOME/src"
gh repo clone "$SELKA_GITHUB_REPO" selka -- --branch development
git -C selka switch -c main --track origin/development
gh repo clone eugenepentland/guardian-zig guardian-zig
git -C guardian-zig fetch origin ae1ae2899cc60b575e9e1b9212d73eddf9e2df72
git -C guardian-zig checkout --detach ae1ae2899cc60b575e9e1b9212d73eddf9e2df72
cd selka
```

A depth-1 clone or a source archive builds: the components are compiled by the
compiler the build has just built ([component builds](selfhost-components.md#build-and-install)).

## 3. Install the pinned Zig distribution

From the selka checkout, download the assets published in the maintainer step.
Keep `zig` and its complete `lib/` directory together. The archive checksum is
checked before extraction, and the executable's version is checked afterward.

```bash
zig_version=$(cat .zigversion)
zig_archive="zig-x86_64-linux-${zig_version}.tar.xz"
zig_download="$HOME/Downloads/selka-toolchain/$zig_version"
mkdir -p "$zig_download" "$HOME/.local/share/selka/zig"
gh release download "zig-$zig_version" --repo "$SELKA_GITHUB_REPO" \
  --pattern "$zig_archive" --pattern "$zig_archive.sha256" --dir "$zig_download"
(cd "$zig_download" && sha256sum --check "$zig_archive.sha256") &&
  tar -xJf "$zig_download/$zig_archive" -C "$HOME/.local/share/selka/zig"
test "$("$HOME/.local/share/selka/zig/$zig_version/zig" version)" = "$zig_version"
```

An already downloaded asset makes `gh release download` refuse to overwrite it.
For a repeat installation, reuse it after checking its checksum. Do not replace
the pinned release with the distribution's `apt install zig` or `master`: the
build accepts 0.17.1 or a later 0.17 release and refuses a snapshot, and the gate
uses exactly the version in `.zigversion`. The compiler also recognizes the approved
distribution's contents when deciding whether objects can be reused: only the
official 0.17.1 distribution is approved.

## 4. Configure each shell and worktree

Create this user-local environment file once. Source it **from inside the
checkout you are about to work on**, including after switching worktrees.
It derives paths from that checkout; it contains no original-machine paths.

```bash
mkdir -p "$HOME/.config/selka"
cat > "$HOME/.config/selka/dev-env.sh" <<'ENV'
selka_dev_root=$(git rev-parse --show-toplevel) || return 1
selka_dev_zig_version=$(cat "$selka_dev_root/.zigversion") || return 1
export ZIG="$HOME/.local/share/selka/zig/$selka_dev_zig_version/zig"
test -x "$ZIG" || { echo "Missing pinned Zig: $ZIG" >&2; return 1; }
export SELKA_ZIG="$ZIG"
export PATH="$(dirname "$ZIG"):$PATH"
export ZIG_GLOBAL_CACHE_DIR="$HOME/.cache/selka/zig-global"
export ZIG_LOCAL_CACHE_DIR="$selka_dev_root/.zig-cache"
export TMPDIR="$selka_dev_root/.tmp/work"
export SELKA_SLOT_DIR="$HOME/.cache/selka/slots"
export SELKA_BUILD_SLOTS=1
export SELKA_GATE_SLOTS=1
export SELKA_DEV_JOBS=4
export SELKA_DEV_MAXRSS=8589934592
mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR" "$TMPDIR" "$SELKA_SLOT_DIR"
ENV
. "$HOME/.config/selka/dev-env.sh"
test "$(zig version)" = "$(cat .zigversion)"
scripts/build-slot.sh status
```

All agents using this account should source the same configuration and use the
same slot directory. Each worktree keeps its own `.zig-cache` and `.selka-cache`;
the Zig global cache can be shared on this host. Do not synchronize build caches,
locks, or native executables between machines. Native builds use host CPU features.

One build slot still lets that build use multiple cores. Increase the job count,
build slots, and memory budget only to fit the host's available resources. Zig's
`--maxrss` schedules declared step budgets; it is not an OS memory limit.
See [many agents](many-agents.md) for admission and memory settings.

## 5. Build and run a smoke test

From the selka checkout, with the environment above loaded:

```bash
# doc: not-selka
sh scripts/setup-git.sh
scripts/build-slot.sh build zig build \
  -j"$SELKA_DEV_JOBS" --maxrss "$SELKA_DEV_MAXRSS"

mkdir -p .tmp
cat > .tmp/remote-smoke.selka <<'SELKA'
func main(out: Stream) -> int:
    print(out, "Remote development is ready")
    return 0

public func test_addition() -> bool:
    return 1 + 2 == 3
SELKA
scripts/build-slot.sh build zig-out/bin/selka check .tmp/remote-smoke.selka
scripts/build-slot.sh build zig-out/bin/selka run .tmp/remote-smoke.selka
scripts/build-slot.sh build zig-out/bin/selka test .tmp/remote-smoke.selka
```

The run should print `Remote development is ready` and exit successfully. The
test command should pass one test. The first build also compiles and installs the
Selka components with the compiler it builds. Keep `zig-out/bin/`,
`zig-out/libexec/`, and `zig-out/tools/` together if relocating an installation.

Configure your Git author name and email in this clone before your first commit
if they are not already configured. Merge drivers are local Git configuration,
so register them after every new clone; worktrees of a clone share them.

## 6. Run the complete verification gate

```bash
python3 -B scripts/verify_cache.py --zig "$ZIG" -- \
  -j"$SELKA_DEV_JOBS" --maxrss "$SELKA_DEV_MAXRSS"
```

This covers the registered `test` and `fmt-check` inventory: compiler tests, guest tests, documentation, and developer scripts. It owns
build/gate admission itself: run it directly. Successful unchanged actions can
be reused on subsequent requests. `--force` before `--zig` requests fresh action
execution. The report is `.selka-cache/verification-v3/last-run.json`; success
requires the command to exit zero and the report to record `success: true`.

## Everyday development

After editing compiler source, rebuild before invoking `zig-out/bin/selka`.
Focused tests do not install a new compiler:

```bash
scripts/build-slot.sh build zig build -j"$SELKA_DEV_JOBS" --maxrss "$SELKA_DEV_MAXRSS"
scripts/build-slot.sh build zig build test-core -Dtest-filter='zero RC' \
  -j"$SELKA_DEV_JOBS" --maxrss "$SELKA_DEV_MAXRSS"
scripts/build-slot.sh build zig build test-units -Dtest-filter=reference \
  -j"$SELKA_DEV_JOBS" --maxrss "$SELKA_DEV_MAXRSS"
scripts/build-slot.sh build zig build test-tooling-units \
  -j"$SELKA_DEV_JOBS" --maxrss "$SELKA_DEV_MAXRSS"
```

Run a native checked-ownership fixture with:

```bash
scripts/build-slot.sh build zig-out/bin/selka run \
  test/core/zero_rc_json_lookup.selka
```

Use the complete gate before finishing a change. See [test layout](test-layout.md),
[development loop](development-loop.md), and [managed memory](../managed-memory.md)
for the relevant workflows.

For parallel agents, create sibling worktrees (a commit older than GH-3a then still
resolves `../guardian-zig`). In each agent's shell:

```bash
git worktree add ../selka-feature -b feature/example main
cd ../selka-feature
. "$HOME/.config/selka/dev-env.sh"
```

Use a distinct branch and directory per agent. Do not share a writable worktree.
When returning to the main checkout, source the environment there again.

For measurements, build programs under `build` and run prebuilt binaries under
`scripts/build-slot.sh timing`. The [parity harness](../../bench/parity/README.md)
and Juice runtime harness already own admission. Select an allowed CPU on the
remote host (`taskset -pc $$`); the old development machine's CPU numbers are not
portable. A quiet admission window excludes cooperating jobs on this host, not
other tenants of a shared VM. Compare before/after results on the same host.

## Update an existing workspace

Start with a clean main checkout, after committing or otherwise preserving work:

```bash
git switch main
git pull --ff-only origin development
. "$HOME/.config/selka/dev-env.sh"
```

If `.zigversion` or the Guardian pin in this guide changes, install the matching
toolchain/revision before building. Then repeat the build and complete gate.
Changes to the environment file in this guide need to be applied to the local
copy too. Keep feature changes on branches; push a feature branch and target
`development` when opening its pull request. The local `main` tracks
`origin/development`; an explicit `git push origin main:development` updates
that remote branch.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Clone or release download is denied | `gh auth status`; the account needs access to both repositories and the release assets. |
| Guardian commit or toolchain release cannot be found | Complete the publication steps below; neither a newer Guardian nor a newer Zig is an automatic substitute. |
| Zig version mismatch | Source the environment in the current worktree and check `zig version` against `.zigversion`. |
| Missing component manifest | Run ordinary `zig build`. A copied `selka` executable alone uses its built-in implementations and says so; a component folder without the manifest is an error. |
| Admission keeps waiting | `scripts/build-slot.sh status` shows live jobs, timing requests, and available memory. Check the host's resources before changing limits. |
| Temporary files fail or disk fills | `df -h "$TMPDIR"`; use persistent disk and inspect [cache retention](cache-retention.md). |
| Verification rejects a PATH directory | Remove nonexistent entries from that shell's PATH; the coordinator verifies its host tool search paths. |

## Publish the setup inputs

These are **maintainer commands on the existing development machine** for
publishing or updating the GitHub setup inputs. They publish
Selka source, the required Guardian revision, and a toolchain asset to GitHub.
The documentation change itself does not publish anything.

1. Commit this guide and the intended compiler changes on `main`. In the selka clone, configure
   `origin` if it has none, then push local `main` to `development` with its full ancestry:

   ```bash
   SELKA_GITHUB_REPO=eugenepentland/selka
   git remote add origin "git@github.com:${SELKA_GITHUB_REPO}.git"
   git push -u origin main:development
   ```

   If `origin` already exists, check `git remote -v` and skip `remote add`.
   Reconcile any existing destination history normally; do not force-push over it.

2. Publish the validated Guardian commit with a named reference, without moving
   Guardian's main branch:

   ```bash
   git -C ../guardian-zig push origin \
     ae1ae2899cc60b575e9e1b9212d73eddf9e2df72:refs/tags/mylang-dev-2026-10-11
   ```

3. Package the **complete working Zig directory** and its license, then publish
   the archive and checksum as assets. Set `SELKA_ZIG_SOURCE` to that directory;
   on the original host it is
   `/home/epentland/zig-toolchains/0.17.1`.
   Its final directory name must match `.zigversion`, as expected by extraction.

   ```bash
   (
   set -e
   read -r -p 'Path to the working pinned Zig directory: ' SELKA_ZIG_SOURCE
   SELKA_ZIG_SOURCE=$(realpath "$SELKA_ZIG_SOURCE")
   zig_version=$(cat .zigversion)
   test "$(basename "$SELKA_ZIG_SOURCE")" = "$zig_version"
   test "$("$SELKA_ZIG_SOURCE/zig" version)" = "$zig_version"
   zig_archive="zig-x86_64-linux-${zig_version}.tar.xz"
   zig_assets="$PWD/.tmp/toolchain-release"
   mkdir -p "$zig_assets"
   scripts/build-slot.sh build tar -C "$(dirname "$SELKA_ZIG_SOURCE")" \
     -cJf "$zig_assets/$zig_archive" "$zig_version"
   (cd "$zig_assets" && sha256sum "$zig_archive" > "$zig_archive.sha256")
   gh release create "zig-$zig_version" --repo "$SELKA_GITHUB_REPO" --target development \
     --title "Pinned Linux x86-64 Zig $zig_version" \
     --notes 'Complete development toolchain, including libraries and license. Verify the SHA-256 checksum before extracting.' \
     "$zig_assets/$zig_archive" "$zig_assets/$zig_archive.sha256"
   )
   ```

   Keep this release immutable. If it already exists, verify its assets instead
   of replacing them. A trusted source copy plus the published checksum provides
   the installation input; the unavailable upstream nightly URL is not needed.

Finally, follow sections 1–6 on a fresh host. The existing GitHub Actions workflow
no longer checks out Guardian (GH-2) and is not the authority for this setup until
updated and qualified separately.
