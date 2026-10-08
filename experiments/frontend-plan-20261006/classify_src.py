import subprocess,re,os,collections
B="codex/new-core-s3-integration"
files=subprocess.check_output(["git","ls-tree","-r","--name-only",B,"src"],text=True).split()
src={f:subprocess.check_output(["git","show",f"{B}:{f}"],text=True,errors="replace") for f in files}
loc={f:len(s.splitlines()) for f,s in src.items()}
imp={}
for f,s in src.items():
    d=os.path.dirname(f); out=set()
    for m in re.findall(r'@import\("([^"]+\.zig)"\)',s):
        p=os.path.normpath(os.path.join(d,m))
        if p in src: out.add(p)
    for m in re.findall(r'@embedFile\("([^"]+)"\)',s):
        p=os.path.normpath(os.path.join(d,m))
        if p in src: out.add(p)
    imp[f]=out
def clos(roots,stop=set()):
    seen=set(); st=list(roots)
    while st:
        x=st.pop()
        if x in seen or x in stop: continue
        seen.add(x); st+=imp.get(x,())
    return seen
test=lambda f: f.endswith("_test.zig") or "/native_fixtures/" in f
fe=clos(["src/sema.zig","src/parser.zig","src/lexer.zig","src/typed.zig"])
core={f for f in files if f.startswith("src/core/")}
old=clos(["src/qbe.zig","src/lower.zig","src/qbe_build.zig","src/bytecode.zig"],stop=fe)
cat={}
for f in files:
    if test(f): c="tests"
    elif f in core: c="new core"
    elif f in fe: c="frontend"
    elif f in old or re.match(r'src/(qbe_|native_|rc_|bytecode)',f) : c="old backend"
    elif re.match(r'src/(stdlib|board_trial|schematic|byte_io|wiring)/',f): c="apps/stdlib"
    else: c="tooling/driver/other"
    cat[f]=c
tot=collections.Counter(); n=collections.Counter()
for f,c in cat.items(): tot[c]+=loc[f]; n[c]+=1
for c,v in tot.most_common(): print(f"{c:22s} {v:7d} lines {n[c]:4d} files")
print("old-backend imported by frontend? ",sorted(f for f in fe if re.match(r'src/(qbe_|native_|rc_|lower|bytecode)',f))[:20])
open("SCRATCH/other.txt","w").write("\n".join(f"{loc[f]} {f}" for f in sorted(cat,key=lambda f:-loc[f]) if cat[f]=="tooling/driver/other"))
print("---old non-prefixed")
ol=[f for f in cat if cat[f]=="old backend" and not re.match(r'src/(qbe_|native_|rc_|bytecode)',f)]
print(sum(loc[f] for f in ol)); print(" ".join(f"{f[4:]}:{loc[f]}" for f in sorted(ol,key=lambda f:-loc[f])[:70]))
nt=[f for f in cat if cat[f]=="old backend" and re.match(r'src/native_test|src/native_bench|src/native_run|src/native_execute',f)]
print("native test/run/bench tooling in old:",sum(loc[f] for f in nt))
ext=collections.Counter()
for f in cat:
  if cat[f] in("old backend","new core"): ext[(cat[f],os.path.splitext(f)[1])]+=loc[f]
print(ext)
print("---fe top"); print(" ".join(f"{f[4:]}:{loc[f]}" for f in sorted([f for f in cat if cat[f]=="frontend"],key=lambda f:-loc[f])[:40]))
print("---fe groups")
groups=[("parse/syntax",r'(lexer|parser|ast|ast_copy|tokens|syntax|source|python_layout|.*_literal|number_grammar|float_syntax|nominal_type_syntax|navigation_syntax|project_syntax|module_syntax)'),
("caching/incremental",r'(.*cache.*|semantic_(key|store|entry|summary)|incremental|invalidation|identity|.*receipt.*|retention)'),
("generics/nominal",r'(generic_.*|nominal_.*|structural_.*|symbolic_.*|constraint_.*|type_catalog|interfaces|interface_files|provider.*|scoped_providers)'),
("sema core",r'(sema.*|typed|prelude.*|context|declarations|callables|call_.*|records?|cell_types|data_type)'),
("effects/ownership analyses",r'(effects?.*|origins|alias_warning|mut_.*|value_semantics.*|ownership.*|mutation|option_flow|iteration_.*|loop_.*|view_cycles|dictionary_views|navigation.*)'),
("constants/formatting",r'(constant_.*|format_.*|integers|floats|truncating_math|number_.*|buffer_operations|byte_.*)'),
]
fl=[f for f in cat if cat[f]=="frontend"]; used=set()
for g,rx in groups:
    m=[f for f in fl if f not in used and re.fullmatch(rx, os.path.splitext(os.path.basename(f))[0])]
    used|=set(m); print(f"{g:28s} {sum(loc[f] for f in m):6d} {len(m):3d}  "+" ".join(f"{os.path.basename(f)}:{loc[f]}" for f in sorted(m,key=lambda f:-loc[f])[:8]))
rest=[f for f in fl if f not in used]; print(f"{'other':28s} {sum(loc[f] for f in rest):6d} {len(rest):3d}  "+" ".join(f"{os.path.basename(f)}:{loc[f]}" for f in sorted(rest,key=lambda f:-loc[f])[:25]))
