"""Independent specification oracle; Python native parsers never enter timing."""
import csv
import io
import json
MOD = 1000000007
CASES = {
    'bytes_scan': {'family':'bytes','level':'micro','sizes':[64,4096],'unit':'one full byte-buffer scan','description':'Sum every input byte XOR a changing 8-bit mask.'},
    'string_equal': {'family':'strings','level':'micro','sizes':[64,4096],'unit':'one string equality comparison','description':'Rotate long equal, late mismatch, early mismatch, and short UTF-8 equal pairs.'},
    'string_search': {'family':'strings','level':'micro','sizes':[64,4096],'unit':'one substring search','description':'Rotate early hit, late hit, absent needle and Unicode hit; return scalar index.'},
    'string_split': {'family':'strings','level':'micro','sizes':[64,4096],'unit':'one full document split and result fold','description':'Split SIZE fields with alternating explicit separators, preserving empty fields.'},
    'string_join': {'family':'strings','level':'micro','sizes':[64,4096],'unit':'one full fragment join and output fold','description':'Join SIZE fields with alternating one/two-byte separators.'},
    'int_parse': {'family':'conversion','level':'micro','sizes':[64,4096],'unit':'one strict signed decimal parse','description':'Cycle a seeded working set with valid, negative, leading-zero and malformed text.'},
    'int_format': {'family':'conversion','level':'micro','sizes':[64,4096],'unit':'one signed decimal formatting and output fold','description':'Cycle a seeded numeric working set with negative and positive integers.'},
    'word_count': {'family':'text_application','level':'application','sizes':[16,256],'unit':'one complete tokenize/count/fold job','description':'Tokenize ASCII whitespace and count a mixed UTF-8 vocabulary in a native map.'},
    'csv_aggregate': {'family':'text_application','level':'application','sizes':[16,256],'unit':'one complete CSV parse/validate/group/fold job','description':'Quote-aware CSV records, rejected numeric data, active-row aggregation by region.'},
    'json_transform': {'family':'text_application','level':'application','sizes':[16,256],'unit':'one complete JSON parse/filter/transform/serialize/fold job','description':'Native-library JSON workload; parse records, filter active rows, change amounts and serialize.'},
}
def score(text):
    raw=text.encode('utf-8')
    return len(raw)+sum(raw)
def name(j):
    return ('café,"item"' if j%2==0 else 'naïve,item')+str(j)
def tokens(size, seed):
    return [('', 'alpha', 'café', 'x', 'naïve')[(seed+j)%5] for j in range(size)]
def fixtures(case,size,seed):
    if case=='bytes_scan': return bytes((seed+j*37)%256 for j in range(size))
    if case=='string_equal':
        text='a'*size
        unicode='é'*size
        return [(text,''.join(['a']*size)),(unicode,'é'*(size-1)+'ê'),(text,'b'+'a'*(size-1)),('café'+str(seed),'café'+str(seed))]
    if case=='string_search': return 'a'*size+';café;needle;'+str(seed),['a','needle','absentΩ','é']
    if case in ('string_split','string_join'): return tokens(size,seed)
    if case=='int_parse':
        out=[]
        for j in range(size):
            n=(seed+j*137)%1000003
            out.append((str(n),'-'+str(n),'00'+str(n),str(n)+'x','oops','')[j%6])
        return out
    if case=='int_format': return [(-1 if j%3==0 else 1)*((seed+j*137)%1000003) for j in range(size)]
    if case=='word_count':
        vocabulary=['red','blue','café','red','green','blue','naïve','red']
        chunks=[vocabulary[(j+seed)%8]+(' ','\t','\n','  ')[j%4] for j in range(size)]
        return [''.join(chunks)+'red',''.join(chunks)+'blue']
    if case=='csv_aggregate':
        rows=[]
        for j in range(size):
            amount='oops' if j%11==0 else str((seed+j*19)%100003)
            rows.append([str(seed+j),name(j),('east','west','north')[(seed+j)%3],amount,'1' if (seed+j)%3!=0 else '0'])
        stream=io.StringIO(newline='')
        csv.writer(stream,lineterminator='\n').writerows(rows)
        return stream.getvalue()
    if case=='json_transform':
        rows=[{'id':seed+j,'name':name(j),'amount':(seed+j*19)%100003,'active':(seed+j)%3!=0} for j in range(size)]
        return json.dumps(rows,ensure_ascii=False,separators=(',',':'))
    raise ValueError(case)
def cycle_values(case,size,seed):
    fixture=fixtures(case,size,seed)
    if case=='bytes_scan': return [sum(value^mask for value in fixture) for mask in range(256)]
    if case=='string_equal': return [1 if a==b else 0 for a,b in fixture]
    if case=='string_search':
        text,needles=fixture
        return [text.find(needle)+1 for needle in needles]
    if case=='string_split':
        values=[]
        for separator in ('|','::'):
            parts=separator.join(fixture).split(separator)
            values.append(len(parts)*7+sum(score(p) for p in parts))
        return values
    if case=='string_join': return [score(separator.join(fixture)) for separator in ('|','::')]
    if case=='int_parse':
        return [int(text) if text and all(ch in '0123456789' for ch in text.lstrip('-')) else 97 for text in fixture]
    if case=='int_format': return [score(str(n)) for n in fixture]
    if case=='word_count':
        from collections import Counter
        return [sum(score(word)*count*count for word,count in Counter(text.split()).items()) for text in fixture]
    if case=='csv_aggregate':
        groups={'east':0,'west':0,'north':0}; accepted=0; rejected=0; names=0
        for row in csv.reader(io.StringIO(fixture)):
            try: amount=int(row[3])
            except ValueError: rejected+=1; continue
            if row[4]=='1':
                accepted+=1; groups[row[2]]+=amount; names+=score(row[1])
        return [groups['east']+2*groups['west']+3*groups['north']+accepted*17+rejected*101+names]
    if case=='json_transform':
        parsed=json.loads(fixture)
        return [score(json.dumps([{'id':r['id'],'name':r['name'],'amount':r['amount']+bump} for r in parsed if r['active']],ensure_ascii=False,separators=(',',':'))) for bump in range(17)]
    raise ValueError(case)
def checksum(case,size,iterations,seed):
    values=cycle_values(case,size,seed)
    # Every port starts the fixture cursor at seed and advances once per iteration.
    offset=seed%len(values)
    full,remaining=divmod(iterations,len(values))
    total=full*sum(values)+sum(values[(offset+j)%len(values)] for j in range(remaining))
    return total%MOD
