"""Independent expected-value models; never provision this module to participants.

The application implementations must not import or copy these models. Type/schema
checks complete before stateful work. Models favor clear Python value semantics.
"""
from collections import OrderedDict
import re
import struct
from .catalog import IDS


class Invalid(ValueError):
    pass


def need(value):
    if not value: raise Invalid()


def obj(value, required, optional=()):
    need(type(value) is dict and set(required) <= value.keys() and value.keys() <= set(required) | set(optional))
    return value


def integer(value, low=-1000000, high=1000000):
    need(type(value) is int and low <= value <= high)
    return value


def seq(value, limit=128):
    need(type(value) is list and len(value) <= limit)
    return value


def ident(value):
    need(type(value) is str and re.fullmatch('[a-z][a-z0-9_-]{0,31}', value) is not None)
    return value


def boolean(value):
    need(type(value) is bool)
    return value


def ascii_text(value):
    need(type(value) is str and len(value) <= 32 and all(32 <= ord(c) <= 126 for c in value))
    return value


def path(value):
    need(type(value) is str and 1 <= len(value) <= 256 and value.startswith('/'))
    if value != '/':
        for component in value[1:].split('/'):
            need(component not in ('', '.', '..') and re.fullmatch('[a-z0-9_.-]{1,32}', component) is not None)
    return value


def hexbytes(value):
    need(type(value) is str and len(value) <= 1024 and re.fullmatch('(?:[0-9a-f]{2})*', value) is not None)
    return bytes.fromhex(value)


def unique_names(values):
    for key in values: ident(key)
    need(len(values) == len(set(values)))


def rollup(q):
    obj(q, ['rows'], ['minimum'])
    minimum = integer(q.get('minimum', -128000000), -128000000, 128000000)
    rows = seq(q['rows'])
    for r in rows: obj(r,['key','delta']);ident(r['key']);integer(r['delta'])
    groups = {r['key'] for r in rows}
    result = []
    for key in sorted(groups):
        amounts = [r['delta'] for r in rows if r['key'] == key]
        total = sum(amounts)
        if total >= minimum: result.append({'key':key,'count':len(amounts),'total':total})
    return {'groups':result}


def table(q):
    obj(q,['columns','rows']); columns=integer(q['columns'],0,8); rows=seq(q['rows'],64)
    for row in rows:
        seq(row,8);need(len(row)==columns)
        for cell in row:ascii_text(cell)
    widths=[max((len(row[i]) for row in rows),default=0) for i in range(columns)]
    return {'widths':widths,'lines':[' | '.join(cell.ljust(widths[i]) for i,cell in enumerate(row)) for row in rows]}


def layers(q):
    obj(q,['layers']); values=seq(q['layers'],64)
    defaults={'timeout':1000,'retries':3,'enabled':True,'label':'default'}
    for layer in values:
        obj(layer,[],defaults)
        for key,value in layer.items():
            if value is None:continue
            if key=='timeout':integer(value,0,60000)
            elif key=='retries':integer(value,0,10)
            elif key=='enabled':boolean(value)
            else:ident(value)
    result=dict(defaults)
    for layer in values:
        result.update({k:defaults[k] if v is None else v for k,v in layer.items()})
    return {'config':result,'changed':sorted(k for k in defaults if result[k]!=defaults[k])}


def quota(q):
    obj(q,['limit','used','requests']);limit=integer(q['limit'],0);used=integer(q['used'],0,limit)
    requests=seq(q['requests'])
    for amount in requests:integer(amount,0)
    accepted=[]
    for amount in requests:
        fits=amount <= limit-used
        accepted.append(fits)
        if fits:used+=amount
    return {'accepted':accepted,'used':used,'remaining':limit-used}


def lru(q):
    obj(q,['capacity','operations']);capacity=integer(q['capacity'],0,16);operations=seq(q['operations'])
    for op in operations:
        need(type(op) is dict and op.get('op') in ('get','put'))
        obj(op,['op','key']+(['value'] if op['op']=='put' else []));ident(op['key'])
        if op['op']=='put':integer(op['value'])
    cache=OrderedDict();results=[]
    for op in operations:
        key=op['key']
        if op['op']=='get':
            result=cache.get(key)
            if key in cache:cache.move_to_end(key)
            results.append({'value':result})
        else:
            evicted=None
            if capacity:
                if key in cache:del cache[key]
                elif len(cache)==capacity:evicted=cache.popitem(last=False)[0]
                cache[key]=op['value']
            results.append({'evicted':evicted})
    return {'results':results,'entries':[{'key':k,'value':v} for k,v in cache.items()]}


def ttl(q):
    obj(q,['operations']);operations=seq(q['operations']);previous=0
    for op in operations:
        need(type(op) is dict and op.get('op') in ('get','put'))
        obj(op,['op','at','key']+(['value','ttl'] if op['op']=='put' else []))
        previous=integer(op['at'],previous,1000000);ident(op['key'])
        if op['op']=='put':integer(op['value']);integer(op['ttl'],0)
    # Store history, independently resolve most recent writes at every event.
    writes={};results=[]
    for op in operations:
        now=op['at'];key=op['key']
        if op['op']=='put':
            writes[key]=(op['value'],now+op['ttl']);results.append(None)
        else:
            entry=writes.get(key);results.append(entry[0] if entry and now<entry[1] else None)
    now=operations[-1]['at'] if operations else 0
    return {'results':results,'live':sorted(k for k,(_,expiry) in writes.items() if expiry>now)}


