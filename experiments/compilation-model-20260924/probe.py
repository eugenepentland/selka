#!/usr/bin/env python3
"""Per-stage, per-process measurements of the mylang build loop on one generated tier.

usage: probe.py TIER_DIR --mylang BIN [--mode default|Debug] [--samples 3] [--work DIR]
                [--steps cold,noop,edit,iface,check,split,trace] [--tag NAME]

TIER_DIR is a gen_scale.py output (its `mylang/` subtree is copied into a fresh work
directory). Every command runs under `taskset -c 0-11` and /usr/bin/time (timed.py).

Steps
  cold     integrated cold `build` (wall, peak RSS of the largest process, phases)
  noop     two no-op builds (the first after cold is not a receipt hit)
  edit     body edit in the middle module, then `build` (samples times)
  iface    append a public function to the middle module, then `build`
  check    body edit, then `check`
  split    body edit and interface edit, each measured as two processes: the frontend
           child alone (`emit-project-qbe`, with its phase timings and peak RSS) and the
           driver alone (`build --manifest-file`), so each process's time and memory is
           visible
  trace    one body edit under `strace -f`, reporting every tool process's span

Output: JSON lines on stdout, one per measurement, and a summary at the end.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
TIMED = HERE / "timed.py"


def timed(cmd, cwd, label, out=None, err=None):
    args = [sys.executable, str(TIMED), "--cwd", str(cwd), "--label", label]
    if out:
        args += ["--out", str(out)]
    if err:
        args += ["--err", str(err)]
    p = subprocess.run(args + ["--"] + cmd, capture_output=True, text=True)
    line = p.stdout.strip().splitlines()[-1]
    return json.loads(line)


def phases(path):
    """phase-timings-v1 and work/qbe-build records from a stdout/stderr capture."""
    res = {"phases": {}, "report": None, "work": None}
    if not path or not Path(path).exists():
        return res
    for line in Path(path).read_text(errors="replace").splitlines():
        if not line.startswith("{"):
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        v = d.get("version")
        if v == "phase-timings-v1":
            res["phases"][d["name"]] = res["phases"].get(d["name"], 0) + d["duration_ns"] / 1e9
            if d.get("counts"):
                res["counts"] = d["counts"]
        elif v == "qbe-build-v1":
            d.pop("functions", None)
            res["report"] = d
        elif v == "work-report-v1":
            res["work"] = {k: d[k] for k in d if isinstance(d[k], dict)}
    return res


def body_edit(path, token):
    s = path.read_text()
    s2, n = re.subn(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{token}{m.group(3)}", s, count=1)
    assert n == 1, path
    path.write_text(s2)


def iface_edit(path, token):
    with path.open("a") as f:
        f.write(f"\n\npublic def extra_{token}(n: int) -> int:\n    return n + {token}\n")


class Probe:
    def __init__(self, a):
        self.a = a
        self.tier = Path(a.tier).resolve()
        self.work = Path(a.work or (self.tier.parent / f"work-{self.tier.name}-{a.tag}")).resolve()
        self.src = self.work / "src"
        self.cache = self.work / "cache"
        self.out = self.work / "bin" / "big"
        self.logs = self.work / "logs"
        self.M = len(list((self.tier / "mylang").glob("m*.my")))
        self.mid = self.src / f"m{self.M // 2:03d}.my"
        self.token = 7000
        self.results = []

    def fresh(self):
        shutil.rmtree(self.work, ignore_errors=True)
        shutil.copytree(self.tier / "mylang", self.src)
        for d in (self.cache, self.out.parent, self.logs):
            d.mkdir(parents=True, exist_ok=True)

    def mode(self):
        return ["--mode", "Debug"] if self.a.mode == "Debug" else []

    def build_cmd(self, extra=()):
        return [self.a.mylang, "build", "main.my", "--project", "-o", str(self.out), f"--cache-dir={self.cache}",
                "--timings=json", "--report"] + self.mode() + list(extra)

    def frontend_cmd(self):
        cmd = [self.a.mylang, "emit-project-qbe", str(self.src / "main.my"), "--lean-manifest=executable",
               f"--cache-dir={self.cache}", "--timings=json", "--report"]
        if self.a.mode != "Debug":
            cmd += ["--drop-debug", "--drop-step-checks", "--drop-frame-checks"]
        return cmd

    def record(self, label, rec, log=None):
        rec["label"] = label
        if log:
            ph = phases(log)
            rec["phases"] = {k: round(v, 4) for k, v in ph["phases"].items()}
            if ph["report"]:
                r = ph["report"]
                rec["counters"] = {k: r.get(k) for k in ("compiled_functions", "reused_functions", "function_objects",
                                                         "compiled_function_objects", "metadata_reused", "link_route", "output_changed")}
            if ph["work"]:
                rec["work"] = ph["work"]
        self.results.append(rec)
        print(json.dumps(rec), flush=True)

    def build(self, label):
        n = len(self.results)
        log = self.logs / f"{label}-{n}.log"
        rec = timed(self.build_cmd(), self.src, label, out=log, err=str(log) + ".err")
        self.record(label, rec, log)
        ph = phases(str(log) + ".err")
        if ph["phases"]:
            rec.setdefault("phases", {}).update({k: round(v, 4) for k, v in ph["phases"].items()})
            print(json.dumps({"label": label + ":phases", "phases": rec["phases"]}), flush=True)
        return rec

    def split(self, label):
        n = len(self.results)
        man = self.logs / f"{label}-{n}.manifest"
        felog = self.logs / f"{label}-{n}.fe.log"
        rec = timed(self.frontend_cmd(), self.src, label + ":frontend", out=man, err=felog)
        rec["manifest_bytes"] = man.stat().st_size if man.exists() else None
        self.record(label + ":frontend", rec, felog)
        drvlog = self.logs / f"{label}-{n}.drv.log"
        rec2 = timed(self.build_cmd([f"--manifest-file={man}"]), self.src, label + ":driver", out=drvlog, err=str(drvlog) + ".err")
        self.record(label + ":driver", rec2, drvlog)

    def check(self, label):
        rec = timed([self.a.mylang, "check", "main.my", "--timings=json"], self.src, label, err=self.logs / f"{label}.log")
        self.record(label, rec, self.logs / f"{label}.log")

    def test(self, label):
        n = len(self.results)
        log = self.logs / f"{label}-{n}.log"
        cmd = [self.a.mylang, "test", "main.my", "--cache-dir", str(self.work / "testcache")]
        rec = timed(cmd, self.src, label, out=log, err=str(log) + ".err")
        self.record(label, rec)

    def next_token(self):
        self.token += 1
        return self.token

    def trace(self, label, iface=False):
        if iface:
            iface_edit(self.mid, self.next_token())
        else:
            body_edit(self.mid, self.next_token())
        tr = self.logs / f"{label}.strace"
        cmd = ["strace", "-f", "-ttt", "-e", "trace=execve,exit_group", "-o", str(tr)] + self.build_cmd()
        rec = timed(cmd, self.src, label, out=self.logs / f"{label}.log", err=self.logs / f"{label}.err")
        rec["tools"] = spans(tr)
        self.record(label, rec, self.logs / f"{label}.log")

    def run(self):
        steps = self.a.steps.split(",")
        if self.a.reuse and self.work.exists():
            self.token = 7500 + int(time.time()) % 1000
        else:
            self.fresh()
        self.results.append({"tier": self.tier.name, "modules": self.M, "mode": self.a.mode, "mylang": self.a.mylang,
                             "load": os.getloadavg()[0]})
        if "cold" in steps:
            self.build("cold")
        if "noop" in steps:
            self.build("noop-first")
            self.build("noop")
        for s in range(self.a.samples):
            if "edit" in steps:
                body_edit(self.mid, self.next_token())
                self.build("edit")
            if "iface" in steps:
                iface_edit(self.mid, self.next_token())
                self.build("iface")
            if "check" in steps:
                body_edit(self.mid, self.next_token())
                self.check("edit-check")
            if "test" in steps:
                if s == 0:
                    self.test("test-cold")
                    self.test("test-noop")
                body_edit(self.mid, self.next_token())
                self.test("edit-test")
            if "split" in steps:
                body_edit(self.mid, self.next_token())
                self.split("edit-split")
                iface_edit(self.mid, self.next_token())
                self.split("iface-split")
        if "trace" in steps:
            self.trace("edit-trace")
        if "trace-iface" in steps:
            self.trace("iface-trace", iface=True)
        summary = {}
        for r in self.results[1:]:
            summary.setdefault(r["label"], []).append(r)
        out = {"summary": {k: {"min_wall_s": min(x["wall_s"] for x in v if x.get("rc") == 0) if any(x.get("rc") == 0 for x in v) else None,
                                "max_rss_mb": round(max((x.get("max_rss_kb") or 0) for x in v) / 1024, 1),
                                "n": len(v)} for k, v in summary.items()},
               "load_end": os.getloadavg()[0]}
        print(json.dumps(out), flush=True)
        (self.work / f"probe-{self.a.tag}.json").write_text(json.dumps(self.results + [out], indent=1))


def spans(path):
    """Group strace execve/exit lines into per-tool wall spans."""
    starts, tools, first, names = {}, {}, None, {}
    for line in Path(path).read_text(errors="replace").splitlines():
        m = re.match(r"(\d+) +([\d.]+) (.*)", line)
        if not m:
            continue
        pid, t, rest = int(m.group(1)), float(m.group(2)), m.group(3)
        first = t if first is None else first
        cm = re.search(r"SIGCHLD \{.*si_pid=(\d+).*si_utime=(\d+).*si_stime=(\d+)", rest)
        if cm and int(cm.group(1)) in names:
            d = tools.setdefault(names[int(cm.group(1))], {"n": 0, "sum_s": 0.0, "first_start": None, "last_end": None})
            d["cpu_s"] = round(d.get("cpu_s", 0.0) + (int(cm.group(2)) + int(cm.group(3))) / 100.0, 2)
        if rest.startswith("execve(") and "= 0" in rest or ("execve(" in rest and "resumed" in rest and "= 0" in rest):
            mm = re.search(r'execve\("([^"]+)", \["([^"]*)"(?:\.\.\.)?(?:, "([^"]*)")?', rest)
            if mm:
                name = os.path.basename(mm.group(1))
                if name in ("zig", "mylang") and mm.group(3):
                    name += " " + mm.group(3)
                starts[pid] = (name, t)
                names[pid] = name
        elif "exit_group(" in rest or "+++ exited" in rest:
            if pid in starts:
                name, t0 = starts.pop(pid)
                d = tools.setdefault(name, {"n": 0, "sum_s": 0.0, "first_start": None, "last_end": None})
                d["n"] += 1
                d["sum_s"] += t - t0
                d["first_start"] = round(t0 - first, 4) if d["first_start"] is None else min(d["first_start"], round(t0 - first, 4))
                d["last_end"] = round(t - first, 4) if d["last_end"] is None else max(d["last_end"], round(t - first, 4))
    for d in tools.values():
        d["sum_s"] = round(d["sum_s"], 4)
    return tools


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tier")
    ap.add_argument("--mylang", default=os.environ.get("MYLANG_BIN"))
    ap.add_argument("--mode", default="default")
    ap.add_argument("--samples", type=int, default=3)
    ap.add_argument("--work")
    ap.add_argument("--tag", default="probe")
    ap.add_argument("--steps", default="cold,noop,edit,iface,check,split,trace")
    ap.add_argument("--reuse", action="store_true", help="keep an existing work directory (warm caches)")
    a = ap.parse_args()
    Probe(a).run()


if __name__ == "__main__":
    main()
