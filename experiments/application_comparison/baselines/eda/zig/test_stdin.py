#!/usr/bin/env python3
"""Independent baseline tests. Uses only stdlib; no oracle or fixture imports."""
import copy
import json
import subprocess
import sys

binary = sys.argv[1] if len(sys.argv) > 1 else './eda-inspector'
def raw(data):
    p = subprocess.run([binary], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert p.returncode == 0, (p.returncode, p.stderr)
    return json.loads(p.stdout)
def request(cases):
    return raw(json.dumps({'cases':cases}, separators=(',', ':')).encode())['results']
def comp(name, x, y, w=1, h=1, pins=()):
    return dict(id=name,x=x,y=y,width=w,height=h,pins=list(pins))
def board(cs=(), ns=(), clearance=0, unit='um'):
    return dict(version=1,unit=unit,width=100,height=100,clearance=clearance,components=list(cs),nets=list(ns))
def ref(c,p='p'):
    return dict(component=c,pin=p)
def findings(b):
    return request([b])[0]['findings']
assert findings(board([comp('b',1,0),comp('a',0,0)])) == [] # touching at zero
assert findings(board([comp('a',0,0,2),comp('b',1,0)])) == [dict(code='clearance',subjects=['a','b'])]
assert findings(board([comp('a',0,0),comp('b',4,5)],clearance=5)) == [] # 3-4-5 equality
assert findings(board([comp('a',0,0),comp('b',4,5)],clearance=6)) == [dict(code='clearance',subjects=['a','b'])]
assert findings(board([comp('a',-1,0),comp('b',99,99)])) == [dict(code='outside-board',subjects=['a'])]
b = board([comp('b',2,0,2,pins=['p']),comp('a',0,0,pins=['p','q'])],[dict(id='z',members=[ref('b'),ref('a')]),dict(id='empty',members=[])])
r = request([b])[0]
assert r['nets'] == [dict(id='empty',members=[],span=0),dict(id='z',members=[ref('a'),ref('b')],span=3)]
assert r['findings'] == [dict(code='unconnected-pin',subjects=['a','q']),dict(code='underconnected-net',subjects=['empty'])]
assert r['svg'] == '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="0" y="0" width="100" height="100" fill="white" stroke="black"/><rect id="a" x="0" y="0" width="1" height="1" fill="none" stroke="black"/><rect id="b" x="2" y="0" width="2" height="1" fill="none" stroke="black"/></svg>'
b['components'].reverse(); b['nets'].reverse(); b['nets'][0]['members'].reverse()
assert request([b])[0] == r
mm = copy.deepcopy(b); mm['unit'] = 'mm'
assert request([mm])[0]['nets'][1]['span'] == 2500
# Phase precedence, distinct sorted references, independent cases.
bad = board([comp('a',0,0,pins=['p']),comp('a',0,0,pins=['p'])],[dict(id='x',members=[ref('missing'),ref('missing')])])
assert request([bad])[0] == dict(error='duplicate-id',components=['a'],nets=[])
bad['components'][1]['pins'] = ['p','p']
assert request([bad])[0] == dict(error='invalid-board')
bad['components'].pop()
assert request([bad])[0] == dict(error='unknown-pin',refs=[ref('missing')])
bad['nets'][0]['members'] = [ref('a'),ref('a')]
assert request([bad])[0] == dict(error='reused-pin',refs=[ref('a')])
assert request([{}, board()])[0] == dict(error='invalid-board')
assert raw(b'{"cases":[]}') == dict(results=[])
for data in [b'', b'{"cases":[],"cases":[]}', b'{"cases":[NaN]}',b'{"cases":[1e400]}',b'{"cases":[9223372036854775808]}', b'{"cases":["\xff"]}',b'{"cases":[]}null']:
    assert raw(data) == dict(error='invalid-request'), data
# Total depth is 2 plus nested arrays; unknown schema must not bypass depth check.
assert raw(b'{"cases":[' + b'['*62 + b'0' + b']'*62 + b']}') == dict(results=[dict(error='invalid-board')])
assert raw(b'{"cases":[' + b'['*63 + b'0' + b']'*63 + b']}') == dict(error='invalid-request')
base=b'{"cases":[]}'
assert raw(base+b' '*(1048576-len(base))) == dict(results=[])
assert raw(base+b' '*(1048577-len(base))) == dict(error='invalid-request')
assert raw(json.dumps({'cases':[{}]*65}).encode()) == dict(error='invalid-request')
# Large legal response: 64 overlapping boards with maximum-length IDs.
large=board([comp('c'+str(i).zfill(31),0,0,pins=['p'+str(j) for j in range(6)]) for i in range(128)])
rs=request([large]*64)
assert len(rs)==64 and all(len(r['findings'])==8128+768 for r in rs)
print('stdin tests passed (transport, phases, exact SVG, geometry, sorting, scaling, large output)')
