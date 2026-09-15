#!/usr/bin/env python3
"""Consolidated Wave 3.1 regression probes for the six review findings."""
import json, os, subprocess, tempfile, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ML = os.environ.get("ML", os.path.join(ROOT, "zig-out", "bin", "mylang"))
fails = []

def run(args, cwd=None):
    return subprocess.run([ML] + args, cwd=cwd, capture_output=True, text=True)

def deps(entry, cache=None):
    args = ["project-dependencies", entry]
    if cache: args.append("--cache-dir=" + cache)
    p = run(args)
    if p.returncode != 0: raise RuntimeError("project-dependencies failed: " + p.stderr[:200])
    return json.loads(p.stdout)

def piface(r): return r["incremental"]["project_interface_sha256"]
def decl_iface(r, module, name):
    for m in r["incremental"]["modules"]:
        if m["name"] == module:
            for d in m["declarations"]:
                if d["name"] == name: return d.get("interface_sha256")
    raise KeyError((module, name))

def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ((" — " + detail) if detail else ""))
    if not cond: fails.append(name)

def report_line(stderr, version):
    for line in stderr.splitlines():
        line=line.strip()
        if line.startswith("{") and version in line:
            try: return json.loads(line)
            except Exception: pass
    return None

root = tempfile.mkdtemp(prefix="w31-all-")

# F1: a body edit must invalidate lowering/emission/linking and change execution.
app = os.path.join(root, "f1"); os.makedirs(app)
entry = os.path.join(app, "main.my")
def w1(text): open(entry,"w").write(text)
base = """module main
export helper
export main

def helper(n: i64) -> i64:
    return n + 2

def main() -> i64:
    return helper(40)
"""
w1(base)
cache1 = os.path.join(root, "f1cache")
r0 = run(["run", entry, "--explain-invalidation", "--cache-dir=" + cache1])
w1(base.replace("n + 2","n + 3"))
r1 = run(["run", entry, "--explain-invalidation", "--cache-dir=" + cache1])
rep = report_line(r1.stderr, "invalidation-report-v1")
q = {x["stage"]: x for x in rep["queries"]} if rep else {}
check("F1 execution changes on body edit", r0.returncode == 42 and r1.returncode == 43, f"{r0.returncode}->{r1.returncode}")
for s in ("check_body","lower_function","emit_fragment","link"):
    check(f"F1 {s} misses after body edit", q.get(s,{}).get("status") == "miss", q.get(s,{}).get("status","none"))
# check-project must mark lowering/emission/linking skipped, not hit.
r2 = run(["check-project", entry, "--explain-invalidation", "--cache-dir=" + cache1])
rep2 = report_line(r2.stderr, "invalidation-report-v1")
q2 = {x["stage"]: x for x in rep2["queries"]} if rep2 else {}
for s in ("lower_function","emit_fragment","link"):
    check(f"F1 check-project {s} skipped", q2.get(s,{}).get("status") == "skipped", q2.get(s,{}).get("status","none"))

# F2: constant and effect ceiling change the project interface; comment does not.
d = os.path.join(root, "f2"); os.makedirs(d); e = os.path.join(d, "main.my")
def w2(t): open(e,"w").write(t)
w2("module main\nexport K\n\n\nconst K: i64 = 41\n\n\ndef main() -> i64:\n    return K\n")
a = piface(deps(e)); w2("module main\nexport K\n\n\nconst K: i64 = 42\n\n\ndef main() -> i64:\n    return K\n")
b = piface(deps(e)); check("F2 exported constant changes project interface", a != b)
w2("module main\nexport tick\n\n\ndef tick() -> i64 effects(clock):\n    return 1\n\n\ndef main() -> i64:\n    return tick()\n")
c = piface(deps(e)); w2("module main\nexport tick\n\n\ndef tick() -> i64 effects(random):\n    return 1\n\n\ndef main() -> i64:\n    return tick()\n")
d2 = piface(deps(e)); check("F2 effect ceiling changes project interface", c != d2)
g = "module main\nexport id\n\n\ndef id[T](n: T) -> T:\n    return n\n\n\ndef main() -> i64:\n    return id[i64](41)\n"
w2(g); e1 = piface(deps(e)); w2(g.replace("module main\n","module main\n# unrelated comment\n",1)); e2 = piface(deps(e))
check("F2 unrelated comment does not change project interface", e1 == e2)

