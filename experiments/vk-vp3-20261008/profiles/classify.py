import re,sys,subprocess,collections
data=sys.argv[1]; top=int(sys.argv[2]) if len(sys.argv)>2 else 12
rep=subprocess.run(["perf","report","-i",data,"--stdio","--sort","symbol"],capture_output=True,text=True).stdout
syms=[]
for line in rep.splitlines():
    m=re.match(r"\s+([0-9.]+)%\s+\[\.\]\s+(\S+)",line)
    if m: syms.append((float(m.group(1)),m.group(2)))
syms=syms[:top]
agg=collections.Counter(); covered=0
for share,sym in syms:
    if sym.startswith("0x"): continue
    out=subprocess.run(["perf","annotate","-i",data,"--stdio","-s",sym],capture_output=True,text=True).stdout
    loc=collections.Counter()
    for line in out.splitlines():
        m=re.match(r"\s+([0-9]+\.[0-9]+)\s+:\s+[0-9a-f]+:\s+(\S+)\s*(.*)",line)
        if not m: continue
        p=float(m.group(1)); op=m.group(2); a=m.group(3)
        if op.startswith('vmov') or op.startswith('rep'): k='record/aggregate copies (vector moves)'
        elif op in ('dec','inc') or (op in ('add','sub','lock') and '$0x1,' in a and '(%' in a): k='count +/-1'
        elif op=='cmp' and '$0xffffffff' in a: k='count saturation check'
        elif op.startswith('call'): k='calls'
        elif op.startswith('j'): k='branches'
        elif op.startswith('mov') and '(%rsp)' in a: k='scalar stack moves'
        else: k='other compute/loads'
        loc[k]+=p
    t=sum(loc.values()) or 1
    for k,v in loc.items(): agg[k]+=share*v/t
    covered+=share
for k,v in agg.most_common(): print(f"{v:6.1f}%  {k}")
print(f"{covered:6.1f}%  of all samples covered (top {top} symbols)")