def frames(q):
    obj(q,['records']);records=seq(q['records'],32)
    for record in records:
        obj(record,['tag','data']);integer(record['tag'],0,255);need(len(hexbytes(record['data']))<=32)
    wire=bytearray();offsets=[]
    for record in records:
        data=bytes.fromhex(record['data']);offsets.append(len(wire))
        wire.extend(struct.pack('<BH',record['tag'],len(data)));wire.extend(data)
    return {'hex':wire.hex(),'offsets':offsets}


def little(q):
    obj(q,['hex','offsets']);wire=hexbytes(q['hex']);offsets=seq(q['offsets'])
    for offset in offsets:integer(offset,0,512)
    if any(offset+2>len(wire) for offset in offsets):return {'error':'out-of-bounds'}
    return {'values':[wire[offset]+256*wire[offset+1] for offset in offsets]}


def snapshot(q):
    obj(q,['before','after'])
    for side in ('before','after'):
        rows=seq(q[side]);names=[]
        for entry in rows:obj(entry,['path','digest']);names.append(path(entry['path']));ident(entry['digest'])
        need(len(names)==len(set(names)))
    before={r['path']:r['digest'] for r in q['before']};after={r['path']:r['digest'] for r in q['after']}
    return {'added':sorted(after.keys()-before.keys()),'removed':sorted(before.keys()-after.keys()),
            'changed':sorted(k for k in before.keys()&after.keys() if before[k]!=after[k])}


def mounts(q):
    obj(q,['mounts','paths']);mappings=seq(q['mounts'],32);paths=seq(q['paths']);prefixes=[]
    for mapping in mappings:obj(mapping,['prefix','target']);prefixes.append(path(mapping['prefix']));path(mapping['target'])
    need(len(prefixes)==len(set(prefixes)))
    for name in paths:path(name)
    results=[]
    for name in paths:
        candidates=[m for m in mappings if m['prefix']=='/' or name==m['prefix'] or name.startswith(m['prefix']+'/')]
        if not candidates:results.append(None);continue
        winner=max(candidates,key=lambda m:len(m['prefix']))
        suffix=name[len(winner['prefix']):].lstrip('/')
        results.append(winner['target'].rstrip('/')+('/'+suffix if suffix else '') or '/')
    return {'paths':results}


def inventory(q):
    obj(q,['stock','operations']);stock=seq(q['stock'],32);ops=seq(q['operations']);names=[]
    for item in stock:obj(item,['id','quantity']);names.append(ident(item['id']));integer(item['quantity'],0)
    unique_names(names)
    for op in ops:
        need(type(op) is dict and op.get('op') in ('reserve','release'))
        obj(op,['op','token']+(['id','quantity'] if op['op']=='reserve' else []));ident(op['token'])
        if op['op']=='reserve':ident(op['id']);integer(op['quantity'],1)
    available={item['id']:item['quantity'] for item in stock};held={};results=[]
    for op in ops:
        token=op['token']
        if op['op']=='release':
            if token not in held:results.append('unknown-token');continue
            item,amount=held.pop(token);available[item]+=amount;results.append('released')
        else:
            item=op['id'];amount=op['quantity']
            if token in held:results.append('duplicate-token')
            elif item not in available:results.append('unknown-item')
            elif available[item]<amount:results.append('insufficient')
            else:available[item]-=amount;held[token]=(item,amount);results.append('reserved')
    return {'results':results,'available':[{'id':k,'quantity':available[k]} for k in sorted(available)],'active':sorted(held)}


def transfers(q):
    obj(q,['accounts','batches']);accounts=seq(q['accounts'],32);batches=seq(q['batches'],32);names=[]
    for a in accounts:obj(a,['id','balance']);names.append(ident(a['id']));integer(a['balance'],0)
    unique_names(names)
    for batch in batches:
        seq(batch,32)
        for transfer in batch:obj(transfer,['from','to','amount']);ident(transfer['from']);ident(transfer['to']);integer(transfer['amount'],0)
    balances={a['id']:a['balance'] for a in accounts};results=[]
    for batch in batches:
        tentative=dict(balances);error=None
        for transfer in batch:
            source,target,amount=transfer['from'],transfer['to'],transfer['amount']
            if source not in tentative or target not in tentative:error='unknown-account';break
            if tentative[source]<amount:error='insufficient';break
            tentative[source]-=amount;tentative[target]+=amount
        if error is None:balances=tentative
        results.append(error or 'committed')
    return {'results':results,'balances':[{'id':k,'balance':balances[k]} for k in sorted(balances)]}


MODELS=dict(zip(IDS,(rollup,table,layers,quota,lru,ttl,frames,little,snapshot,mounts,inventory,transfers)))


def expected(task, request):
    if task not in MODELS:raise ValueError('unknown task')
    try:return MODELS[task](request)
    except Invalid:return {'error':'invalid-request'}


def batch_expected(task, envelope):
    if task not in MODELS:raise ValueError('unknown task')
    try:obj(envelope,['requests']);seq(envelope['requests'],64)
    except Invalid:return {'error':'invalid-envelope'}
    return {'results':[expected(task,request) for request in envelope['requests']]}