# F3: default argument changes the declaration and project interface.
d = os.path.join(root, "f3"); os.makedirs(d); e = os.path.join(d, "main.my")
def w3(t): open(e,"w").write(t)
w3("module main\nexport value\n\n\ndef value(n: i64 = 41) -> i64:\n    return n\n\n\ndef main() -> i64:\n    return value()\n")
r = deps(e); i0 = decl_iface(r,"main","value"); p0 = piface(r)
w3("module main\nexport value\n\n\ndef value(n: i64 = 42) -> i64:\n    return n\n\n\ndef main() -> i64:\n    return value()\n")
r = deps(e); i1 = decl_iface(r,"main","value"); p1 = piface(r)
check("F3 default value changes declaration interface", i0 != i1)
check("F3 default value changes project interface", p0 != p1)

# F4: specialization key follows concrete provider shape and target.
d = os.path.join(root, "f4"); os.makedirs(d); e = os.path.join(d, "main.my")
def w4(t): open(e,"w").write(t)
one = """module main
export HasValue
export value_of
constraint HasValue[T] = copy + field(value: i64)


record Payload:
    value: i64


def value_of[T: HasValue](item: T) -> i64:
    return item.value


def main() -> i64:
    return value_of(Payload(value=7))
"""
padded = one.replace("record Payload:\n    value: i64","record Payload:\n    padding: i64\n    value: i64").replace("Payload(value=7)","Payload(padding=0, value=7)")
w4(one); s0 = deps(e)["incremental"]["specializations"][0]["key_sha256"]
w4(padded); s1 = deps(e)["incremental"]["specializations"][0]["key_sha256"]
check("F4 provider shape changes specialization key", s0 != s1)

# F5: a rejected check still emits an invalidation report.
d = os.path.join(root, "f5"); os.makedirs(d); e = os.path.join(d, "main.my")
def w5(t): open(e,"w").write(t)
w5("module main\nexport main\n\n\ndef main() -> i64:\n    return 0\n")
cache5 = os.path.join(root, "f5cache")
run(["check-project", e, "--explain-invalidation", "--cache-dir=" + cache5])
w5("module main\nexport main\n\n\ndef main() -> i64:\n    return True\n")
r = run(["check-project", e, "--explain-invalidation", "--cache-dir=" + cache5])
check("F5 rejected check emits a report", report_line(r.stderr,"invalidation-report-v1") is not None and r.returncode == 1)

# F6: a structurally empty baseline is corrupt, never a hit.
d = os.path.join(root, "f6"); os.makedirs(d); e = os.path.join(d, "main.my")
def w6(t): open(e,"w").write(t)
w6("module main\nexport main\n\n\ndef main() -> i64:\n    return 0\n")
cache6 = os.path.join(root, "f6cache")
run(["check-project", e, "--explain-invalidation", "--cache-dir=" + cache6])
open(os.path.join(cache6, "invalidation", "main.json"), "w").write("{}")
r = run(["check-project", e, "--explain-invalidation", "--cache-dir=" + cache6])
rep = report_line(r.stderr, "invalidation-report-v1")
check("F6 empty baseline has no hits", rep is not None and rep["hits"] == 0, json.dumps({k:rep[k] for k in ("hits","misses","skipped")}) if rep else "no report")
if rep:
    reasons = {x.get("first_changed") for x in rep["queries"] if x.get("first_changed")}
    check("F6 empty baseline is corrupt-baseline", reasons == {"corrupt-baseline"}, str(reasons))

print()
if fails:
    print("FAILED:", ", ".join(fails)); sys.exit(1)
print("all Wave 3.1 probes passed")
