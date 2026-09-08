"""Deterministic public/private request generation, separate from expected models."""
import random
import hashlib
import base64
from .boundaries import probes
from .catalog import IDS
from .oracles import batch_expected

PUBLIC = {
'data-rollup':[{'rows':[]},{'rows':[{'key':'b','delta':-2},{'key':'a','delta':7},{'key':'b','delta':2}],'minimum':0}],
'ascii-table':[{'columns':0,'rows':[[],[]]},{'columns':2,'rows':[['a','xyz'],['long','']]},{'columns':3,'rows':[]}],
'config-layers':[{'layers':[]},{'layers':[{'enabled':False,'timeout':0},{'timeout':None,'label':'x'},{'enabled':None}]}],
'quota-boundary':[{'limit':5,'used':2,'requests':[3,0,1]},{'limit':0,'used':0,'requests':[0,1]}],
'lru-cache':[{'capacity':0,'operations':[{'op':'put','key':'a','value':1},{'op':'get','key':'a'}]},
 {'capacity':2,'operations':[{'op':'put','key':'a','value':1},{'op':'put','key':'b','value':2},{'op':'get','key':'a'},{'op':'put','key':'c','value':3}]}],
'ttl-boundary':[{'operations':[]},{'operations':[{'op':'put','at':1,'key':'a','value':7,'ttl':2},{'op':'get','at':3,'key':'a'}]},
 {'operations':[{'op':'put','at':0,'key':'a','value':1,'ttl':0},{'op':'get','at':0,'key':'a'}]}],
'record-frames':[{'records':[]},{'records':[{'tag':255,'data':''},{'tag':1,'data':'0001ff'}]}],
'little-endian-read':[{'hex':'','offsets':[]},{'hex':'0102ff00','offsets':[0,1,2,0]},{'hex':'01','offsets':[0]}],
'snapshot-diff':[{'before':[],'after':[]},{'before':[{'path':'/a','digest':'x'},{'path':'/b','digest':'y'}],'after':[{'path':'/a','digest':'z'},{'path':'/c','digest':'y'}]}],
'mount-routing':[{'mounts':[],'paths':['/']},{'mounts':[{'prefix':'/','target':'/root'},{'prefix':'/a','target':'/x'},{'prefix':'/a/b','target':'/'}],'paths':['/a','/ab','/a/b/c','/']}],
'inventory-reservations':[{'stock':[],'operations':[]},{'stock':[{'id':'a','quantity':5}],'operations':[{'op':'reserve','token':'t','id':'a','quantity':5},{'op':'reserve','token':'t','id':'z','quantity':1},{'op':'release','token':'t'},{'op':'release','token':'t'}]}],
'atomic-transfers':[{'accounts':[],'batches':[[]]},{'accounts':[{'id':'a','balance':5},{'id':'b','balance':0}],'batches':[[{'from':'a','to':'b','amount':3},{'from':'a','to':'b','amount':3}],[{'from':'a','to':'b','amount':5}]]}],
}


