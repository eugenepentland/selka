#!/usr/bin/env python3
"""Build Selka programs for a CPU with no operating system and run them (lane MCU-A2; not wired into zig build).

    scripts/bare/bare_run.py --compiler PATH [--platform qemu|rp2040-ram] [--release] [--work DIR] FILE.selka...

For each FILE.selka: the compiler given by path builds it for Linux (stores under WORK/stores through
scripts/lane/with-stores.sh), and the Linux executable runs with SELKA_CORE_LEAKCHECK=1 for the expected status. The same
compiler links it for the Cortex-M0+ with the bare runtime and the platform's hooks (`build --target thumbv6m-none FILE -o
X.elf --link PLATFORM.c --linker-script SCRIPT.ld`, with `--release` when asked: whole-image optimisation), and the image
runs:

  qemu        qemu-system-arm -M mps2-an385, semihosting: QEMU's exit status is the program's
  qemu-memory QEMU again, with the device described by its memory (scripts/bare/qemu-memory/selka.json, MCU-NOC4A) instead of a
              linker script: the same programs, the same results
  rp2040-ram  a RAM image for the board loop of ~/ai/canopy/selka-rp (tools/board.py run IMAGE.bin; platform side in
              bringup/selka-ram/, its headers in bringup/ramlog/): the log the program leaves ends with "exit status N"

A program passes when its bare status is its Linux status, the first two lines of a trap's text are the same, and the
exit report says 0 live blocks. A `--release` image reports a trap tersely, `error[CODE] PATH:LINE` (PATH:LINE is the site
of Linux's `  in FUNCTION at PATH:LINE:COLUMN` line; no place for a trap Linux reports without a site): the code and the
place are compared. A file with the line `# bare: R_CODE` expects that trap on the bare CPU (status 1)
whatever Linux does (memory exhaustion: 264 KiB is less than Linux has); `# bare-text: error[R_CODE] FILE:LINE`
asks for a line that begins with the code and ends with the place (a path may lead it).

A device program (`main(reg: Registers)`, lane MCU-B1D) has no Linux build: Linux provides no registers. Its file says
what the device does instead: `# bare-status: N` is its expected status; `# bare-serial: TEXT` is the text it writes
through QEMU's UART0 (`\n` a newline), captured with `-serial file:` and compared exactly; `# bare-platform: NAME` runs
it only on that platform, and another platform skips it and says so; `# bare-link: FILE.c` (MCU-EXT) links the C file of
that name beside the program after the platform's, for a program whose `extern func` declarations call it. One line per program; a JSON line per program
goes to WORK/results.jsonl. Exit status 0 when every program passes or is skipped.
"""
import argparse, json, os, re, shutil, struct, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BOARD_DIR = os.path.expanduser("~/ai/canopy/selka-rp/bringup/selka-ram")
BOARD_PY = os.path.expanduser("~/ai/canopy/selka-rp/tools/board.py")


def zig():
    path = os.environ.get("ZIG")
    if not path:
        sys.exit("bare_run: $ZIG is not set (source ~/.config/selka/dev-env.sh)")
    return path


def run(cmd, env=None, timeout=600, **kw):
    return subprocess.run(cmd, env=env, timeout=timeout, capture_output=True, text=True, errors="replace", **kw)


def must(cmd, what, **kw):
    r = run(cmd, **kw)
    if r.returncode != 0:
        raise RuntimeError("%s failed (status %d): %s" % (what, r.returncode, (r.stderr or r.stdout).strip()[:2000]))
    return r


def zig_env(work):
    env = dict(os.environ)
    env["ZIG_LOCAL_CACHE_DIR"] = env["ZIG_GLOBAL_CACHE_DIR"] = os.path.join(work, "zig-cache")
    return env


def platform_files(work, platform, board_dir):
    """The platform's C file and linker script. The board's file includes headers of bringup/ramlog by quoted name, so it
    is copied beside them into WORK, where its compile finds them (`--link` takes no include path)."""
    if platform == "qemu":
        return os.path.join(HERE, "qemu", "platform.c"), os.path.join(HERE, "qemu", "link.ld")
    copy = os.path.join(work, "platform-" + platform)
    os.makedirs(copy, exist_ok=True)
    ramlog = os.path.join(os.path.dirname(board_dir), "ramlog")
    for source in (os.path.join(board_dir, "platform.c"), os.path.join(ramlog, "layout.h"), os.path.join(ramlog, "rp2040.h")):
        shutil.copyfile(source, os.path.join(copy, os.path.basename(source)))
    return os.path.join(copy, "platform.c"), os.path.join(board_dir, "link.ld")


def elf_sizes(path):
    """Code (vectors, text, read-only data), initialised data and zeroed data of a 32-bit ELF, from its sections."""
    data = open(path, "rb").read()
    shoff, = struct.unpack_from("<I", data, 0x20)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x2E)
    sections = [struct.unpack_from("<IIIIIIIIII", data, shoff + i * shentsize) for i in range(shnum)]
    names = sections[shstrndx][4]
    sizes = {"code": 0, "data": 0, "bss": 0}
    for s in sections:
        name = data[names + s[0]:data.index(b"\0", names + s[0])].decode()
        if not s[2] & 2:  # not SHF_ALLOC
            continue
        if s[1] == 8:  # SHT_NOBITS
            sizes["bss"] += s[5]
        elif s[2] & 1:  # SHF_WRITE
            sizes["data"] += s[5]
        elif name:
            sizes["code"] += s[5]
    return sizes


