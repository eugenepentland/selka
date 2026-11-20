#!/usr/bin/env python3
"""kitproj.py: the project half of the lane kit (docs/tooling/lane-kit.md).

  kitproj.py clone KIT                         clone the projects into KIT/proj and write KIT/PROJECTS.txt
  kitproj.py prepare KIT COMPILER STORES       `selka fix` of each project's prepare units, with COMPILER only
  kitproj.py sweep KIT COMPILER OUT STORES     `check` of each check unit and `fix --check` of each prepare unit, three at a time;
                                               OUT/<unit>.{out,diag,rc}, OUT/<unit>.fixcheck.out, OUT/SUMMARY.txt, OUT/fixcheck.txt
  kitproj.py compare BASE_OUT NEW_OUT [FILE]   per-project comparison (file, line, code); exit 1 when something is newly refused

Never more than three compiler processes at a time. The stores (STORES) are set on each command only. Nothing is committed in a
project, and the source projects are only read.
"""
import concurrent.futures as cf
import os
import re
import subprocess
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

HOME = Path.home()
SOURCES = Path(os.environ.get("KIT_SOURCES", HOME / "ai/canopy"))
# name -> (kind, source folder). `git` clones, `archive` copies the tracked source of HEAD (the folder is read only).
PROJECTS = {
    "netlisp-selka-redo": ("git", "netlisp-selka-redo"),
    "selka-protobuf": ("git", "selka-protobuf"),
    "selka-sqlite": ("git", "selka-sqlite"),
    "artifacts-site": ("archive", "artifacts-site"),
}
DIAG = re.compile(r"^(?:(?P<file>\S+?):(?P<line>\d+):(?P<col>\d+): )?(?P<sev>error|warning)\[(?P<code>[A-Za-z0-9_]+)\]")
WOULD = re.compile(r"^would fix (?P<file>\S+): (?P<n>\d+) edits? \((?P<codes>[^)]*)\)")
SKIP_DIRS = {".git", ".selka-cache", ".zig-cache", "zig-out", "node_modules"}


def units_for(name, root):
    """The prepare and check units of a project: lists of (cwd relative to the project, arguments)."""
    if name == "netlisp-selka-redo":
        return [(".", ["src"])], [(".", ["src"])]
    if name == "artifacts-site":
        roots = [(".", [d]) for d in ("src", "viewgen", "tools", "tests")]
        return roots, roots + [("friction/f6_layout", ["."])]
    dirs = sorted({str(p.parent.relative_to(root)) for p in root.rglob("*.selka")
                   if not (set(p.relative_to(root).parts) & SKIP_DIRS)})
    return [(".", ["."])], [(d, ["."]) for d in dirs]


def unit_name(project, cwd, args):
    """A file-name-safe name of a unit."""
    where = args[0] if cwd == "." else cwd
    return project + "~" + ("_root" if where == "." else where.replace("/", "_"))


def read_projects(kit):
    """Read KIT/PROJECTS.txt: {project: {"commit", "prepare": [...], "check": [...]}}."""
    out = {}
    for line in (Path(kit) / "PROJECTS.txt").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if f[0] == "project":
            out[f[1]] = {"commit": f[2], "prepare": [], "check": []}
        else:
            # the verb and the flags are not part of a unit: `check src --warnings --no-cache` is the target ["src"]
            out[f[1]][f[0]].append((f[2], [w for w in f[3].split(" ")[1:] if not w.startswith("--")]))
    return out


def clone(kit):
    """Clone or copy every project into KIT/proj (a no-op for one that is there) and write PROJECTS.txt."""
    kit = Path(kit)
    (kit / "proj").mkdir(exist_ok=True)
    lines = ["# lane kit: projects, their prepare units (selka fix) and check units (selka check). TAB separated.",
             "# project NAME COMMIT SOURCE | prepare NAME DIR ARGS | check NAME DIR ARGS   (DIR is relative to the project; run in it)"]
    for name, (kind, src) in PROJECTS.items():
        dst = kit / "proj" / name
        source = SOURCES / src
        if not dst.exists():
            if kind == "git":
                subprocess.run(["git", "clone", "-q", str(source), str(dst)], check=True)
            else:
                dst.mkdir(parents=True)
                git = subprocess.Popen(["git", "-C", str(source), "archive", "HEAD"], stdout=subprocess.PIPE)
                subprocess.run(["tar", "-x", "-C", str(dst)], stdin=git.stdout, check=True)
                if git.wait() != 0:
                    raise SystemExit("git archive failed for " + name)
        commit = subprocess.run(["git", "-C", str(source), "rev-parse", "--short=10", "HEAD"], capture_output=True, text=True).stdout.strip()
        prepare, check = units_for(name, dst)
        lines.append(f"project\t{name}\t{commit}\t{source}" + (" (tracked source of HEAD)" if kind == "archive" else ""))
        lines += [f"prepare\t{name}\t{c}\tfix {' '.join(a)}" for c, a in prepare]
        lines += [f"check\t{name}\t{c}\tcheck {' '.join(a)} --warnings --no-cache" for c, a in check]
    (kit / "PROJECTS.txt").write_text("\n".join(lines) + "\n")
    print(f"clone: {len(PROJECTS)} projects, {sum(1 for l in lines if l.startswith('check'))} check units -> {kit}/PROJECTS.txt")


