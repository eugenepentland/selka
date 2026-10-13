"""Keep allocator observations raw; require exact semantic traffic and projected delta accounting."""
def compare(a,b):
 def normalized(value):
  if isinstance(value,list):return [normalized(v) for v in value]
  if isinstance(value,dict):return {k:normalized(v) for k,v in value.items() if k not in ['realloc_moves','realloc_moved_bytes'] and not (k=='extra' and value.get('kind') in ['list_push'])}
  return value
 x=normalized(a);y=normalized(b)
 for name in ['list_push']:
  if name in x['kinds']:x['kinds'][name].pop('extra',None);y['kinds'][name].pop('extra',None)
 assert x==y,'non-placement counter mismatch'
 delta=b['totals']['realloc_moved_bytes']-a['totals']['realloc_moved_bytes'];assert sum(v['extra'] for v in b['kinds'].values())-sum(v['extra'] for v in a['kinds'].values())in [0,delta]
 assert sum(v['extra'] for v in b['sites'])-sum(v['extra'] for v in a['sites'])in [0,delta]
 for fa,fb in zip(a['functions'],b['functions']):
  sa=sum(v['extra'] for v in a['sites'] if v['function']==fa['name']);sb=sum(v['extra'] for v in b['sites'] if v['function']==fb['name']);assert sb-sa in [0,fb['realloc_moved_bytes']-fa['realloc_moved_bytes']],fa['name']
