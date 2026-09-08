"""Deliberate resource maxima, schema edges and precedence probes, independent of RNG."""
from copy import deepcopy


def probes(task):
    longpath='/' + ('a'*32+'/')*7 + 'b'*24
    if task=='data-rollup':
        base={'rows':[{'key':'a'+str(i),'delta':1000000 if i%2 else -1000000} for i in range(128)],'minimum':-128000000}
        edges=[{'rows':[],'minimum':v} for v in (-128000001,128000001)]+[{'rows':[{'key':'a','delta':v}]} for v in (-1000001,1000001)]
        arrays=['rows']
    elif task=='ascii-table':
        base={'columns':8,'rows':[['a'*32]*8 for _ in range(64)]};arrays=['rows']
        edges=[{'columns':v,'rows':[]} for v in (-1,9)]+[{'columns':1,'rows':[[v]]} for v in ('a'*33,'\t','é')]+[{'columns':2,'rows':[['a']]}]
    elif task=='config-layers':
        base={'layers':[{'timeout':60000,'retries':10,'enabled':False,'label':'a'*32} for _ in range(64)]};arrays=['layers']
        edges=[{'layers':[{key:value}]} for key,values in [('timeout',[-1,60001]),('retries',[-1,11]),('enabled',[0,1]),('label',['a'*33,''])] for value in values]
        edges += [{'layers':[{'timeout':0,'retries':0,'enabled':True,'label':'a'}]}]
    elif task=='quota-boundary':
        base={'limit':1000000,'used':0,'requests':[1000000]+[0]*127};arrays=['requests']
        edges=[{'limit':v,'used':0,'requests':[]} for v in (-1,1000001)]+[{'limit':1,'used':v,'requests':[]} for v in (-1,2)]+[{'limit':1,'used':0,'requests':[v]} for v in (-1,1000001)]
    elif task=='lru-cache':
        base={'capacity':16,'operations':[{'op':'put','key':'a'+str(i%32),'value':-1000000 if i%2 else 1000000} for i in range(128)]};arrays=['operations']
        edges=[{'capacity':v,'operations':[]} for v in (-1,17)]+[{'capacity':1,'operations':[{'op':'put','key':'a','value':v}]} for v in (-1000001,1000001)]
        edges += [{'capacity':1,'operations':[{'op':'get','key':'a','value':0}]}]
    elif task=='ttl-boundary':
        base={'operations':[{'op':'put','at':1000000,'key':'a'+str(i),'value':1000000,'ttl':1000000} for i in range(128)]};arrays=['operations']
        edges=[{'operations':[{'op':'put','at':0,'key':'a','value':0,'ttl':v}]} for v in (-1,1000001)]
        edges += [{'operations':[{'op':'get','at':v,'key':'a'}]} for v in (-1,1000001)]
        edges += [{'operations':[{'op':'get','at':2,'key':'a'},{'op':'get','at':1,'key':'a'}]}]
    elif task=='record-frames':
        base={'records':[{'tag':255,'data':'ff'*32} for _ in range(32)]};arrays=['records']
        edges=[{'records':[{'tag':v,'data':''}]} for v in (-1,256)]+[{'records':[{'tag':0,'data':v}]} for v in ('ff'*33,'0','FF','gg')]
    elif task=='little-endian-read':
        base={'hex':'00ff'*256,'offsets':[510]*128};arrays=['offsets']
        edges=[{'hex':'00'*512,'offsets':[v]} for v in (-1,511,512,513)]+[{'hex':v,'offsets':[]} for v in ('00'*513,'a','AA','xx')]
        edges += [{'hex':'','offsets':[0,True]}]
    elif task=='snapshot-diff':
        base={'before':[{'path':'/a'+str(i),'digest':'a'*32} for i in range(128)],'after':[{'path':'/a'+str(i),'digest':'b'} for i in range(128)]};arrays=['before','after']
        edges=[{'before':[{'path':longpath,'digest':'a'}],'after':[]},{'before':[{'path':longpath+'b','digest':'a'}],'after':[]}]
        edges += [{'before':[{'path':'/a','digest':'a'},{'path':'/a','digest':'a'}],'after':[]}]
    elif task=='mount-routing':
        base={'mounts':[{'prefix':'/a'+str(i),'target':'/b'} for i in range(32)],'paths':['/a'+str(i%32)+'/x' for i in range(128)]};arrays=['mounts','paths']
        edges=[{'mounts':[{'prefix':'/','target':longpath}],'paths':[longpath]}, {'mounts':[{'prefix':'/a','target':'/b'},{'prefix':'/a','target':'/c'}],'paths':[]}]
    elif task=='inventory-reservations':
        base={'stock':[{'id':'a'+str(i),'quantity':1000000} for i in range(32)],'operations':[{'op':'reserve','token':'t'+str(i),'id':'a'+str(i%32),'quantity':1} for i in range(128)]};arrays=['stock','operations']
        edges=[{'stock':[{'id':'a','quantity':v}],'operations':[]} for v in (-1,1000001)]
        edges += [{'stock':[],'operations':[{'op':'reserve','token':'t','id':'x','quantity':v}]} for v in (0,1000001)]
        edges += [{'stock':[{'id':'a','quantity':0}]*2,'operations':[]}, {'stock':[],'operations':[{'op':'release','token':'unknown'},{'op':'reserve','token':'t','id':'a','quantity':None}]}]
    elif task=='atomic-transfers':
        base={'accounts':[{'id':'a'+str(i),'balance':1000000} for i in range(32)],'batches':[[{'from':'a'+str(i),'to':'a'+str(i),'amount':1000000} for i in range(32)] for _ in range(32)]};arrays=['accounts','batches']
        edges=[{'accounts':[{'id':'a','balance':v}],'batches':[]} for v in (-1,1000001)]
        edges += [{'accounts':[],'batches':[[{'from':'a','to':'b','amount':v}]]} for v in (-1,1000001)]
        edges += [{'accounts':[{'id':'a','balance':0}]*2,'batches':[]},{'accounts':[],'batches':[[{'from':'a','to':'b','amount':0}],[{'from':'a','to':'b','amount':None}]]}]
        edges += [{'accounts':base['accounts'],'batches':[base['batches'][0]+[base['batches'][0][0]]]}]
    else:raise ValueError('unknown task')
    # Max+1 array length, then boolean/float/null in every distinct scalar field.
    for field in arrays:
        changed=deepcopy(base);changed[field].append(deepcopy(changed[field][0]));edges.append(changed)
    seen=set()
    def scalars(value, route=(), field=''):
        if type(value) is dict:
            for key,child in value.items():yield from scalars(child,route+(key,),key)
        elif type(value) is list:
            if value:yield from scalars(value[0],route+(0,),field)
        elif field not in seen:
            seen.add(field);yield route,value
    for route,value in scalars(base):
        replacements=(True,1.0,None) if type(value) is int else ((0,1,None) if type(value) is bool else (1,False,None))
        for replacement in replacements:
            changed=deepcopy(base);target=changed
            for part in route[:-1]:target=target[part]
            target[route[-1]]=replacement;edges.append(changed)
    return [base]+edges
