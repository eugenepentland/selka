import sys
class Cursor:
    __slots__=("src","pos","line","col")
    def __init__(s,src): s.src=src; s.pos=0; s.line=1; s.col=1
def peek(c): return c.src[c.pos] if c.pos < len(c.src) else ""
def advance(c):
    ch=c.src[c.pos]; c.pos+=1
    if ch=="\n": c.line+=1; c.col=1
    else: c.col+=1
def skip_ws(c):
    while c.pos<len(c.src):
        ch=peek(c)
        if ch.isspace(): advance(c)
        elif ch=="#":
            while c.pos<len(c.src) and peek(c)!="\n": advance(c)
        else: break
def parse_string(c):
    advance(c); out=""
    while True:
        if c.pos>=len(c.src): raise ValueError("unterminated")
        ch=peek(c)
        if ch=='"': advance(c); return ("text",out)
        if ch=="\\":
            advance(c); esc=peek(c); out += {"n":"\n","t":"\t"}.get(esc,esc); advance(c)
        else: out+=ch; advance(c)
def parse_atom(c):
    start=c.pos
    while c.pos<len(c.src):
        ch=peek(c)
        if ch.isspace() or ch=="(" or ch==")": break
        advance(c)
    return ("atom", c.src[start:c.pos])
def parse_node(c):
    skip_ws(c); ch=peek(c)
    if ch=="(": return parse_list(c)
    if ch=='"': return parse_string(c)
    return parse_atom(c)
def parse_list(c):
    advance(c); items=[]
    while True:
        skip_ws(c)
        if peek(c)==")": advance(c); return ("items",items)
        items.append(parse_node(c))
def count(n): return 1+sum(count(x) for x in n[1]) if n[0]=="items" else 1
sys.setrecursionlimit(10000)
src=open(sys.argv[1]).read()
print(count(parse_node(Cursor(src))))
