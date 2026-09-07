"""Role extension CLI regression cases; stdlib fixture/assertion driver only."""
import copy
import itertools
import json
from test_cli import board, component, invoke, result

def fixture():
    return board(components=[component('a', pins=['p','q','r'])],
                 nets=[{'id':'n','members':[{'component':'a','pin':p} for p in ['p','q','r']]}])

def tests():
    baseline = result(fixture())
    count = 0
    for roles in itertools.product(['passive','input','output'], repeat=3):
        b = fixture()
        b['components'][0]['pin_roles'] = [dict(pin=p,role=r) for p,r in zip(['p','q','r'],roles)]
        expected = copy.deepcopy(baseline)
        code = 'multiple-drivers' if roles.count('output') >= 2 else 'undriven-input-net' if 'input' in roles and 'output' not in roles else None
        expected['findings'] = [] if code is None else [dict(code=code,subjects=['n'])]
        assert result(b) == expected, roles
        count += 1

    bad = [None, {}, 'input', True, 1, [None], [True], [[]], [{}],
           [{'pin':'p'}], [{'role':'input'}], [{'pin':'p','role':'INPUT'}],
           [{'pin':'p','role':None}], [{'pin':1,'role':'input'}],
           [{'pin':'absent','role':'input'}],
           [{'pin':'p','role':'input','extra':0}],
           [{'pin':'p','role':'input'},{'pin':'p','role':'input'}],
           [{'pin':'p','role':'input'},{'pin':'p','role':'output'}],
           [{'pin':'p','role':'passive'}]*33]
    for value in bad:
        b = fixture()
        b['components'][0]['pin_roles'] = value
        assert result(b) == {'error':'invalid-board'}, value
        count += 1
    for missing in ['id','x','y','width','height','pins']:
        b = fixture()
        b['components'][0]['pin_roles'] = []
        del b['components'][0][missing]
        assert result(b) == {'error':'invalid-board'}, missing
        count += 1
    for key in ['role', 'extra']:
        b = fixture()
        b['components'][0]['pin_roles'] = []
        b['components'][0][key] = []
        assert result(b) == {'error':'invalid-board'}, key
        count += 1
    b = fixture()
    b['components'][0]['pin_roles'] = []
    assert result(b) == baseline
    # Full 32-role boundary, intentionally reverse order; only connected pins count.
    b = board(components=[component('a',pins=['p'+str(i) for i in range(32)])])
    b['components'][0]['pin_roles'] = [dict(pin='p'+str(i),role='input') for i in reversed(range(32))]
    assert all(f['code']=='unconnected-pin' for f in result(b)['findings'])
    # Findings of all six codes coexist in exact code/subjects order.
    b = board(width=10,height=10,components=[
        component('z',x=-1,pins=['p','q','r','s','t']),
        component('a',pins=['p','q'])],
        nets=[dict(id='z',members=[dict(component='z',pin='p'),dict(component='z',pin='q')]),
              dict(id='a',members=[dict(component='z',pin='r')]),
              dict(id='empty',members=[])])
    b['components'][0]['pin_roles'] = [dict(pin=p,role=r) for p,r in [('p','output'),('q','output'),('r','input'),('s','input')]]
    findings = result(b)['findings']
    assert findings == [
        dict(code='clearance',subjects=['a','z']),
        dict(code='multiple-drivers',subjects=['z']),
        dict(code='outside-board',subjects=['z']),
        *[dict(code='unconnected-pin',subjects=[c,p]) for c,p in [('a','p'),('a','q'),('z','s'),('z','t')]],
        dict(code='underconnected-net',subjects=['a']),
        dict(code='underconnected-net',subjects=['empty']),
        dict(code='undriven-input-net',subjects=['a'])], findings
    # Schema and reference phase ordering.
    b = fixture()
    b['components'][0]['pin_roles'] = [dict(pin='missing',role='input')]
    b['components'].append(copy.deepcopy(b['components'][0]))
    assert result(b)=={'error':'invalid-board'}
    b = fixture()
    b['components'][0]['pin_roles']=[dict(pin='p',role='input')]
    b['nets'][0]['members'].append(dict(component='missing',pin='p'))
    assert result(b)==dict(error='unknown-pin',refs=[dict(component='missing',pin='p')])
    b['nets'][0]['members'][-1]=dict(component='a',pin='p')
    assert result(b)==dict(error='reused-pin',refs=[dict(component='a',pin='p')])
    # Decoded spelling equality for keys, pin IDs and role strings.
    b = fixture()
    b['components'][0]['pin_roles']=[dict(pin='p',role='input')]
    raw=json.dumps(dict(cases=[b])).encode()
    escaped=raw.replace(b'"pin_roles"',b'"pin_\\u0072oles"').replace(b'"input"',b'"\\u0069nput"').replace(b'"p"',b'"\\u0070"')
    assert invoke(escaped)==invoke(raw)
    duplicate=raw.replace(b'"role": "input"',b'"role":"input","\\u0072ole":"output"')
    assert invoke(duplicate)==dict(error='invalid-request')
    print('role tests passed: 27 role combinations, 19 invalid role shapes, required fields, limits, ordering, precedence and escapes')

if __name__ == '__main__':
    tests()