def program_links(src):
    """The program's own C files (`# bare-link: FILE.c`, beside the program; MCU-EXT), linked after the platform's."""
    names = re.findall(r"^# bare-link: (\S+)", open(src).read(), re.M)
    return [os.path.join(os.path.dirname(os.path.abspath(src)), name) for name in names]


def linux_side(args, src, out, device):
    """Build for Linux and run the executable (not for a device program, which Linux cannot build); link the image for the
    bare target. Returns (status, stderr lines, ELF path); the status is None for a device program."""
    exe = os.path.join(out, "linux.exe")
    elf = os.path.join(out, "program.elf")
    stores = [os.path.join(ROOT, "scripts", "lane", "with-stores.sh"), os.path.join(args.work, "stores"), args.compiler]
    if not device:
        must(stores + ["build", src, "-o", exe], "selka build")
    if os.path.exists(elf):
        os.remove(elf)
    if args.platform == "qemu-memory":
        # The device is described by its memory (`qemu-memory/selka.json`), not by a linker script: the program is built from a
        # project folder holding the description, QEMU's platform file and the program's own C files, with no other flag.
        project = os.path.join(out, "project")
        shutil.rmtree(project, ignore_errors=True)
        os.makedirs(project)
        for source in [os.path.join(HERE, "qemu", "platform.c"), os.path.join(HERE, "qemu-memory", "selka.json"), src] + program_links(src):
            shutil.copyfile(source, os.path.join(project, os.path.basename(source)))
        copies = [arg for c in program_links(src) for arg in ("--link", os.path.join(project, os.path.basename(c)))]
        must(stores + ["build", os.path.join(project, os.path.basename(src)), "-o", elf] + copies + (["--release"] if args.release else []),
             "selka build (a device described by its memory)")
    else:
        plat_c, script = platform_files(args.work, args.platform, args.board_dir)
        links = [arg for c in program_links(src) for arg in ("--link", c)]
        must(stores + ["build", "--target", "thumbv6m-none", src, "-o", elf, "--link", plat_c, "--linker-script", script]
             + links + (["--release"] if args.release else []), "selka build --target thumbv6m-none")
    if device:
        return None, [], elf
    env = dict(os.environ, SELKA_CORE_LEAKCHECK="1")
    r = run([exe], env=env, timeout=120)
    return r.returncode, r.stderr.splitlines(), elf


def bare_side(args, elf, out):
    """Run the image. Returns (status, output lines, sizes, seconds); on QEMU the text UART0 wrote is in sizes["serial"]."""
    sizes = elf_sizes(elf)
    started = time.monotonic()
    if args.platform in ("qemu", "qemu-memory"):
        serial = os.path.join(out, "serial.txt")
        if os.path.exists(serial):
            os.remove(serial)
        r = run(["qemu-system-arm", "-M", "mps2-an385", "-nographic", "-monitor", "none", "-serial", "file:" + serial,
                 "-semihosting-config", "enable=on,target=native", "-kernel", elf], timeout=120)
        seconds = time.monotonic() - started
        sizes["serial"] = open(serial, errors="replace").read() if os.path.exists(serial) else ""
        return r.returncode, r.stderr.splitlines() + r.stdout.splitlines(), sizes, seconds
    image = os.path.join(out, "program.bin")
    must([zig(), "objcopy", "-O", "binary", elf, image], "objcopy", env=zig_env(args.work))
    sizes["image"] = os.path.getsize(image)
    r = run([sys.executable, BOARD_PY, "run", image], timeout=120)
    seconds = time.monotonic() - started
    lines = (r.stdout + r.stderr).splitlines()
    found = [int(m.group(1)) for m in (re.search(r"exit status (\d+)", l) for l in lines) if m]
    total = [float(m.group(1)) for m in (re.search(r"total ([0-9.]+) s", l) for l in lines) if m]
    sizes["board_total"] = total[-1] if total else None
    if r.returncode != 0 or not found:
        return None, lines, sizes, seconds
    return found[-1], lines, sizes, seconds


def trap_lines(lines):
    return [l for l in lines if "error[" in l or l.startswith("  in ")][:2]


def terse_lines(lines):
    """What a `--release` image prints for the trap Linux printed as `lines`: `error[CODE] PATH:LINE`, the place from the
    site's `  in` line; a trap whose first line names no place (`error[CODE]: ...`, raised outside a site) has none."""
    first = next((l for l in lines if "error[" in l), None)
    if first is None:
        return []
    code = re.search(r"error\[([A-Z0-9_]+)\]", first).group(1)
    if first.startswith("error["):
        return ["error[%s]" % code]
    site = next((re.match(r"  in .* at (.+):(\d+):\d+$", l) for l in lines if l.startswith("  in ")), None)
    return ["error[%s] %s:%s" % (code, site.group(1), site.group(2))] if site else [first]