def wait_for_memory(gib=4, patience=900):
    """Wait (up to patience seconds) until gib GiB of memory are available, so a lane's sweep never starves a gate."""
    for _ in range(patience // 5):
        avail = next(int(l.split()[1]) for l in open("/proc/meminfo") if l.startswith("MemAvailable"))
        if avail >= gib * 1048576:
            return
        time.sleep(5)


def run_unit(compiler, stores, cwd, argv, jobs, outfile, timeout=1800):
    """Run one compiler command in cwd with the lane's stores; return (status, seconds). Output goes to outfile."""
    if not Path(cwd).is_dir():
        raise SystemExit(f"kitproj: no such directory {cwd}")
    wait_for_memory()
    env = dict(os.environ, SELKA_JOBS=str(jobs))
    for stale in ("SELKA_COMPONENT_DIR",):
        env.pop(stale, None)
    libexec = Path(compiler).resolve().parent.parent / "libexec/selka/components"
    if libexec.is_dir():
        env["SELKA_COMPONENT_DIR"] = str(libexec)
    cmd = [str(Path(__file__).with_name("with-stores.sh")), stores, str(compiler)] + argv
    t0 = time.time()
    with open(outfile, "w") as fh:
        try:
            rc = subprocess.run(cmd, cwd=cwd, env=env, stdout=fh, stderr=subprocess.STDOUT, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            rc = 124
    return rc, time.time() - t0


def prepare(kit, compiler, stores):
    """`selka fix` of each prepare unit with the base compiler, one project at a time, three jobs each."""
    kit = Path(kit)
    log = kit / "logs"
    log.mkdir(exist_ok=True)
    failed = False
    for name, p in read_projects(kit).items():
        t0 = time.time()
        edits, rcs = 0, []
        for cwd, args in p["prepare"]:
            out = log / f"prepare-{unit_name(name, cwd, args)}.log"
            rc, _ = run_unit(compiler, stores, kit / "proj" / name / cwd,
                             ["fix", "--cache-dir=" + str(kit / "cache" / name)] + args, 3, out)
            rcs.append(rc)
            m = re.search(r"^fix: (\d+) edits? in (\d+) files? over (\d+) rounds?", out.read_text(errors="replace"), re.M)
            edits += int(m.group(1)) if m else 0
        print(f"prepare {name}: {edits} edits, status {','.join(map(str, rcs))}, {time.time() - t0:.0f}s", flush=True)
        failed = failed or any(rc not in (0, 1) for rc in rcs)
    return 3 if failed else 0


def parse_diags(text, rc):
    """The (severity, file, line, code) tuples of a check's output; a status other than 0 or 1 is a crash entry."""
    found = set()
    for line in text.splitlines():
        m = DIAG.match(line)
        if m:
            found.add((m["sev"], m["file"] or "", int(m["line"] or 0), m["code"]))
    if rc not in (0, 1):
        found.add(("error", "", 0, f"STATUS_{rc}"))
    return found


def sweep(kit, compiler, out, stores):
    """Every `check` unit and every `fix --check` unit (writes nothing in the projects), in one pool of three processes, the
    heavy ones first. Writes OUT/<unit>.{out,diag,rc}, OUT/<unit>.fixcheck.out, OUT/SUMMARY.txt and OUT/fixcheck.txt."""
    kit, out = Path(kit), Path(out)
    out.mkdir(parents=True, exist_ok=True)
    jobs = []
    for name, p in read_projects(kit).items():
        heavy = 3 if name == "netlisp-selka-redo" else 1
        jobs += [(heavy, "check", name, cwd, args) for cwd, args in p["check"]]
        jobs += [(heavy, "fix", name, cwd, args) for cwd, args in p["prepare"]]
    jobs.sort(key=lambda j: -j[0])

    def one(job):
        _, kind, name, cwd, args = job
        u = unit_name(name, cwd, args)
        where = kit / "proj" / name / cwd
        if kind == "check":
            rc, secs = run_unit(compiler, stores, where, ["check"] + args + ["--warnings", "--no-cache"], 1, out / (u + ".out"))
            diags = parse_diags((out / (u + ".out")).read_text(errors="replace"), rc)
            (out / (u + ".diag")).write_text("".join(f"{s} {f}:{l} {c}\n" for s, f, l, c in sorted(diags)))
            (out / (u + ".rc")).write_text(f"{rc}\n")
            return kind, u, name, rc, secs, diags
        f = out / (u + ".fixcheck.out")
        rc, secs = run_unit(compiler, stores, where, ["fix", "--check", "--no-cache"] + args, 1, f)
        found = [f"{name}\t{u}\t{m['codes'].replace(', ', '+')}\t{m['file']}\t{m['n']}"
                 for m in map(WOULD.match, f.read_text(errors="replace").splitlines()) if m]
        if rc not in (0, 1):
            found.append(f"{name}\t{u}\tSTATUS_{rc}\t-\t1")
        return kind, u, name, rc, secs, found

    rows, fixes, bad = {}, [], []
    with cf.ThreadPoolExecutor(max_workers=3) as pool:
        for kind, u, name, rc, secs, found in pool.map(one, jobs):
            if rc not in (0, 1):
                bad.append(f"{kind} {u} status {rc}")
            if kind == "check":
                e = sum(1 for d in found if d[0] == "error")
                rows[u] = (name, rc, e, len(found) - e, secs)
            else:
                fixes += found
    if bad:
        print("kitproj: the compiler ended with a status other than 0 or 1 on: " + "; ".join(sorted(bad)[:5]), file=sys.stderr)
    lines = [f"{u}\trc={rc}\terrors={e}\twarnings={w}\t{s:.0f}s" for u, (n, rc, e, w, s) in sorted(rows.items())]
    (out / "SUMMARY.txt").write_text("\n".join(lines) + "\n")
    (out / "fixcheck.txt").write_text("\n".join(sorted(fixes)) + ("\n" if fixes else ""))
    return 3 if bad else 0


def read_fixcheck(path):
    """fixcheck.txt as a list of (project, unit, codes, file, n)."""
    p = Path(path)
    if not p.exists():
        return []
    return [tuple(l.split("\t")) for l in p.read_text().splitlines() if l]


def read_diag(path):
    """A .diag file as a set of (severity, file, line, code)."""
    out = set()
    if Path(path).exists():
        for l in Path(path).read_text().splitlines():
            sev, loc, code = l.split(" ")
            f, _, n = loc.rpartition(":")
            out.add((sev, f, int(n), code))
    return out


def compare(base, new, full=None):
    """Compare two check results; print the summary lines; return the number of newly refused places."""
    base, new = Path(base), Path(new)
    units = defaultdict(list)
    for d in sorted(new.glob("*.diag")):
        units[d.name.split("~")[0]].append(d.stem)
    report, newly_all, total_new = [], [], 0
    bfix, nfix = read_fixcheck(base / "fixcheck.txt"), read_fixcheck(new / "fixcheck.txt")
    base_fix_keys = {(a[1], a[2], a[3]) for a in bfix}
    for project, names in units.items():
        newly, gone, wplus, wminus = [], [], 0, 0
        for u in names:
            b, n = read_diag(base / (u + ".diag")), read_diag(new / (u + ".diag"))
            be, ne = {d for d in b if d[0] == "error"}, {d for d in n if d[0] == "error"}
            bw, nw = b - be, n - ne
            newly += [(u,) + d for d in sorted(ne - be)]
            gone += [(u,) + d for d in sorted(be - ne)]
            wplus += len(nw - bw)
            wminus += len(bw - nw)
        codes = Counter()
        fix_new = []
        for a in nfix:
            if a[0] != project or (a[1], a[2], a[3]) in base_fix_keys:
                continue
            codes[a[2]] += int(a[4])
            if any(c.startswith("E_") or c.startswith("STATUS_") for c in a[2].split("+")):
                fix_new.append(("fix --check",) + a[3:] + (a[2],))
        fixtext = ", ".join(f"{c} {k}" for c, k in sorted(codes.items())) if codes else "none"
        report.append(f"{project}: newly refused {len(newly) + len(fix_new)}, no longer refused {len(gone)}, "
                      f"warnings +{wplus} -{wminus}, fix --check edits by code: {fixtext}")
        newly_all += [f"NEW {project} {u.split('~')[1]} {f}:{l} {c}" for u, s, f, l, c in newly]
        newly_all += [f"NEW {project} fix --check would edit {a[1]} ({a[2]} edits, {a[3]})" for a in fix_new]
        total_new += len(newly) + len(fix_new)
    lines = report + (newly_all[:10] if newly_all else [])
    if len(newly_all) > 10:
        lines.append(f"... and {len(newly_all) - 10} more newly refused places")
    if full:
        Path(full).write_text("\n".join(report + newly_all) + "\n")
    print("\n".join(lines))
    return total_new


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0 if len(argv) > 1 else 2
    cmd, a = argv[1], argv[2:]
    if cmd == "clone":
        clone(a[0])
    elif cmd == "prepare":
        return prepare(*a)
    elif cmd == "sweep":
        return sweep(*a)
    elif cmd == "compare":
        return 1 if compare(*a) else 0
    else:
        print("unknown command " + cmd, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
