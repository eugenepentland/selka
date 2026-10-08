import re,sys,glob,os,collections
S=sys.argv[1]
sets={"eda":glob.glob(S+"/corpus/eda/**/*.my",recursive=True),"lox":glob.glob(S+"/corpus/lox/**/*.my",recursive=True),"stdlib":glob.glob(S+"/corpus/stdlib/**/*.my",recursive=True)}
def strip(line):
    line=re.sub(r'"(\\.|[^"\\])*"|\'(\\.|[^\'\\])*\'','""',line)
    return line.split('#',1)[0]
pats=[
("replace(r, f=v)",r'\breplace\('),
("field write x.f = / x.f +=",r'^\s*[a-z_]\w*(\.\w+|\[[^\]]+\])*\.\w+\s*(=|\+=|-=)(?!=)'),
("bit_*/shift_* named",r'\b(bit_and|bit_or|bit_xor|shift_left|shift_right)\('),
("& | ^ operators",r'\s[&|^]\s'),
("strings.* module",r'\bstrings\.\w+\('),
("sort.* module",r'\bsort\.\w+\('),
("sorted()/.sort()",r'\bsorted\(|\.sort\('),
("with open(",r'\bwith\s+open\('),
("effects(...) clause",r'\)\s*->.*\beffects\('),
("noio/noalloc",r'\b(noio|noalloc)\b'),
("assert",r'^\s*assert\b'),
("@requires/@ensures",r'@(requires|ensures)\b'),
("@invariant",r'@invariant\b'),
("public decl",r'^public\s'),
("export directive",r'^export\s'),
("module header",r'^module\s'),
("class decl",r'^class\s'),
("with arena",r'\bwith\s+arena\('),
("lambda",r'\blambda\b'),
("list/dict/set comprehension",r'[\[{][^\]}]*\bfor\b[^\]}]*\bin\b'),
("conditional expression",r'^(?!\s*(if|elif|while|assert)\b).*\S\s+if\s.+\selse\s'),
("semicolon separator",r';\s*\S'),
("f-string",r'\bf"'),
("+ str( concat",r'\+\s*str\(|str\([^)]*\)\s*\+'),
(".copy()",r'\.copy\(\)'),
("is None / is not None",r'\bis\s+(not\s+)?None\b'),
("== None / != None",r'[=!]=\s*None\b'),
(".unwrap_or(",r'\.unwrap_or\('),
("? propagation",r'\w\)?\?(\s|$|\)|,)'),
("match",r'^\s*match\s'),
("while loop",r'^\s*while\s'),
("for loop",r'^\s*for\s'),
("keyword arg in call",r'\w\([^)]*\b[a-z_]\w*=(?!=)'),
("debug(",r'\bdebug\('),
("type alias",r'^type\s'),
("constraint decl",r'^constraint\s'),
("generic def",r'^(public\s+)?def\s+\w+\['),
("[N]T fixed array type",r':\s*\[\w+\]\w'),
("slice [a:b]",r'\[[^\]\[]*:[^\]\[]*\]'),
("mut param",r':\s*mut\s'),
("record decl",r'^(public\s+)?record\s'),
("union/enum decl",r'^(public\s+)?(union|enum)\s'),
]
res=collections.OrderedDict(); lines={}
for k,fs in sets.items():
    L=[strip(l) for f in fs for l in open(f,errors="replace")]
    lines[k]=(len(fs),sum(1 for l in L if l.strip()))
    for name,rx in pats:
        r=re.compile(rx); res.setdefault(name,{})[k]=sum(1 for l in L if r.search(l))
print("corpus files/nonblank:",lines)
print(f"{'pattern':34s} {'eda':>6s} {'lox':>6s} {'stdlib':>6s}")
for n,d in res.items(): print(f"{n:34s} {d['eda']:6d} {d['lox']:6d} {d['stdlib']:6d}")
