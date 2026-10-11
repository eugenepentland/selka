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
scheduling budget. First-time compiler seed provisioning takes several minutes.

## Before the first GitHub-only setup

The maintainer must first complete [Publish the setup inputs](#publish-the-setup-inputs).
At the time this guide was written:

- The repository is [eugenepentland/selka](https://github.com/eugenepentland/selka).
  Its GitHub `main` did not yet contain the locally merged `441a96465` changes,
  and the local clone had no Git remote configured.
- The Guardian revision used by the passing integrated gate,
  `ae1ae2899cc60b575e9e1b9212d73eddf9e2df72`, was not available on GitHub.
- The upstream download URL for Zig `0.17.0-dev.1683+5ceec001b` returned 404.
  The working distribution therefore needs to be preserved as a release asset.

The steps below use that exact Guardian revision and a GitHub release containing
the complete pinned Zig distribution. They do not assume that the latest
Guardian or a newer Zig version is compatible. Update this guide's pins and the
release assets together after validating a toolchain upgrade.

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

For a long-running SSH session, start `tmux new -s mylang-dev`; reconnect with
`tmux attach -t mylang-dev` if the connection drops.

## 2. Clone the source and Guardian

Clone Selka into a local directory named `mylang` for the remaining examples.
Both repositories
must be siblings because `build.zig.zon` uses `../guardian-zig`.

```bash
MYLANG_GITHUB_REPO=eugenepentland/selka
mkdir -p "$HOME/src"
cd "$HOME/src"
gh repo clone "$MYLANG_GITHUB_REPO" mylang -- --branch main
gh repo clone eugenepentland/guardian-zig guardian-zig
git -C guardian-zig fetch origin ae1ae2899cc60b575e9e1b9212d73eddf9e2df72
git -C guardian-zig checkout --detach ae1ae2899cc60b575e9e1b9212d73eddf9e2df72
cd mylang
```

Use a full clone, not `--depth 1` or GitHub's source ZIP. Component provisioning
archives a pinned historical compiler commit from Git. Check that it exists:

```bash
seed_commit=$(python3 -c 'import json; print(json.load(open("selfhost/component-seed.json"))["commit"])')
git cat-file -e "${seed_commit}^{commit}"
```

If an existing clone is shallow, run `git fetch --unshallow origin`. Source
archives can instead supply a verified seed tarball as described in
[component builds](selfhost-components.md#build-and-install).

## 3. Install the pinned Zig distribution

From the mylang checkout, download the assets published in the maintainer step.
Keep `zig` and its complete `lib/` directory together. The archive checksum is
checked before extraction, and the executable's version is checked afterward.

```bash
zig_version=$(cat .zigversion)
zig_archive="zig-x86_64-linux-${zig_version}.tar.xz"
zig_download="$HOME/Downloads/mylang-toolchain/$zig_version"
mkdir -p "$zig_download" "$HOME/.local/share/mylang/zig"
gh release download "zig-$zig_version" --repo "$MYLANG_GITHUB_REPO" \
  --pattern "$zig_archive" --pattern "$zig_archive.sha256" --dir "$zig_download"
(cd "$zig_download" && sha256sum --check "$zig_archive.sha256") &&
  tar -xJf "$zig_download/$zig_archive" -C "$HOME/.local/share/mylang/zig"
test "$("$HOME/.local/share/mylang/zig/$zig_version/zig" version)" = "$zig_version"
```

An already downloaded asset makes `gh release download` refuse to overwrite it.
For a repeat installation, reuse it after checking its checksum. Do not replace
the pinned snapshot with the distribution's `apt install zig`, a stable release,
or `master`: the build checks the exact version. The compiler also recognizes
the approved distribution's contents when deciding whether objects can be reused.

## 4. Configure each shell and worktree

Create this user-local environment file once. Source it **from inside the
checkout you are about to work on**, including after switching worktrees.
It derives paths from that checkout; it contains no original-machine paths.

```bash
mkdir -p "$HOME/.config/mylang"
cat > "$HOME/.config/mylang/dev-env.sh" <<'ENV'
mylang_dev_root=$(git rev-parse --show-toplevel) || return 1
mylang_dev_zig_version=$(cat "$mylang_dev_root/.zigversion") || return 1
export ZIG="$HOME/.local/share/mylang/zig/$mylang_dev_zig_version/zig"
test -x "$ZIG" || { echo "Missing pinned Zig: $ZIG" >&2; return 1; }
export MYLANG_ZIG="$ZIG"
export PATH="$(dirname "$ZIG"):$PATH"
export ZIG_GLOBAL_CACHE_DIR="$HOME/.cache/mylang/zig-global"
export ZIG_LOCAL_CACHE_DIR="$mylang_dev_root/.zig-cache"
export TMPDIR="$mylang_dev_root/.tmp/work"
export MYLANG_SLOT_DIR="$HOME/.cache/mylang/slots"
export MYLANG_BUILD_SLOTS=1
export MYLANG_GATE_SLOTS=1
export MYLANG_DEV_JOBS=4
export MYLANG_DEV_MAXRSS=8589934592
mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR" "$TMPDIR" "$MYLANG_SLOT_DIR"
ENV
. "$HOME/.config/mylang/dev-env.sh"
test "$(zig version)" = "$(cat .zigversion)"
scripts/build-slot.sh status
```

All agents using this account should source the same configuration and use the
same slot directory. Each worktree keeps its own `.zig-cache` and `.mylang-cache`;
the Zig global cache can be shared on this host. Do not synchronize build caches,
locks, or native executables between machines. Native builds use host CPU features.

One build slot still lets that build use multiple cores. Increase the job count,
build slots, and memory budget only to fit the host's available resources. Zig's
`--maxrss` schedules declared step budgets; it is not an OS memory limit.
See [many agents](many-agents.md) for admission and memory settings.

## 5. Build, install hooks, and run a smoke test

From the mylang checkout, with the environment above loaded:

```bash
# doc: not-mylang
sh scripts/setup-git.sh
scripts/build-slot.sh build zig build \
  -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
scripts/build-slot.sh build zig build guardian -- install-hook .

mkdir -p .tmp
cat > .tmp/remote-smoke.my <<'MYLANG'
func main(out: Stream) -> int:
    out.print("Remote development is ready")
    return 0

public func test_addition() -> bool:
    return 1 + 2 == 3
MYLANG
scripts/build-slot.sh build zig-out/bin/mylang check .tmp/remote-smoke.my
scripts/build-slot.sh build zig-out/bin/mylang run .tmp/remote-smoke.my
scripts/build-slot.sh build zig-out/bin/mylang test .tmp/remote-smoke.my
```

The run should print `Remote development is ready` and exit successfully. The
test command should pass one test. The first build also provisions the separate
compiler seed and installs the Selka components. Keep `zig-out/bin/`,
`zig-out/libexec/`, and `zig-out/tools/` together if relocating an installation.

Configure your Git author name and email in this clone before your first commit
if they are not already configured. The hook runs the blocking Guardian gate.
Hooks and merge drivers are local Git configuration, so install them after every
new clone; worktrees of a clone share them.

## 6. Run the complete verification gate

```bash
python3 -B scripts/verify_cache.py --zig "$ZIG" -- \
  -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
```

This covers the registered `test` and `fmt-check` inventory, including Guardian,
compiler tests, guest tests, documentation, and developer scripts. It owns
build/gate admission itself: run it directly. Successful unchanged actions can
be reused on subsequent requests. `--force` before `--zig` requests fresh action
execution. The report is `.mylang-cache/verification-v1/last-run.json`; success
requires the command to exit zero and the report to record `success: true`.

## Everyday development

After editing compiler source, rebuild before invoking `zig-out/bin/mylang`.
Focused tests do not install a new compiler:

```bash
scripts/build-slot.sh build zig build -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
scripts/build-slot.sh build zig build test-core -Dtest-filter='zero RC' \
  -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
scripts/build-slot.sh build zig build test-units -Dtest-filter=reference \
  -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
scripts/build-slot.sh build zig build test-tooling-units \
  -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
```

The current memory-management prototype and its tests are available with:

```bash
scripts/build-slot.sh build zig-out/bin/mylang run \
  test/core/zero_rc_json_lookup.my --experimental-zero-rc
```

Use the complete gate before finishing a change. See [test layout](test-layout.md),
[development loop](development-loop.md), and [managed memory](../managed-memory.md)
for the relevant workflows.

For parallel agents, create sibling worktrees, so all still resolve
`../guardian-zig`. In each agent's shell:

```bash
git worktree add ../mylang-feature -b feature/example main
cd ../mylang-feature
. "$HOME/.config/mylang/dev-env.sh"
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
git pull --ff-only origin main
. "$HOME/.config/mylang/dev-env.sh"
```

If `.zigversion` or the Guardian pin in this guide changes, install the matching
toolchain/revision before building. Then repeat the build and complete gate.
Changes to the environment file in this guide need to be applied to the local
copy too. Keep feature changes on branches; publish them with ordinary Git push
and merge workflows.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Clone or release download is denied | `gh auth status`; the account needs access to both repositories and the release assets. |
| Guardian commit or toolchain release cannot be found | Complete the publication steps below; neither a newer Guardian nor a newer Zig is an automatic substitute. |
| Seed archive / unknown Git revision error | Use full history and verify the commit from `selfhost/component-seed.json` exists. |
| Zig version mismatch | Source the environment in the current worktree and check `zig version` against `.zigversion`. |
| Missing component manifest | Run ordinary `zig build`; a copied `mylang` executable alone is an incomplete installation. |
| Admission keeps waiting | `scripts/build-slot.sh status` shows live jobs, timing requests, and available memory. Check the host's resources before changing limits. |
| Temporary files fail or disk fills | `df -h "$TMPDIR"`; use persistent disk and inspect [cache retention](cache-retention.md). |
| Verification rejects a PATH directory | Remove nonexistent entries from that shell's PATH; the coordinator verifies its host tool search paths. |

## Publish the setup inputs

These are **one-time maintainer commands on the existing development machine**,
before another machine can follow the GitHub-only instructions. They publish
Selka source, the required Guardian revision, and a toolchain asset to GitHub.
The documentation change itself does not publish anything.

1. Commit this guide and the intended compiler changes on `main`. In the mylang clone, configure
   `origin` if it has none, then push `main` with its full ancestry:

   ```bash
   MYLANG_GITHUB_REPO=eugenepentland/selka
   git remote add origin "git@github.com:${MYLANG_GITHUB_REPO}.git"
   git push -u origin main
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
   the archive and checksum as assets. Set `MYLANG_ZIG_SOURCE` to that directory;
   on the original host it is
   `/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b`.
   Its final directory name must match `.zigversion`, as expected by extraction.

   ```bash
   (
   set -e
   read -r -p 'Path to the working pinned Zig directory: ' MYLANG_ZIG_SOURCE
   MYLANG_ZIG_SOURCE=$(realpath "$MYLANG_ZIG_SOURCE")
   zig_version=$(cat .zigversion)
   test "$(basename "$MYLANG_ZIG_SOURCE")" = "$zig_version"
   test "$("$MYLANG_ZIG_SOURCE/zig" version)" = "$zig_version"
   zig_archive="zig-x86_64-linux-${zig_version}.tar.xz"
   zig_assets="$PWD/.tmp/toolchain-release"
   mkdir -p "$zig_assets"
   scripts/build-slot.sh build tar -C "$(dirname "$MYLANG_ZIG_SOURCE")" \
     -cJf "$zig_assets/$zig_archive" "$zig_version"
   (cd "$zig_assets" && sha256sum "$zig_archive" > "$zig_archive.sha256")
   gh release create "zig-$zig_version" --repo "$MYLANG_GITHUB_REPO" --target main \
     --title "Pinned Linux x86-64 Zig $zig_version" \
     --notes 'Complete development toolchain, including libraries and license. Verify the SHA-256 checksum before extracting.' \
     "$zig_assets/$zig_archive" "$zig_assets/$zig_archive.sha256"
   )
   ```

   Keep this release immutable. If it already exists, verify its assets instead
   of replacing them. A trusted source copy plus the published checksum provides
   the installation input; the unavailable upstream nightly URL is not needed.

Finally, follow sections 1–6 on a fresh host. The existing GitHub Actions workflow
still has an older Guardian pin and a retired QBE benchmark command; it is not
the authority for this setup until updated and qualified separately.
