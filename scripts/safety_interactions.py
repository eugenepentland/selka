"""Generated ownership/JSON/partition boundary cases with independent scalar oracles."""


def templates(rng):
    value = rng.randrange(1, 1000)
    wire_limit = rng.choice([0, 1, 4096])
    json_source = '''buffer Bytes:u8;result Encoded{ok:Bytes,err:i64}
struct Item{n:i64,valid:bool}result Decoded{ok:Item,err:i64}
fn roundtrip<T:codec>(heap:allocator,item:T)->Encoded{return json_encode::<Encoded>(heap,item,LIMIT);}
fn main(heap:allocator)->i64{arena heap as child{
match roundtrip::<Item>(child,new Item{n:VALUE,valid:true}){
Encoded.ok(bytes)=>{match json_decode::<Decoded>(child,bytes,4096){
Decoded.ok(item)=>{if item.valid{return item.n;}return -1;},Decoded.err(e)=>{return -2;}}},
Encoded.err(e)=>{discard e;return -3;}}}}'''.replace('LIMIT', str(wire_limit)).replace('VALUE', str(value))
    yield json_source, value if wire_limit == 4096 else -3, 'generic-json-arena-success-or-budget'
    midpoint = rng.randrange(5)
    partition = '''fn change<T:copy>(a:&mut []T,b:&mut []T,x:T)->i64{
if len_slice(a)>0u64{write_slice(a,0,x);}if len_slice(b)>0u64{write_slice(b,0,x);}return 0;}
fn main()->i64{let mut values=new [4]i64 [1,2,3,4];let old=values;
borrow mut values[0..4] as view{split view at MID as left,right{discard change::<i64>(left,right,VALUE);}}
return values[0]+values[1]+values[2]+values[3]+old[0];}'''.replace('MID', str(midpoint)).replace('VALUE', str(value))
    numbers = [1, 2, 3, 4]
    if midpoint:
        numbers[0] = value
    if midpoint < 4:
        numbers[midpoint] = value
    yield partition, sum(numbers) + 1, 'generic-split-snapshot'
    owner = """buffer B<T:copy>:T;result R{ok:B<i64>,err:i64}
fn inspect<T:copy>(value:&B<T>)->i64{return cast<i64>(capacity_buffer(value));}
fn main(heap:allocator)->i64{arena heap as child{match acquire_buffer<R>(child,CAP){
R.ok(b)=>{let mut capacity=0;borrow b as view{capacity=inspect::<i64>(view);}discard b;return capacity;},R.err(e)=>{return -1;}}}}"""
    capacity = rng.randrange(1, 20)
    yield owner.replace('CAP', str(capacity)), capacity, 'generic-owner-reference-arena'
