import subprocess, sys, os
I = "/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-integration"
OLD, QBE, NEW = f"{I}/.mylang-cache/s3/oracle/mylang", f"{I}/.mylang-cache/s3/oracle/qbe", f"{I}/zig-out/bin/mylang-core"
ARGS = ["64", "2", "42"]
src = open("full.my").read()
head, body = src.split("def main(args: list[str], out: Stream) -> int:\n")
lines = body.rstrip("\n").split("\n")
# group into top-level statements (4-space indent starts a statement)
stmts, cur = [], []
for l in lines:
    if l.startswith("    ") and not l.startswith("     ") and cur:
        stmts.append(cur); cur = []
    cur.append(l)
stmts.append(cur)
def outcome(ss):
    text = head + "def main(args: list[str], out: Stream) -> int:\n" + "\n".join(l for s in ss for l in s) + "\n"
    open("cand.my", "w").write(text)
    r = []
    for name, cmd in (("old", [OLD, "build", "cand.my", "-o", "cand-old", "--qbe", QBE, "--cache-dir", "oc"]),
                      ("new", [NEW, "build", "cand.my", "-o", "cand-new", "--cache-dir", "nc"])):
        if subprocess.run(cmd, capture_output=True).returncode: return None
        p = subprocess.run([f"./cand-{name}", *ARGS], capture_output=True, text=True)
        r.append((p.returncode, p.stdout))
    return r
def differs(ss):
    r = outcome(ss)
    return r is not None and r[0] != r[1]
assert differs(stmts)
changed = True
while changed:
    changed = False
    for i in range(len(stmts) - 1, -1, -1):
        if stmts[i][0].strip().startswith(("out.print", "return")): continue
        trial = stmts[:i] + stmts[i+1:]
        if differs(trial):
            stmts = trial; changed = True
final = head + "def main(args: list[str], out: Stream) -> int:\n" + "\n".join(l for s in stmts for l in s) + "\n"
open("reduced.my", "w").write(final)
print("\n".join(l for s in stmts for l in s))
print(outcome(stmts))
