from pathlib import Path
import subprocess,json
root=Path(__file__).parent
compiler='/home/epentland/ai/canopy/mylang-stdlib-collections/zig-out/bin/mylang'
prefix='buffer B:u8;result Open{ok:B,err:i64}buffer Vec<T:storable>:T;result Created<T:storable>{ok:Vec<T>,err:i64}result Taken<T:storable>{ok:T,err:i64}result Status{ok:bool,err:i64}'
cases={
'inner_append': 'fn work(heap:allocator)->Status{let mut outer=try acquire_buffer<Created<B>>(heap,1);arena heap as inner{let child=try acquire_buffer<Open>(inner,1);return append_buffer<Status>(outer,child);}}',
'inner_generic_append': 'fn put<T:storable>(outer:&mut Vec<T>,value:T)->Status{return append_buffer<Status>(outer,value);}fn work(heap:allocator)->Status{let mut outer=try acquire_buffer<Created<B>>(heap,1);borrow mut outer as dest{arena heap as inner{let child=try acquire_buffer<Open>(inner,1);return put::<B>(dest,child);}}}',
'owned_double_use':'fn work(heap:allocator)->Status{let mut outer=try acquire_buffer<Created<B>>(heap,2);let child=try acquire_buffer<Open>(heap,1);discard try append_buffer<Status>(outer,child);return append_buffer<Status>(outer,child);}',
'owned_read':'fn work(heap:allocator)->Status{let outer=try acquire_buffer<Created<B>>(heap,1);discard read_buffer(outer,0);return new Status.ok(true);}',
'owned_slice':'fn work(heap:allocator)->Status{let outer=try acquire_buffer<Created<B>>(heap,1);borrow outer[0..0] as view{discard read_slice(view,0);}return new Status.ok(true);}',
'owned_array_slice':'fn work(heap:allocator)->Status{let child=try acquire_buffer<Open>(heap,1);let items=new [1]B[child];borrow items[0..1] as view{discard read_slice(view,0);}return new Status.ok(true);}',
'owned_resize':'fn work(heap:allocator)->Status{let mut outer=try acquire_buffer<Created<B>>(heap,2);let child=try acquire_buffer<Open>(heap,1);return resize_buffer<Status>(outer,2,child);}',
'generic_double_use':'fn twice<T:storable>(x:T)->T{let y=x;discard y;return x;}',
'uncalled_result_element':'buffer Bad:Status;',
'uncalled_result_array':'buffer Bad:[1]Status;',
'generic_result_array':'fn bad<T:storable>(x:T)->T{return x;}fn f(x:[1]Status)->[1]Status{return bad::<[1]Status>(x);}',
}
results=[]
for name,body in cases.items():
 path=root/(name+'.my');path.write_text(prefix+body+'fn main()->i64{return 0;}')
 p=subprocess.run([compiler,'check',str(path),'--diagnostics=json'],capture_output=True,text=True)
 results.append(dict(name=name,status=p.returncode,diagnostics=p.stderr[:800]))
print(json.dumps(results,indent=2));(root/'negative-results.json').write_text(json.dumps(results,indent=2)+'\n')