def random_request(task, r, index):
    keys=['a','b','c','d']; count=r.randrange(1,25)
    if task=='data-rollup':return {'rows':[{'key':r.choice(keys),'delta':r.randint(-100,100)} for _ in range(count)],'minimum':r.randint(-100,100)}
    if task=='ascii-table':
        cols=r.randrange(9)
        return {'columns':cols,'rows':[[''.join(r.choices(' aZ|09',k=r.randrange(12))) for _ in range(cols)] for _ in range(r.randrange(12))]}
    if task=='config-layers':return {'layers':[{r.choice(['timeout','retries','label','enabled']):None} if i%3==0 else {'timeout':r.randrange(60001),'enabled':bool(r.randrange(2))} for i in range(count)]}
    if task=='quota-boundary':
        limit=r.randrange(101);used=r.randrange(limit+1)
        return {'limit':limit,'used':used,'requests':[limit-used,0]+[r.randrange(101) for _ in range(count)]}
    if task=='lru-cache':return {'capacity':r.randrange(5),'operations':[{'op':'get','key':r.choice(keys)} if i%3==0 else {'op':'put','key':r.choice(keys),'value':r.randint(-100,100)} for i in range(count)]}
    if task=='ttl-boundary':
        now=0;ops=[]
        for i in range(count):
            now+=r.randrange(4);key=r.choice(keys)
            ops.append({'op':'get','at':now,'key':key} if i%3==0 else {'op':'put','at':now,'key':key,'value':r.randint(-10,10),'ttl':r.randrange(5)})
        return {'operations':ops}
    if task=='record-frames':return {'records':[{'tag':r.randrange(256),'data':bytes(r.randrange(256) for _ in range(r.randrange(33))).hex()} for _ in range(count)]}
    if task=='little-endian-read':
        data=bytes(r.randrange(256) for _ in range(count+2))
        return {'hex':data.hex(),'offsets':[r.randrange(len(data)-(0 if index%4==0 else 1)) for _ in range(count)]}
    if task=='snapshot-diff':return {side:[{'path':'/'+key,'digest':r.choice(keys)} for key in keys if r.randrange(2)] for side in ('before','after')}
    if task=='mount-routing':return {'mounts':[{'prefix':p,'target':r.choice(['/','/x','/x/y'])} for p in ['/','/a','/a/b','/c'] if r.randrange(2)],'paths':['/','/a','/a/b','/a/b/c','/aa','/c/d']}
    if task=='inventory-reservations':return {'stock':[{'id':k,'quantity':r.randrange(8)} for k in keys[:3]],'operations':[{'op':'release','token':r.choice(keys)} if i%3==0 else {'op':'reserve','token':r.choice(keys),'id':r.choice(keys),'quantity':r.randrange(1,8)} for i in range(count)]}
    if task=='atomic-transfers':return {'accounts':[{'id':k,'balance':r.randrange(20)} for k in keys[:3]],'batches':[[{'from':r.choice(keys),'to':r.choice(keys),'amount':r.randrange(12)} for _ in range(r.randrange(6))] for _ in range(count)]}
    raise ValueError('unknown task')


def build(task, seed, public=False):
    if task not in IDS or type(seed) is not str or not seed.strip():raise ValueError('known task and nonempty seed required')
    material=('public-v1' if public else seed)+'\0'+task
    r=random.Random(int.from_bytes(hashlib.sha256(material.encode()).digest(),'big'))
    requests=list(PUBLIC[task])
    requests += [random_request(task,r,i) for i in range(4 if public else 48)]
    # Shared structural negatives do not depend on either oracle implementation.
    if not public: requests += probes(task)
    requests += [None,{}, {'unexpected':1}, {**PUBLIC[task][0], 'unknown':None}]
    cases=[]
    for offset in range(0,len(requests),16):
        envelope={'requests':requests[offset:offset+16]}
        cases.append({'name':'batch-'+str(offset//16),'case':{'request':envelope,'expected':batch_expected(task,envelope)}})
    for i,envelope in enumerate([{}, {'requests':None}, {'requests':[],'extra':1}, {'requests':[{}]*65}]):
        cases.append({'name':'invalid-envelope-'+str(i),'case':{'request':envelope,'expected':{'error':'invalid-envelope'}}})
    malformed = [b'{', b'{"requests":[],"requests":[]}', b'\xff', b'{"requests":[]} {}',
                 b'{"requests":["\\ud800"]}', b'{"requests":[1e9999]}']
    if not public:
        malformed += [b'{"requests":[9223372036854775808]}',
                      b'{"requests":['+b'['*31+b'0'+b']'*31+b']}',
                      b'{"requests":[]}'+b' '*(1048577-len(b'{"requests":[]}')),
                      b' ' * 2097152]
        exact=b'{"requests":[]}'+b' '*(1048576-len(b'{"requests":[]}'))
        cases.append({'name':'transport-byte-limit','case':{'request_base64':base64.b64encode(exact).decode('ascii'),'expected':{'results':[]}}})
    for i,raw in enumerate(malformed):
        cases.append({'name':'invalid-transport-'+str(i),'case':{
            'request_base64':base64.b64encode(raw).decode('ascii'),
            'expected':{'error':'invalid-envelope'}}})
    return cases