def check(args, src):
    name = os.path.splitext(os.path.basename(src))[0]
    out = os.path.join(args.work, args.platform + ("-release" if args.release else ""), name)
    os.makedirs(out, exist_ok=True)
    text = open(src).read()
    expect = re.search(r"^# bare: (R_[A-Z_]+)", text, re.M)
    expect_text = re.search(r"^# bare-text: (.*)$", text, re.M)
    device = re.search(r"^# bare-status: (\d+)", text, re.M)
    serial = re.search(r"^# bare-serial: (.*)$", text, re.M)
    only = re.search(r"^# bare-platform: (\S+)", text, re.M)
    if only and only.group(1) != args.platform.split("-")[0] and only.group(1) != args.platform:
        print("%-14s skip (runs only on %s)" % (name, only.group(1)), flush=True)
        return None
    linux_status, linux_err, elf = linux_side(args, src, out, device is not None)
    status, lines, sizes, seconds = bare_side(args, elf, out)
    written = sizes.pop("serial", None)
    report = next((l for l in lines if "myl-bare:" in l), "")
    get = lambda key: int(re.search(key + r" (\d+)", report).group(1)) if re.search(key + r" (\d+)", report) else None
    live, heap, stack = get("live blocks"), get("heap high-water"), get("stack")
    problems = []
    if expect_text and not any(l.startswith(expect_text.group(1).split(" ")[0]) and l.endswith(expect_text.group(1).split(" ")[-1]) for l in lines):
        problems.append("no line like %r" % expect_text.group(1))
    if serial and written != serial.group(1).replace("\\n", "\n"):
        problems.append("serial %r, expected %r" % (written, serial.group(1).replace("\\n", "\n")))
    if device:
        if status != int(device.group(1)):
            problems.append("status %s, expected %s" % (status, device.group(1)))
        if live not in (0, None):
            problems.append("%d live blocks at exit" % live)
    elif expect:
        if status != 1 or not any("error[%s]" % expect.group(1) in l for l in lines):
            problems.append("expected error[%s] and status 1" % expect.group(1))
    else:
        if status != linux_status:
            problems.append("status %s, Linux %s" % (status, linux_status))
        expected = terse_lines(linux_err) if args.release else trap_lines(linux_err)
        got = [l for l in lines if "error[" in l][:1] if args.release else trap_lines(lines)
        # A program built from a project folder (`qemu-memory`) names its copy in a trap: the harness compares the original's path.
        got = [l.replace(os.path.join(out, "project") + "/", os.path.dirname(src) + "/") for l in got]
        if expected != got:
            problems.append("trap text differs: Linux %r, bare %r" % (expected, got))
        leaked_linux = any("blocks live at exit" in l for l in linux_err)
        if live not in (0, None) and not leaked_linux:
            problems.append("%d live blocks at exit (Linux 0)" % live)
        if live is None and linux_status == 0 and not trap_lines(lines):
            problems.append("no exit report")
    result = dict(program=name, platform=args.platform, release=args.release, linux=linux_status, bare=status, live=live, heap=heap,
                  stack=stack, seconds=round(seconds, 2), problems=problems, serial=written, **sizes)
    with open(os.path.join(args.work, "results.jsonl"), "a") as f:
        f.write(json.dumps(result) + "\n")
    with open(os.path.join(out, "bare-output.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("%-14s %-4s linux %-3s bare %-4s live %-4s code %6d data %4d bss %6d heap %6s stack %5s %6.2f s%s" % (
        name, "ok" if not problems else "FAIL", linux_status, status, live, sizes["code"], sizes["data"], sizes["bss"],
        heap, stack, seconds, "" if not problems else "  " + "; ".join(problems)), flush=True)
    return not problems


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--compiler", required=True, help="the selka compiler that builds for Linux and links the image")
    ap.add_argument("--platform", choices=["qemu", "qemu-memory", "rp2040-ram"], default="qemu")
    ap.add_argument("--release", action="store_true", help="link the image with `--release` (whole-image optimisation)")
    ap.add_argument("--work", default=os.path.expanduser("~/ai/.home-cache/aw/mcu-a2/work"))
    ap.add_argument("--board-dir", default=BOARD_DIR)
    args = ap.parse_args()
    args.work = os.path.abspath(args.work)
    os.makedirs(args.work, exist_ok=True)
    args.compiler = os.path.abspath(args.compiler)
    passed = skipped = 0
    for src in args.files:
        try:
            verdict = check(args, os.path.abspath(src))
            skipped += verdict is None
            passed += bool(verdict)
        except (RuntimeError, subprocess.TimeoutExpired) as e:
            print("%-14s FAIL %s" % (os.path.splitext(os.path.basename(src))[0], str(e).splitlines()[0][:300]), flush=True)
    print("bare_run: %d of %d passed on %s%s%s" % (passed, len(args.files) - skipped, args.platform, " --release" if args.release else "",
                                                 ", %d skipped (another platform's)" % skipped if skipped else ""))
    return 0 if passed + skipped == len(args.files) else 1


if __name__ == "__main__":
    sys.exit(main())
